import Foundation

/// Typed errors the backend can return. `noCredits` (HTTP 402) triggers the
/// upgrade paywall; `unauthorized` (401) triggers sign-in.
public enum BackendError: LocalizedError {
    case notSignedIn
    case unauthorized
    case noCredits
    case proRequired
    case rateLimited
    /// E55: het model weigerde deze foto (moderatie/safety, HTTP 422
    /// `generation_refused`). Eigen case + eigen copy: de generieke
    /// "probeer opnieuw"-toast lokte kansloze retries van 30–60s uit,
    /// terwijl een ándere foto het echte advies is. Credits zijn veilig
    /// (server rekent pas af ná succes).
    case generationRefused
    case server(Int, String?)
    case decode
    case transport(Error)
    /// Pre-flight reject when the input PNG exceeds the Magic Cutout size
    /// limit. Surfaces a dedicated "image too large" toast instead of the
    /// generic server-error copy — the request never reaches the wire.
    case payloadTooLarge(bytes: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:   return "Please sign in to continue."
        case .unauthorized:  return "Session expired. Please sign in again."
        case .noCredits:     return "You're out of credits for this period."
        case .proRequired:   return "Pro subscription required."
        case .rateLimited:   return "Too many requests. Please wait a moment."
        case .generationRefused:
            return "This photo was declined by the safety filter. Try a different photo — no credits were charged."
        case .server(let s, let m): return m ?? "Server error (\(s))."
        case .decode:        return "Unexpected server response."
        case .transport(let e): return e.localizedDescription
        case .payloadTooLarge(_, let limit):
            return "Image is over \(limit / (1024 * 1024)) MB."
        }
    }
}

/// Result of a checkout request. The backend returns either a hosted Stripe
/// URL (DMG-build path: open in browser, listen for `aaavatar://auth-callback`
/// to refresh entitlement) or a StoreKit product ID (App Store-build path:
/// invoke `Product.purchase()`). Exactly one is non-nil.
public enum CheckoutResult {
    case web(URL)
    case storeKit(productId: String)
}

/// REST client for the Avatar backend (Vercel + Supabase).
/// Production base URL: `https://api.aaavatar.nl`.
/// All requests authenticate via the bearer token from the injected
/// `AccessTokenProviding` (v1: `AuthManager`; 2.0: `AuthService`).
@MainActor
public final class BackendClient {
    public let baseURL: URL

    /// Marketing version pulled from the app bundle, e.g. "1.1.4". Sent as
    /// `X-App-Version` on every request so the backend can gate
    /// version-targeted features (announcements with `minAppVersion`).
    public static let appVersion: String? =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    private unowned let auth: any AccessTokenProviding
    private let session: URLSession

    public init(auth: any AccessTokenProviding, session: URLSession = TLSPinning.pinnedShared) {
        self.auth = auth
        self.session = session
        self.baseURL = Self.resolveBaseURL()
    }

    #if DEBUG
    /// Waar de `dev.apiBase`-override gelezen wordt. Tests wijzen dit naar een
    /// eigen suite: `swift test --parallel` draait testmethoden in aparte
    /// processen die `UserDefaults.standard` op schijf delen, waardoor de
    /// override-tests elkaars waarde zagen (race).
    static var devOverrideDefaults: UserDefaults = .standard
    #endif

    /// Productie = `api.aaavatar.nl`. In DEBUG kan een override de client
    /// tegen een Vercel-preview richten (E01.15): env `AAAVATAR_API_BASE` of
    /// UserDefaults `dev.apiBase`. Een Release-build
    /// negeert beide → altijd productie. TLS-pinning raakt dit niet: alleen
    /// `api.aaavatar.nl` is gepind; andere hosts (zoals *.vercel.app) vallen
    /// terug op OS-trust (TLSPinningDelegate).
    private static func resolveBaseURL() -> URL {
        let production = URL(string: "https://api.aaavatar.nl")!
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["AAAVATAR_API_BASE"]
            ?? devOverrideDefaults.string(forKey: "dev.apiBase")
        if let raw, !raw.isEmpty, let override = URL(string: raw) {
            print("[BackendClient] DEBUG baseURL override → \(override.absoluteString)")
            return override
        }
        #endif
        return production
    }

    // MARK: GET /v1/account
    /// Current tier, credits, and subscription state. Drives `ProEntitlement`.
    /// Anonymous-friendly: when no Bearer token is available the server
    /// falls back to a `device_grants` lookup keyed on
    /// `X-Device-Fingerprint`. Devices that paid via the pre-auth checkout
    /// flow are reported as Pro with `needs_account_link: true`.
    public func me() async throws -> AccountPayload {
        try await requestAllowingAnonymous("/v1/account", method: "GET")
    }

    // MARK: POST /v1/import-claim
    /// Atomic anti-cheat gate. Must be called before every import (Subject
    /// Lift OR Magic Cutout) by free-tier users. The server checks the
    /// per-account counter (`users.free_imports_used`) and the per-device
    /// counter keyed on the local `DeviceFingerprint` — if either is at
    /// the cap the call returns 402 and the caller surfaces the paywall.
    /// Pro users get a short-circuit `allowed: true` without consuming any
    /// counter. Works without a signed-in session (anonymous mode hits
    /// only the device counter).
    public struct ClaimResponse: Decodable, Sendable {
        public let allowed: Bool
        public let importsUsed: Int
        public let importsRemaining: Int
        public let pro: Bool?
    }
    public func claimImport() async throws -> ClaimResponse {
        try await requestAllowingAnonymous("/v1/import-claim", method: "POST")
    }

    // MARK: POST /v1/cutout (+ /v1/cutout/upload-url)
    /// Magic Cutout — runs BiRefNet on the backend, deducts 1 credit on
    /// success. Returns the cutout PNG (foreground over transparent alpha)
    /// plus the user's updated credit balance.
    ///
    /// **v1-only.** Aaavatar 2 does Remove background on-device (Vision /
    /// ORMBG, `PipelineRouter`) and has no call site for `cutout(imagePNG:)`;
    /// the frozen v1 app (`Avatar/Services/ImageProcessor.swift`) still links
    /// it, and `Avatar/` is out of bounds outside SHARED stories. Remove this
    /// together with the v1 target, not before (release-review 2026-09-04).
    /// `uploadInputPNG` below is shared by every cloud edit and stays.
    ///
    /// The PNG is uploaded directly to Supabase Storage (private bucket,
    /// short-lived signed PUT URL) so the request body to `/v1/cutout` is
    /// just the resulting key — Vercel's 4.5 MB serverless body cap never
    /// comes into play. Replicate fetches the input from a signed read URL
    /// the backend mints; bytes never traverse Vercel.
    ///
    /// On 402 (no credits) the caller surfaces the upgrade sheet; transport
    /// or server errors fall back to Apple Subject Lift via the offline /
    /// "hiccup" toasts. Inputs larger than `Self.cutoutInputLimitBytes`
    /// throw `BackendError.payloadTooLarge` before any network I/O.
    public static let cutoutInputLimitBytes: Int = 20 * 1024 * 1024

    private struct CutoutUploadURLResponse: Decodable {
        let url: String
        let key: String
    }
    private struct CutoutResponse: Decodable {
        let cutout: String                // base64 PNG
        let creditsRemaining: Int         // decoded from `credits_remaining`
    }

    /// Uploads a PNG to the `cutout-uploads` Storage bucket via a short-lived
    /// signed PUT URL and returns the resulting object key. Used as the
    /// `storage_key` for every image-processing endpoint (cutout, stylize,
    /// colorize, fill-body, upscale) so their request bodies stay tiny and
    /// Vercel's 4.5 MB serverless body cap never applies. Throws
    /// `payloadTooLarge` for inputs over `cutoutInputLimitBytes` before any I/O.
    private func uploadInputPNG(_ imagePNG: Data) async throws -> String {
        guard imagePNG.count <= Self.cutoutInputLimitBytes else {
            throw BackendError.payloadTooLarge(
                bytes: imagePNG.count,
                limit: Self.cutoutInputLimitBytes
            )
        }

        // 1. Mint a signed PUT URL into the cutout-uploads bucket.
        let upload: CutoutUploadURLResponse = try await request(
            "/v1/cutout/upload-url", method: "POST"
        )
        guard let putURL = URL(string: upload.url) else {
            throw BackendError.decode
        }

        // 2. PUT the bytes directly to Supabase Storage. Use `upload(for:from:)`
        // rather than `data(for:)` with `httpBody` so a 20 MB body streams
        // instead of double-buffering through URLProtocol.
        var putReq = URLRequest(url: putURL)
        putReq.httpMethod = "PUT"
        putReq.setValue("image/png", forHTTPHeaderField: "Content-Type")
        // The signed URL embeds auth in the query string — no Authorization
        // header needed (and including the wrong one trips Supabase's check).
        putReq.timeoutInterval = 120
        let (_, putResponse): (Data, URLResponse)
        do {
            (_, putResponse) = try await session.upload(for: putReq, from: imagePNG)
        } catch {
            throw BackendError.transport(error)
        }
        guard let putHTTP = putResponse as? HTTPURLResponse else {
            throw BackendError.decode
        }
        guard (200...299).contains(putHTTP.statusCode) else {
            throw BackendError.server(putHTTP.statusCode, "storage upload failed")
        }
        return upload.key
    }

    public func cutout(imagePNG: Data) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)

        // Tell the backend the bytes have landed; receive the cutout.
        struct Body: Encodable {
            let storageKey: String
            let modelOverride: String?
            // Matches the snake_case the backend reads — JSONEncoder doesn't
            // apply a key-encoding strategy here so we map explicitly.
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, modelOverride: DevModelOverrides.shared.override(for: .cutout))
        )
        let resp: CutoutResponse = try await request(
            "/v1/cutout", method: "POST", body: body
        )
        guard let data = Data(base64Encoded: resp.cutout) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/fill-body
    /// Fill in Body — sends the cutout PNG to the backend, which builds a
    /// padded canvas + mask and runs FLUX.1 Fill Pro to outpaint the
    /// missing shoulders/chest, then re-extracts alpha via BiRefNet.
    /// Returns the new cutout PNG and the user's updated credit balance.
    ///
    /// On 402 (no credits) the caller surfaces the upgrade sheet; other
    /// errors propagate so the caller can show the failure toast.
    private struct FillBodyResponse: Decodable {
        let cutout: String
        let creditsRemaining: Int
        let didFill: Bool
        let mapping: FillBodyResult.Mapping
        let filledEdges: FillBodyResult.Edges
    }
    /// Normalised face rectangle (0..1, top-left origin) of the input cutout.
    /// The backend uses this to lock the face region as never-paint in the
    /// outpaint mask — strict rule: Fill in Body must never modify the face,
    /// even when alpha gaps suggest missing parts. When the client cannot
    /// detect a face the field is omitted and the backend falls back to a
    /// top-of-bbox heuristic.
    public struct FaceBox: Encodable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }
    public struct FillBodyResult: Sendable {
        public struct Mapping: Decodable, Sendable, Equatable {
            public let canvasWidth: Int
            public let canvasHeight: Int
            public let originalX: Int
            public let originalY: Int
            public let originalWidth: Int
            public let originalHeight: Int

            public init(
                canvasWidth: Int,
                canvasHeight: Int,
                originalX: Int,
                originalY: Int,
                originalWidth: Int,
                originalHeight: Int
            ) {
                self.canvasWidth = canvasWidth
                self.canvasHeight = canvasHeight
                self.originalX = originalX
                self.originalY = originalY
                self.originalWidth = originalWidth
                self.originalHeight = originalHeight
            }
        }

        public struct Edges: Decodable, Sendable, Equatable {
            public let left: Bool
            public let right: Bool
            public let bottom: Bool

            public init(left: Bool, right: Bool, bottom: Bool) {
                self.left = left
                self.right = right
                self.bottom = bottom
            }
        }

        public let data: Data
        public let creditsRemaining: Int
        public let didFill: Bool
        public let mapping: Mapping
        public let filledEdges: Edges
    }

    /// Detailed v2 contract: includes whether work was necessary and where the
    /// original pixels live in the expanded result. Deploy the backend contract
    /// before the app update so an old response cannot be applied ambiguously.
    public func fillBodyDetailed(
        imagePNG: Data,
        faceBox: FaceBox? = nil
    ) async throws -> FillBodyResult {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let face: FaceBox?
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case face
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, face: faceBox,
                 modelOverride: DevModelOverrides.shared.override(for: .fillBody))
        )
        let resp: FillBodyResponse = try await request("/v1/fill-body", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.cutout) else {
            throw BackendError.decode
        }
        return FillBodyResult(
            data: data,
            creditsRemaining: resp.creditsRemaining,
            didFill: resp.didFill,
            mapping: resp.mapping,
            filledEdges: resp.filledEdges
        )
    }

    /// Backward-compatible tuple API used by v1. New call sites should use
    /// `fillBodyDetailed` so they can preserve composition and handle no-op.
    public func fillBody(imagePNG: Data, faceBox: FaceBox? = nil) async throws -> (Data, Int) {
        let result = try await fillBodyDetailed(imagePNG: imagePNG, faceBox: faceBox)
        return (result.data, result.creditsRemaining)
    }

    // MARK: POST /v1/colorize
    /// Colorise — sends the cutout PNG to the backend, which flattens it
    /// over neutral grey, runs DeOldify on the RGB, and re-attaches the
    /// original alpha so the result is a transparent cutout in colour.
    /// Same dimensions in/out, so the client doesn't re-detect geometry.
    /// Returns the new cutout PNG and the user's updated credit balance.
    ///
    /// On 402 (no credits) the caller surfaces the upgrade sheet; other
    /// errors propagate so the caller can show the failure toast.
    private struct ColorizeResponse: Decodable {
        let cutout: String
        let creditsRemaining: Int
    }
    public func colorize(imagePNG: Data) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey,
                 modelOverride: DevModelOverrides.shared.override(for: .colorize))
        )
        let resp: ColorizeResponse = try await request("/v1/colorize", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.cutout) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/stylize

    /// Pixel dimensions returned by `/v1/stylize` (instrumentation + post-boost UI).
    public struct StylizeDimensions: Decodable, Sendable, Equatable {
        public let inputWidth: Int
        public let inputHeight: Int
        public let outputWidth: Int
        public let outputHeight: Int

        enum CodingKeys: String, CodingKey {
            case inputWidth = "input_width"
            case inputHeight = "input_height"
            case outputWidth = "output_width"
            case outputHeight = "output_height"
        }

        public var outputLongEdge: Int { max(outputWidth, outputHeight) }
    }

    /// Result of any `/v1/stylize` call (Effects, hair, clothes, face).
    public struct StylizeCallResult: Sendable {
        public let data: Data
        public let creditsRemaining: Int
        public let dimensions: StylizeDimensions?
    }

    private struct StylizeResponse: Decodable {
        /// Inline base64 (kleine resultaten) — of nil wanneer de server het
        /// resultaat via `image_url` levert (E55-delivery-fix: gpt-image-2-
        /// PNG's kunnen Vercels ~4.5MB-response-cap overschrijden).
        let image: String?
        let imageUrl: String?
        let creditsRemaining: Int
        let inputWidth: Int?
        let inputHeight: Int?
        let outputWidth: Int?
        let outputHeight: Int?

        var dimensions: StylizeDimensions? {
            guard let inputWidth, let inputHeight, let outputWidth, let outputHeight else { return nil }
            return StylizeDimensions(
                inputWidth: inputWidth, inputHeight: inputHeight,
                outputWidth: outputWidth, outputHeight: outputHeight
            )
        }
    }

    // Internal (niet private) zodat AvatarKitTests kan bewijzen dat een
    // ontbrekende modelkeuze het veld écht weglaat (E55.2) — de server-default
    // regeert dan, wat de vloot-rollback via STYLIZE_DEFAULT_MODEL mogelijk maakt.
    struct StylizeBody: Encodable {
        let storageKey: String
        /// E55.2: alléén de expliciete gebruikerskeuze; nil = veld weggelaten
        /// → server-default (gpt-image-2 voor effects, env-overridable).
        let generationModel: String?
        let modelOverride: String?
        let cutoutW: Int?
        let cutoutH: Int?
        let style: String?
        let hairPreset: String?
        let hairPrompt: String?
        let clothesPreset: String?
        let clothesPrompt: String?
        let facePreset: String?
        let softSource: Bool?
        let preserveFraming: Bool?

        enum CodingKeys: String, CodingKey {
            case storageKey = "storage_key"
            case generationModel = "generation_model"
            case modelOverride = "model_override"
            case cutoutW = "cutout_w"
            case cutoutH = "cutout_h"
            case style
            case hairPreset = "hair_preset"
            case hairPrompt = "hair_prompt"
            case clothesPreset = "clothes_preset"
            case clothesPrompt = "clothes_prompt"
            case facePreset = "face_preset"
            case softSource = "soft_source"
            case preserveFraming = "preserve_framing"
        }
    }

    private func runStylize(
        imagePNG: Data,
        cutoutWidth: Int? = nil,
        cutoutHeight: Int? = nil,
        style: String? = nil,
        hairPreset: String? = nil,
        hairPrompt: String? = nil,
        clothesPreset: String? = nil,
        clothesPrompt: String? = nil,
        facePreset: String? = nil,
        softSource: Bool = false,
        preserveFraming: Bool = false
    ) async throws -> StylizeCallResult {
        let storageKey = try await uploadInputPNG(imagePNG)
        let body = try JSONEncoder().encode(
            StylizeBody(
                storageKey: storageKey,
                generationModel: nil,
                modelOverride: DevModelOverrides.shared.override(for: .stylize),
                cutoutW: cutoutWidth,
                cutoutH: cutoutHeight,
                style: style,
                hairPreset: hairPreset,
                hairPrompt: hairPrompt,
                clothesPreset: clothesPreset,
                clothesPrompt: clothesPrompt,
                facePreset: facePreset,
                softSource: softSource ? true : nil,
                preserveFraming: preserveFraming ? true : nil
            )
        )
        let resp: StylizeResponse = try await request(
            "/v1/stylize", method: "POST", body: body, timeoutInterval: 190
        )
        let data = try await resolveStylizeImageData(resp)
        return StylizeCallResult(data: data, creditsRemaining: resp.creditsRemaining, dimensions: resp.dimensions)
    }

    /// E55-delivery-fix: het resultaat komt inline (base64, klein) óf via een
    /// signed Storage-URL (groot — Vercels ~4.5MB-cap). Beide paden leveren
    /// dezelfde PNG-bytes op.
    private func resolveStylizeImageData(_ resp: StylizeResponse) async throws -> Data {
        if let base64 = resp.image, let data = Data(base64Encoded: base64) {
            return data
        }
        if let raw = resp.imageUrl, let url = URL(string: raw) {
            return try await Self.downloadResultImage(from: url)
        }
        throw BackendError.decode
    }

    /// Effects (E09.2; CMS-gestuurd sinds E33) — stuurt het huidige portret + een
    /// stijl-key naar het productie-`/v1/stylize`. De `styleKey` komt uit de
    /// CMS-lijst (`effects()`); de server mapt 'm naar de stijlprompt (incl.
    /// identity-clausule); een vrij prompt-veld is dev-only en hier bewust niet
    /// bereikbaar. De default-engine is server-governed (E55.2: gpt-image-2,
    /// env-overridable). De app stuurt geen gebruikers-`generation_model`;
    /// `model_override` (dev) blijft. Resultaat = opaque styled PNG + bijgewerkt creditsaldo.
    ///
    /// Op 402 (geen credits) gooit dit `BackendError.noCredits` → de caller
    /// toont de paywall; andere fouten propageren voor de faaltoast.
    public func stylize(
        imagePNG: Data,
        styleKey: String,
        cutoutWidth: Int? = nil,
        cutoutHeight: Int? = nil,
        softSource: Bool = false,
        preserveFraming: Bool = false
    ) async throws -> StylizeCallResult {
        try await runStylize(
            imagePNG: imagePNG, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight,
            style: styleKey, softSource: softSource, preserveFraming: preserveFraming
        )
    }

    // MARK: POST /v1/generate-background (E42)
    /// Text-to-background voor portret/banner-achtergronden. Stuurt stijl/view-
    /// keys + beschrijving; de server bouwt de prompt. Geen upload nodig.
    public struct GenerateBackgroundCallResult: Sendable {
        public let imageData: Data
        public let creditsRemaining: Int
    }

    /// Response-vorm van `POST /v1/generate-background` (200). Internal (niet
    /// function-local) zodat de contract-test in AvatarKitTests hem tegen een
    /// fixture van de letterlijke endpoint-JSON kan decoden — E43.2, na de
    /// "Unexpected server response"-outage waarin client en backend stilletjes
    /// een verschillend contract spraken. Moet 1-op-1 blijven sporen met
    /// `backend/api/v1/generate-background.ts` (res.status(200).json).
    struct GenerateBackgroundResponse: Decodable {
        let imageUrl: String
        let creditsRemaining: Int
    }

    public func generateBackground(
        userPrompt: String,
        styleKey: String,
        customStyleText: String?,
        viewKey: String,
        targetWidth: Int,
        targetHeight: Int,
        generationModel: String?
    ) async throws -> GenerateBackgroundCallResult {
        struct Body: Encodable {
            let userPrompt: String
            let styleKey: String
            let customStyleText: String?
            let viewKey: String
            let targetWidth: Int
            let targetHeight: Int
            let generationModel: String?
            let modelOverride: String?

            enum CodingKeys: String, CodingKey {
                case userPrompt = "user_prompt"
                case styleKey = "style_key"
                case customStyleText = "custom_style_text"
                case viewKey = "view_key"
                case targetWidth = "target_width"
                case targetHeight = "target_height"
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }

        // Feature-default is server-side (generate_background = nano-banana)
        // unless the sheet passed an explicit engine key (Gemini).
        let modelKey = generationModel
        let body = try JSONEncoder().encode(
            Body(
                userPrompt: userPrompt,
                styleKey: styleKey,
                customStyleText: customStyleText,
                viewKey: viewKey,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                generationModel: modelKey,
                modelOverride: DevModelOverrides.shared.override(for: .generateBackground)
            )
        )
        let resp: GenerateBackgroundResponse = try await request("/v1/generate-background", method: "POST", body: body)
        guard let url = URL(string: resp.imageUrl) else {
            throw BackendError.decode
        }
        let data = try await Self.downloadResultImage(from: url)
        return GenerateBackgroundCallResult(imageData: data, creditsRemaining: resp.creditsRemaining)
    }

    // MARK: POST /v1/stylize (custom effect, E34)
    /// Past een gebruiker-gemaakt custom effect toe: stuurt het portret + de
    /// `custom_effect_id` (i.p.v. een `style`-key). De server zoekt de eigen rij
    /// op, giet de opgeslagen beschrijving in het custom-sjabloon en hangt de
    /// referentie-afbeelding als tweede beeld aan de model-call (stijlreferentie).
    /// Pro-only (403 `pro_required` → `BackendError.proRequired`); 402 → paywall.
    /// Zelfde response-vorm als `stylize(imagePNG:styleKey:)`; `dimensions` blijft
    /// nil (de custom-tak stuurt geen cutout-maten mee).
    public func stylize(imagePNG: Data, customEffectID: String) async throws -> StylizeCallResult {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let customEffectId: String
            let generationModel: String?
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case customEffectId = "custom_effect_id"
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, customEffectId: customEffectID,
                 generationModel: nil,
                 modelOverride: DevModelOverrides.shared.override(for: .stylize))
        )
        let resp: StylizeResponse = try await request(
            "/v1/stylize", method: "POST", body: body, timeoutInterval: 190
        )
        let data = try await resolveStylizeImageData(resp)
        return StylizeCallResult(data: data, creditsRemaining: resp.creditsRemaining, dimensions: nil)
    }

    /// Downloads a generated RESULT image from the short-lived signed Supabase
    /// Storage URL returned by `/v1/generate-background`. The result is handed
    /// over as a URL rather than inline base64 because a full-frame background
    /// can exceed Vercel's ~4.5 MB response body cap (which would truncate the
    /// body and leave the user charged with no image).
    ///
    /// Uses a plain session, not `TLSPinning.pinnedShared`: the host is
    /// `*.supabase.co`, which is deliberately not pinned (Supabase rotates
    /// certs across tenants — see `TLSPinning`), and the signed token already
    /// authorizes the fetch. Retries a few times so a transient CDN hiccup on
    /// this second hop doesn't waste the (already-charged) generation.
    private static let resultDownloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()

    /// Test-seam (E47.1): laat tests de result-download door hun stub-sessie
    /// leiden. `resultDownloadSession` is bewust privé/statisch (aparte
    /// niet-gepinde sessie voor *.supabase.co), dus zonder deze haak is
    /// `generateBackground` niet integraal testbaar. Internal — alleen
    /// bereikbaar via `@testable import`; blijft `nil` in productie.
    static var resultDownloadSessionOverride: URLSession?

    private static func downloadResultImage(from url: URL) async throws -> Data {
        let session = resultDownloadSessionOverride ?? resultDownloadSession
        var lastError: Error?
        for attempt in 0..<3 {
            // Honour cooperative cancellation: if the user cancelled the
            // generation, bail immediately instead of burning retries. Both
            // checkCancellation and a cancelled URLSession task surface as
            // CancellationError so the caller's `catch is CancellationError`
            // path returns silently (no error banner, no wasted refresh).
            try Task.checkCancellation()
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            }
            do {
                let (data, response) = try await session.data(from: url)
                guard
                    let http = response as? HTTPURLResponse,
                    (200...299).contains(http.statusCode),
                    !data.isEmpty
                else {
                    lastError = BackendError.decode
                    continue
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BackendError.decode
    }

    // MARK: POST /v1/upscale (Boost resolution, E10.3 · tiers E41.5)

    /// E41.5: de twee betaalde upscale-tiers. Raw values = het `quality`-veld
    /// van `/v1/upscale`; het tarief hoort erbij via `creditAction`.
    public enum UpscaleQuality: String, Sendable {
        /// google/upscaler x2 — 1 credit.
        case regular
        /// Topaz High Fidelity V2 (server capt input op 6 MP) — 3 credits.
        case high

        public var creditAction: CreditMeter.Action {
            self == .high ? .upscaleHigh : .upscale
        }
    }

    /// Verhoogt de resolutie van het cutout (2×). De backend flattent met
    /// edge-bleed, upscalet de RGB via het tier-model en hangt het alfa
    /// herschaald weer aan, dus het resultaat blijft een transparante cutout.
    /// Tarief per tier (zie `UpscaleQuality`); 402 → `BackendError.noCredits`
    /// (paywall).
    private struct UpscaleResponse: Decodable {
        let cutout: String
        let creditsRemaining: Int
    }
    public func upscale(imagePNG: Data, quality: UpscaleQuality = .regular) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let quality: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case quality
                case modelOverride = "model_override"
            }
        }
        // Geen dev-override-UI voor upscale → de tier bepaalt het model.
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, quality: quality.rawValue, modelOverride: nil)
        )
        let resp: UpscaleResponse = try await request("/v1/upscale", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.cutout) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/stylize (hair-intent, E11.2)
    /// Kapselwissel via hetzelfde productie-`/v1/stylize` (nano-banana
    /// instruction-edit, E11.1-route). Eén van `preset`/`freeText` wordt
    /// meegestuurd; de server mapt het naar een hair-only edit-prompt. Vrije
    /// tekst gaat als `hair_prompt` (server giet het in een vast sjabloon —
    /// geen rauwe instructie). Resultaat = opaque PNG + bijgewerkt saldo;
    /// 402 → `BackendError.noCredits` (paywall).
    public func editHair(
        imagePNG: Data,
        presetKey: String? = nil,
        freeText: String? = nil,
        cutoutWidth: Int? = nil,
        cutoutHeight: Int? = nil,
        softSource: Bool = false
    ) async throws -> StylizeCallResult {
        try await runStylize(
            imagePNG: imagePNG, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight,
            hairPreset: presetKey, hairPrompt: freeText, softSource: softSource,
            preserveFraming: true
        )
    }

    // MARK: POST /v1/stylize (clothes-intent, E10.4)
    /// Kledingwissel via hetzelfde productie-`/v1/stylize` (nano-banana
    /// instruction-edit, besluit Thierry 2026-06-13). Eén van `preset`/
    /// `freeText`; de server mapt het naar een clothes-only edit-prompt met
    /// het harde acceptatiecriterium (gezicht/haar/pose/achtergrond
    /// identiek). Resultaat = opaque PNG + saldo; 402 → paywall.
    public func editClothes(
        imagePNG: Data,
        presetKey: String? = nil,
        freeText: String? = nil,
        cutoutWidth: Int? = nil,
        cutoutHeight: Int? = nil,
        softSource: Bool = false
    ) async throws -> StylizeCallResult {
        try await runStylize(
            imagePNG: imagePNG, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight,
            clothesPreset: presetKey, clothesPrompt: freeText, softSource: softSource,
            preserveFraming: true
        )
    }

    // MARK: POST /v1/stylize (face-intent, E32.1)
    /// Face beauty-edit via hetzelfde productie-`/v1/stylize` (nano-banana
    /// instruction-edit; E09.1-bakeoff koos nano voor teeth/wrinkles). De
    /// server mapt `face_preset` naar een gezicht-only edit-prompt met het
    /// harde acceptatiecriterium (identiteit/pose/haar/kleding/achtergrond
    /// identiek). E32.4: `preserve_framing` gaat altijd mee, net als bij
    /// hair/clothes — zonder de framing-clausule herkadreerde nano-banana
    /// face-edits soms (≥2% ratio-drift → transform-reset in de client).
    /// Resultaat = opaque PNG + saldo; 402 → paywall.
    public func editFace(
        imagePNG: Data,
        presetKey: String,
        cutoutWidth: Int? = nil,
        cutoutHeight: Int? = nil,
        softSource: Bool = false
    ) async throws -> StylizeCallResult {
        try await runStylize(
            imagePNG: imagePNG, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight,
            facePreset: presetKey, softSource: softSource,
            preserveFraming: true
        )
    }

    // MARK: POST /v1/checkout/subscribe-anonymous
    /// Start a subscription checkout WITHOUT requiring a signed-in user.
    /// Stripe collects the email during checkout; the webhook links that
    /// email to a Supabase auth user and writes a `device_grants` row so
    /// `me()` recognises this Mac as Pro on subsequent calls. The macOS
    /// app's primary subscribe path goes through here — sign-in only
    /// happens later, optionally, via the "Sync across Macs" magic link.
    public func subscribeAnonymous(interval: SubscriptionInterval = .month) async throws -> CheckoutResult {
        struct Body: Encodable { let interval: String }
        let body = try JSONEncoder().encode(Body(interval: interval.rawValue))
        let resp: CheckoutResponse = try await requestAllowingAnonymous(
            "/v1/checkout/subscribe-anonymous", method: "POST", body: body
        )
        return try resp.toResult()
    }

    // MARK: POST /v1/checkout/subscribe (authed)
    /// Start a subscription checkout for the SIGNED-IN user — the checkout is
    /// tied to the Supabase user-id (and reuses their Stripe customer), so no
    /// duplicate customer is created. Use this whenever a session exists
    /// (E14.6 review-fix); `subscribeAnonymous` is for signed-out users only.
    /// Same body/response shape as the anonymous endpoint.
    public func subscribe(interval: SubscriptionInterval = .month) async throws -> CheckoutResult {
        struct Body: Encodable { let interval: String }
        let body = try JSONEncoder().encode(Body(interval: interval.rawValue))
        let resp: CheckoutResponse = try await request(
            "/v1/checkout/subscribe", method: "POST", body: body
        )
        return try resp.toResult()
    }

    // MARK: POST /v1/account/resend-magic-link
    /// Asks the backend to email a Supabase magic-link to the address on
    /// file (the email Stripe captured during the pre-auth checkout). The
    /// link deep-links back to `aaavatar://auth-callback` and signs the
    /// user in on whichever Mac they click it from. Authenticated by
    /// `X-Device-Fingerprint` matching a `device_grants` row.
    private struct ResendMagicLinkResponse: Decodable {
        let sent: Bool
        let email: String?
    }
    @discardableResult
    public func resendMagicLink() async throws -> String? {
        let resp: ResendMagicLinkResponse = try await requestAllowingAnonymous(
            "/v1/account/resend-magic-link", method: "POST"
        )
        return resp.email
    }

    // MARK: POST /v1/account/delete (E15.7)
    /// GDPR art. 17 — verwijdert het account definitief. Server-side
    /// (backend/api/v1/account/delete.ts): cancelt actieve Stripe-
    /// subscriptions, veegt de cutout-uploads-prefix en wist de Supabase-
    /// auth-user via de GoTrue admin API (FK-cascade ruimt de rest op).
    /// Vereist een sessie (JWT = consent-signaal) plus de
    /// `X-Confirm-Delete: yes`-header als tweede consent. POST i.p.v.
    /// DELETE — het endpoint accepteert beide en URLSession is
    /// inconsistent met DELETE+body.
    private struct DeleteAccountResponse: Decodable {
        let deleted: Bool
    }
    public func deleteAccount() async throws {
        let resp: DeleteAccountResponse = try await request(
            "/v1/account/delete", method: "POST",
            extraHeaders: ["X-Confirm-Delete": "yes"]
        )
        // Het endpoint stuurt `deleted:false` alleen met een 5xx (dan is de
        // server-throw hierboven al gebeurd), maar guard defensief.
        guard resp.deleted else { throw BackendError.server(500, "delete_failed") }
    }

    // MARK: GET /v1/billing (Settings › Billing & Invoices)
    /// Huidig plan (lijstprijs, korting, volgende afschrijving) + factuur-
    /// historie uit Stripe. Vereist een sessie; zonder Stripe-customer stuurt
    /// de server `plan: null, invoices: []` (Starter).
    public func billing() async throws -> BillingPayload {
        try await request("/v1/billing", method: "GET")
    }

    // MARK: POST /v1/checkout/topup
    /// Buy a one-time credit pack. Topped-up credits stack with the monthly
    /// grant and never expire. Same union response shape as `subscribe()`.
    public func topup(pack: CreditPack) async throws -> CheckoutResult {
        struct Body: Encodable { let pack: String }
        let body = try JSONEncoder().encode(Body(pack: pack.rawValue))
        let resp: CheckoutResponse = try await request("/v1/checkout/topup", method: "POST", body: body)
        return try resp.toResult()
    }

    /// Wire response for the two `/v1/checkout/*` endpoints. Snake-case
    /// `storekit_product_id` decodes via the global `.convertFromSnakeCase`
    /// strategy in `request<R>`.
    private struct CheckoutResponse: Decodable {
        let url: String?
        let storekitProductId: String?

        func toResult() throws -> CheckoutResult {
            if let raw = url, let parsed = URL(string: raw) { return .web(parsed) }
            if let pid = storekitProductId { return .storeKit(productId: pid) }
            throw BackendError.decode
        }
    }

    // MARK: POST /v1/portal
    /// Stripe Customer Portal URL — opens in the user's browser so they can
    /// update payment method, view invoices, and cancel their subscription.
    /// Wired to the "Manage Subscription" button in Settings.
    private struct PortalResponse: Decodable { let url: String }
    public func openPortal() async throws -> URL {
        let resp: PortalResponse = try await request("/v1/portal", method: "POST")
        guard let url = URL(string: resp.url) else { throw BackendError.decode }
        return url
    }

    // MARK: GET /v1/announcements/pending
    /// Next unseen feature announcement for the signed-in user. Authored
    /// in the Payload CMS at admin.aaavatar.nl and surfaced as a sheet on
    /// sign-in. Returns nil when the user is fully caught up.
    private struct PendingResponse: Decodable {
        let announcement: Announcement?
    }
    public func fetchPendingAnnouncement() async throws -> Announcement? {
        let resp: PendingResponse = try await request("/v1/announcements/pending", method: "GET")
        return resp.announcement
    }

    // MARK: POST /v1/announcements/seen
    /// Marks an announcement as seen. Idempotent on (user, slug) — safe to
    /// call from both the dismiss tap and `.onDisappear`.
    public func markAnnouncementSeen(slug: String, action: String) async throws {
        struct Body: Encodable { let slug: String; let action: String }
        let body = try JSONEncoder().encode(Body(slug: slug, action: action))
        struct Empty: Decodable { let ok: Bool }
        let _: Empty = try await request("/v1/announcements/seen", method: "POST", body: body)
    }

    // MARK: GET /v1/badges
    /// Active "NEW" badges keyed by componentId. Server filters out badges
    /// whose tied announcement the user has already dismissed.
    private struct BadgesResponse: Decodable {
        let badges: [AnnouncementBadge]
    }
    public func fetchBadges() async throws -> [AnnouncementBadge] {
        let resp: BadgesResponse = try await requestAllowingAnonymous("/v1/badges", method: "GET")
        return resp.badges
    }

    // MARK: GET /v1/effects (CMS-gestuurd, E33)
    /// De Effects-stijlen (kaart + thumbnail + key) uit Payload. Vervangt de
    /// hardgecodeerde `StylizeStyle`-enum zodat een nieuw effect zonder app-
    /// release verschijnt. Anoniem-vriendelijk (de lijst is niet-geheim), net als
    /// `/v1/badges`; de prompt blijft server-side en zit bewust niet in de
    /// respons. Het paneel valt terug op `RemoteEffect.fallback` als dit faalt.
    private struct EffectsResponse: Decodable {
        let effects: [RemoteEffect]
    }
    public func effects() async throws -> [RemoteEffect] {
        let resp: EffectsResponse = try await requestAllowingAnonymous("/v1/effects", method: "GET")
        return resp.effects
    }

    // MARK: /v1/custom-effects (E34) — user-created effects, synced per account
    /// De eigen custom effecten (kaart + thumbnail = referentiebeeld + id). Pro-
    /// only (403 `pro_required` → `BackendError.proRequired`); de prompt (de
    /// beschrijving) blijft server-side, net als bij `effects()`. Vereist een
    /// sessie (niet anoniem) — custom effecten horen bij een account.
    private struct CustomEffectsResponse: Decodable {
        let effects: [RemoteCustomEffect]
    }
    public func customEffects() async throws -> [RemoteCustomEffect] {
        let resp: CustomEffectsResponse = try await request("/v1/custom-effects", method: "GET")
        return resp.effects
    }

    /// Maakt een custom effect: uploadt het referentiebeeld via de upload-bypass
    /// (zoals stylize/cutout) en stuurt de key + beschrijving (+ optioneel label)
    /// naar `POST /v1/custom-effects`. De server her-bewaart het beeld in de
    /// publieke `custom-effects`-bucket (referentie + thumbnail) en geeft de
    /// nieuwe rij terug. Pro-only; genereren kost niets — pas het tóépassen
    /// (apply) kost een credit via `stylize(imagePNG:customEffectID:)`.
    private struct CreateCustomEffectResponse: Decodable {
        let effect: RemoteCustomEffect
    }
    public func createCustomEffect(
        description: String,
        label: String?,
        referencePNG: Data
    ) async throws -> RemoteCustomEffect {
        let storageKey = try await uploadInputPNG(referencePNG)
        struct Body: Encodable {
            let storageKey: String
            let description: String
            let label: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case description
                case label
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, description: description, label: label)
        )
        let resp: CreateCustomEffectResponse = try await request(
            "/v1/custom-effects", method: "POST", body: body
        )
        return resp.effect
    }

    /// Verwijdert een eigen custom effect (rij + referentiebeeld). Pro-only,
    /// eigenaar-gescoped (404 als de rij niet bestaat/niet van jou is).
    public func deleteCustomEffect(id: String) async throws {
        struct Empty: Decodable { let ok: Bool }
        let _: Empty = try await request("/v1/custom-effects/\(id)", method: "DELETE")
    }

    // MARK: GET /v1/banner-presets (CMS-gestuurd, E39)
    /// Banner-Studio-startpunten. Anoniem-vriendelijk; de empty-state/home
    /// valt terug op lokale presets als dit faalt.
    private struct BannerPresetsResponse: Decodable {
        // Envelope-key `banner_presets` → `bannerPresets` via .convertFromSnakeCase.
        let bannerPresets: [RemoteBannerPreset]
    }
    public func bannerPresets() async throws -> [RemoteBannerPreset] {
        let resp: BannerPresetsResponse = try await requestAllowingAnonymous("/v1/banner-presets", method: "GET")
        return resp.bannerPresets
    }

    // MARK: GET /v1/app-config (CMS-gestuurd, E33+)
    /// App-brede visuele configuratie. Anoniem-vriendelijk.
    public func appConfig() async throws -> RemoteAppConfig {
        let resp: RemoteAppConfigResponse = try await requestAllowingAnonymous("/v1/app-config", method: "GET")
        return RemoteAppConfig(
            splashBackgroundUrl: resp.splashBackgroundUrl,
            emptyStateAvatarUrls: resp.emptyStateAvatarUrls,
            gradientPresets: resp.gradientPresets,
            paywallProFeatures: resp.paywallProFeatures
        )
    }

    // MARK: GET /v1/hair-presets, /v1/clothes-presets, /v1/face-presets (CMS, E33+)
    /// Kapsel-presets voor het Hair-paneel. Anoniem-vriendelijk; soft-fail → [].
    public func hairPresets() async throws -> [RemotePreset] {
        let resp: RemotePresetsResponse = try await requestAllowingAnonymous("/v1/hair-presets", method: "GET")
        return resp.presets
    }

    /// Kleding-presets voor het Clothes-paneel. Anoniem-vriendelijk; soft-fail → [].
    public func clothesPresets() async throws -> [RemotePreset] {
        let resp: RemotePresetsResponse = try await requestAllowingAnonymous("/v1/clothes-presets", method: "GET")
        return resp.presets
    }

    /// Face beauty-presets voor het Face-paneel. Anoniem-vriendelijk; soft-fail → [].
    public func facePresets() async throws -> [RemotePreset] {
        let resp: RemotePresetsResponse = try await requestAllowingAnonymous("/v1/face-presets", method: "GET")
        return resp.presets
    }

    // MARK: GET /v1/feature-flags (CMS-gestuurd, E33+)
    /// Remote feature flags. Anoniem-vriendelijk; soft-fail → allEnabled.
    public func featureFlags() async throws -> RemoteFeatureFlags {
        try await requestAllowingAnonymous("/v1/feature-flags", method: "GET")
    }

    // MARK: GET /v1/backgrounds (CMS-gestuurd, E33+)
    /// CMS-achtergronden gegroepeerd op categorie. Anoniem-vriendelijk.
    /// Het paneel toont elke unieke `category`-waarde als een gelabelde sectie.
    private struct BackgroundsResponse: Decodable {
        let backgrounds: [RemoteBackground]
    }
    public func backgrounds() async throws -> [RemoteBackground] {
        let resp: BackgroundsResponse = try await requestAllowingAnonymous("/v1/backgrounds", method: "GET")
        return resp.backgrounds
    }

    // MARK: POST /v1/unsplash (UX-audit background-paneel, 2026-07-03)
    /// Zoek (of blader, bij lege query) Unsplash-achtergronden via de
    /// backend-proxy — de access key blijft server-side. Anoniem-vriendelijk,
    /// zelfde soft-fail-gedachte als /v1/backgrounds. POST i.p.v. GET met
    /// query-string: `send` bouwt URL's via `appendingPathComponent`, dat een
    /// "?" zou percent-encoden.
    public func unsplashPhotos(query: String?) async throws -> UnsplashFeed {
        struct Body: Encodable { let q: String? }
        let body = try JSONEncoder().encode(Body(q: query))
        return try await requestAllowingAnonymous("/v1/unsplash", method: "POST", body: body)
    }

    /// Unsplash-guideline: registreer een download op het moment dat een foto
    /// daadwerkelijk als achtergrond wordt toegepast. Best-effort — een
    /// gemiste registratie mag apply nooit blokkeren.
    public func unsplashTrackDownload(_ downloadLocation: String) async {
        struct Body: Encodable { let track: String }
        struct OkResponse: Decodable { let ok: Bool }
        guard let body = try? JSONEncoder().encode(Body(track: downloadLocation)) else { return }
        _ = try? await requestAllowingAnonymous(
            "/v1/unsplash", method: "POST", body: body
        ) as OkResponse
    }

    // MARK: GET /v1/messages (E17.3)
    /// Getargete in-app-berichten (verenigd Message-model, E17.2). De server
    /// filtert op cohort/signup-datum/app-versie/platform/expiry/seen; de
    /// client krijgt de lijst en beheert de queue (MessagingService).
    private struct MessagesResponse: Decodable {
        let messages: [Message]
    }
    public func fetchMessages() async throws -> [Message] {
        let resp: MessagesResponse = try await request("/v1/messages", method: "GET")
        return resp.messages
    }

    /// Markeer een bericht als gezien/gedismissed. Hergebruikt het
    /// announcement-seen-endpoint (gedeelde `announcement_seen`-tabel die
    /// /v1/messages óók leest), zodat dismiss server-side persisteert.
    public func markMessageSeen(slug: String, action: String) async throws {
        try await markAnnouncementSeen(slug: slug, action: action)
    }

    // MARK: - Generic request
    private func request<R: Decodable>(
        _ path: String,
        method: String,
        body: Data? = nil,
        extraHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 120
    ) async throws -> R {
        guard let token = auth.accessToken else { throw BackendError.notSignedIn }
        return try await send(
            path: path, method: method, body: body, token: token,
            extraHeaders: extraHeaders, timeoutInterval: timeoutInterval
        )
    }

    /// Variant of `request` that omits the Authorization header when the
    /// user isn't signed in. Used by `/v1/import-claim`, which must work
    /// for anonymous (signed-out) users so the device-counter cap still
    /// applies before the user has logged in.
    private func requestAllowingAnonymous<R: Decodable>(
        _ path: String,
        method: String,
        body: Data? = nil
    ) async throws -> R {
        try await send(
            path: path, method: method, body: body, token: auth.accessToken
        )
    }

    private func send<R: Decodable>(
        path: String,
        method: String,
        body: Data?,
        token: String?,
        extraHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval = 120
    ) async throws -> R {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Endpoint-specifieke headers (E15.7: `X-Confirm-Delete` voor
        // account-delete). Bewust vóór de vaste headers hieronder, zodat een
        // extra header nooit een standaardheader kan overschrijven.
        for (field, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: field)
        }
        // Stable per-Mac identifier for the free-tier anti-cheat layer.
        // Sent on every request so the backend can cross-reference the
        // device against the user's account if one is signed in.
        req.setValue(DeviceFingerprint.current, forHTTPHeaderField: "X-Device-Fingerprint")
        // Marketing version (e.g. "1.1.4"). Used by the announcements
        // feed to enforce minAppVersion gates so a "what's new in 1.2"
        // pop-up doesn't fire on a 1.1 client where the feature isn't
        // present yet.
        if let version = Self.appVersion {
            req.setValue(version, forHTTPHeaderField: "X-App-Version")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        #if DEBUG
        // E01.15: Vercel-preview deployment-protection bypass, zodat een
        // DEBUG-build de beveiligde preview kan bereiken. Alleen actief als
        // gezet (env `VERCEL_PROTECTION_BYPASS` of UserDefaults
        // `dev.vercelBypass`); geen effect op productie/Release.
        if let bypass = ProcessInfo.processInfo.environment["VERCEL_PROTECTION_BYPASS"]
            ?? UserDefaults.standard.string(forKey: "dev.vercelBypass"), !bypass.isEmpty {
            req.setValue(bypass, forHTTPHeaderField: "x-vercel-protection-bypass")
            req.setValue("true", forHTTPHeaderField: "x-vercel-set-bypass-cookie")
        }
        #endif
        req.httpBody = body
        // Default 120s (Magic Cutout ~15-30s); stylize geeft 190s mee —
        // E55-delivery-fix: het serverbudget is 160s + upload/download-marge,
        // en een client die eerder opgeeft dan de server laat de gebruiker
        // betalen voor een resultaat dat nooit aankomt.
        req.timeoutInterval = timeoutInterval

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw BackendError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw BackendError.decode }
        switch http.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                return try decoder.decode(R.self, from: data)
            } catch {
                throw BackendError.decode
            }
        case 401: throw BackendError.unauthorized
        case 402: throw BackendError.noCredits
        case 429: throw BackendError.rateLimited
        default:
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            if http.statusCode == 403, msg == "pro_required" {
                throw BackendError.proRequired
            }
            if http.statusCode == 422, msg == "generation_refused" {
                throw BackendError.generationRefused
            }
            throw BackendError.server(http.statusCode, msg)
        }
    }
}
