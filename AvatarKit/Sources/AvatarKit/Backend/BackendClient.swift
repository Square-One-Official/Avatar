import Foundation

/// Typed errors the backend can return. `noCredits` (HTTP 402) triggers the
/// upgrade paywall; `unauthorized` (401) triggers sign-in.
public enum BackendError: LocalizedError {
    case notSignedIn
    case unauthorized
    case noCredits
    case proRequired
    case rateLimited
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

    /// Productie = `api.aaavatar.nl`. In DEBUG kan een override de client
    /// tegen een Vercel-preview richten (E01.15): env `AAAVATAR_API_BASE` of
    /// UserDefaults `dev.apiBase` (Advanced-settings). Een Release-build
    /// negeert beide → altijd productie. TLS-pinning raakt dit niet: alleen
    /// `api.aaavatar.nl` is gepind; andere hosts (zoals *.vercel.app) vallen
    /// terug op OS-trust (TLSPinningDelegate).
    private static func resolveBaseURL() -> URL {
        let production = URL(string: "https://api.aaavatar.nl")!
        #if DEBUG
        let raw = ProcessInfo.processInfo.environment["AAAVATAR_API_BASE"]
            ?? UserDefaults.standard.string(forKey: "dev.apiBase")
        if let raw, !raw.isEmpty, let override = URL(string: raw) {
            print("[BackendClient] DEBUG baseURL override → \(override.absoluteString)")
            return override
        }
        #endif
        return production
    }

    /// Of er een sessie is (Bearer-token aanwezig). Gebruikt door
    /// CloudCutoutEngine.isAvailable (E02.4) zodat de router het cloud-pad
    /// niet kiest voor uitgelogde gebruikers; zegt niets over credits of
    /// entitlement. (Eén-regel-toevoeging buiten Engines/ — INFRA-review.)
    public var hasSession: Bool { auth.accessToken != nil }

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
    public func fillBody(imagePNG: Data, faceBox: FaceBox? = nil) async throws -> (Data, Int) {
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
        return (data, resp.creditsRemaining)
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
    /// Effects (E09.2; CMS-gestuurd sinds E33) — stuurt het huidige portret + een
    /// stijl-key naar het productie-`/v1/stylize`. De `styleKey` komt uit de
    /// CMS-lijst (`effects()`); de server mapt 'm naar de stijlprompt (incl.
    /// identity-clausule); een vrij prompt-veld is dev-only en hier bewust niet
    /// bereikbaar. nano-banana is de default;
    /// `model_override` (dev) gaat mee als de DevModelOverrides-store een keuze
    /// heeft. Resultaat = opaque styled PNG + bijgewerkt creditsaldo.
    ///
    /// Op 402 (geen credits) gooit dit `BackendError.noCredits` → de caller
    /// toont de paywall; andere fouten propageren voor de faaltoast.
    private struct StylizeResponse: Decodable {
        let image: String
        let creditsRemaining: Int          // decoded from `credits_remaining`
    }
    public func stylize(imagePNG: Data, styleKey: String) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let style: String
            let generationModel: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case style
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, style: styleKey,
                 generationModel: GenerationModelStore.shared.current.rawValue,
                 modelOverride: DevModelOverrides.shared.override(for: .stylize))
        )
        let resp: StylizeResponse = try await request("/v1/stylize", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.image) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/upscale (Boost resolution, E10.3)
    /// Verhoogt de resolutie van het cutout via Real-ESRGAN (2×). De backend
    /// flattent op grijs, upscalet de RGB en hangt het alfa herschaald weer
    /// aan, dus het resultaat blijft een transparante cutout. 1 credit; 402 →
    /// `BackendError.noCredits` (paywall).
    private struct UpscaleResponse: Decodable {
        let cutout: String
        let creditsRemaining: Int
    }
    public func upscale(imagePNG: Data) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case modelOverride = "model_override"
            }
        }
        // Geen dev-override-UI voor upscale → altijd het registry-default-model.
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey, modelOverride: nil)
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
    public func editHair(imagePNG: Data, presetKey: String? = nil, freeText: String? = nil) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let hairPreset: String?
            let hairPrompt: String?
            let generationModel: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case hairPreset = "hair_preset"
                case hairPrompt = "hair_prompt"
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey,
                 hairPreset: presetKey,
                 hairPrompt: freeText,
                 generationModel: GenerationModelStore.shared.current.rawValue,
                 modelOverride: DevModelOverrides.shared.override(for: .stylize))
        )
        let resp: StylizeResponse = try await request("/v1/stylize", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.image) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/stylize (clothes-intent, E10.4)
    /// Kledingwissel via hetzelfde productie-`/v1/stylize` (nano-banana
    /// instruction-edit, besluit Thierry 2026-06-13). Eén van `preset`/
    /// `freeText`; de server mapt het naar een clothes-only edit-prompt met
    /// het harde acceptatiecriterium (gezicht/haar/pose/achtergrond
    /// identiek). Resultaat = opaque PNG + saldo; 402 → paywall.
    public func editClothes(imagePNG: Data, presetKey: String? = nil, freeText: String? = nil) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let clothesPreset: String?
            let clothesPrompt: String?
            let generationModel: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case clothesPreset = "clothes_preset"
                case clothesPrompt = "clothes_prompt"
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey,
                 clothesPreset: presetKey,
                 clothesPrompt: freeText,
                 generationModel: GenerationModelStore.shared.current.rawValue,
                 modelOverride: DevModelOverrides.shared.override(for: .stylize))
        )
        let resp: StylizeResponse = try await request("/v1/stylize", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.image) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/stylize (face-intent, E32.1)
    /// Face beauty-edit via hetzelfde productie-`/v1/stylize` (nano-banana
    /// instruction-edit; E09.1-bakeoff koos nano voor teeth/wrinkles). De
    /// server mapt `face_preset` naar een gezicht-only edit-prompt met het
    /// harde acceptatiecriterium (identiteit/pose/haar/kleding/achtergrond
    /// identiek). Resultaat = opaque PNG + saldo; 402 → paywall.
    public func editFace(imagePNG: Data, presetKey: String) async throws -> (Data, Int) {
        let storageKey = try await uploadInputPNG(imagePNG)
        struct Body: Encodable {
            let storageKey: String
            let facePreset: String
            let generationModel: String
            let modelOverride: String?
            enum CodingKeys: String, CodingKey {
                case storageKey = "storage_key"
                case facePreset = "face_preset"
                case generationModel = "generation_model"
                case modelOverride = "model_override"
            }
        }
        let body = try JSONEncoder().encode(
            Body(storageKey: storageKey,
                 facePreset: presetKey,
                 generationModel: GenerationModelStore.shared.current.rawValue,
                 modelOverride: DevModelOverrides.shared.override(for: .stylize))
        )
        let resp: StylizeResponse = try await request("/v1/stylize", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.image) else {
            throw BackendError.decode
        }
        return (data, resp.creditsRemaining)
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
        body: Data? = nil
    ) async throws -> R {
        guard let token = auth.accessToken else { throw BackendError.notSignedIn }
        return try await send(
            path: path, method: method, body: body, token: token
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
        token: String?
    ) async throws -> R {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
        req.timeoutInterval = 120  // Magic Cutout calls can take ~15-30s

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
            throw BackendError.server(http.statusCode, msg)
        }
    }
}
