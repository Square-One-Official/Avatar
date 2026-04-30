import Foundation

/// Typed errors the backend can return. `noCredits` (HTTP 402) triggers the
/// upgrade paywall; `unauthorized` (401) triggers sign-in.
enum BackendError: LocalizedError {
    case notSignedIn
    case unauthorized
    case noCredits
    case proRequired
    case rateLimited
    case server(Int, String?)
    case decode
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:   return "Please sign in to continue."
        case .unauthorized:  return "Session expired. Please sign in again."
        case .noCredits:     return "You're out of credits for this period."
        case .proRequired:   return "Pro subscription required."
        case .rateLimited:   return "Too many requests. Please wait a moment."
        case .server(let s, let m): return m ?? "Server error (\(s))."
        case .decode:        return "Unexpected server response."
        case .transport(let e): return e.localizedDescription
        }
    }
}

/// Result of a checkout request. The backend returns either a hosted Stripe
/// URL (DMG-build path: open in browser, listen for `aaavatar://auth-callback`
/// to refresh entitlement) or a StoreKit product ID (App Store-build path:
/// invoke `Product.purchase()`). Exactly one is non-nil.
enum CheckoutResult {
    case web(URL)
    case storeKit(productId: String)
}

/// REST client for the Avatar backend (Vercel + Supabase).
/// Production base URL: `https://api.aaavatar.nl`.
/// All requests authenticate via the bearer token from `AuthManager`.
@MainActor
final class BackendClient {
    let baseURL: URL = URL(string: "https://api.aaavatar.nl")!

    private unowned let auth: AuthManager
    private let session: URLSession

    init(auth: AuthManager, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: GET /v1/account
    /// Current tier, credits, and subscription state. Drives `ProEntitlement`.
    func me() async throws -> AccountPayload {
        try await request("/v1/account", method: "GET")
    }

    // MARK: POST /v1/import-claim
    /// Atomic anti-cheat gate. Must be called before every import (Subject
    /// Lift OR Magic Cutout) by free-tier users. The server checks the
    /// per-account counter (`users.free_imports_used`) and the per-device
    /// counter keyed on the Keychain `DeviceFingerprint` — if either is at
    /// the cap the call returns 402 and the caller surfaces the paywall.
    /// Pro users get a short-circuit `allowed: true` without consuming any
    /// counter. Works without a signed-in session (anonymous mode hits
    /// only the device counter).
    struct ClaimResponse: Decodable {
        let allowed: Bool
        let importsUsed: Int
        let importsRemaining: Int
        let pro: Bool?
    }
    func claimImport() async throws -> ClaimResponse {
        try await requestAllowingAnonymous("/v1/import-claim", method: "POST")
    }

    // MARK: POST /v1/cutout
    /// Magic Cutout — proxies to fal.ai BiRefNet on the backend, deducts
    /// 1 credit on success. Returns the cutout PNG (foreground over
    /// transparent alpha) plus the user's updated credit balance.
    /// On 402 (no credits) the caller surfaces the upgrade sheet; on
    /// any other transport/server error the caller falls back to Apple
    /// Subject Lift and shows the offline toast.
    private struct CutoutResponse: Decodable {
        let cutout: String                // base64 PNG
        let creditsRemaining: Int         // decoded from `credits_remaining`
    }
    func cutout(imagePNG: Data) async throws -> (Data, Int) {
        struct Body: Encodable { let image: String }
        let body = try JSONEncoder().encode(Body(image: imagePNG.base64EncodedString()))
        let resp: CutoutResponse = try await request("/v1/cutout", method: "POST", body: body)
        guard let data = Data(base64Encoded: resp.cutout) else { throw BackendError.decode }
        return (data, resp.creditsRemaining)
    }

    // MARK: POST /v1/checkout/subscribe
    /// Start a subscription checkout. Server picks the tier from the user
    /// account (single Pro tier currently). Returns a Stripe URL or a
    /// StoreKit product ID — caller branches on the `CheckoutResult`.
    func subscribe() async throws -> CheckoutResult {
        let resp: CheckoutResponse = try await request("/v1/checkout/subscribe", method: "POST")
        return try resp.toResult()
    }

    // MARK: POST /v1/checkout/topup
    /// Buy a one-time credit pack. Topped-up credits stack with the monthly
    /// grant and never expire. Same union response shape as `subscribe()`.
    func topup(pack: CreditPack) async throws -> CheckoutResult {
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
    func openPortal() async throws -> URL {
        let resp: PortalResponse = try await request("/v1/portal", method: "POST")
        guard let url = URL(string: resp.url) else { throw BackendError.decode }
        return url
    }

    // MARK: - Generic request
    private func request<R: Decodable>(
        _ path: String,
        method: String,
        body: Data? = nil
    ) async throws -> R {
        guard let token = auth.accessToken else { throw BackendError.notSignedIn }
        return try await send(
            path: path, method: method, body: body, token: token,
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
            path: path, method: method, body: body, token: auth.accessToken,
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
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
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
