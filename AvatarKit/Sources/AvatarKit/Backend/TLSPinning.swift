import CryptoKit
import Foundation
import Security

/// Certificate pinning for `api.aaavatar.nl` (audit CRITICAL #4). Before
/// this change every backend request trusted the OS root store — a rogue
/// CA or a man-in-the-middle on a hostile network could swap in a valid
/// cert and steal the JWT bearer. Pinning blocks that even when the cert
/// chain validates conventionally.
///
/// Pinning strategy: we hash the full DER bytes of each cert in the
/// server's chain and accept the chain iff ANY hash matches a pin. Pins
/// are intermediate + root rather than the leaf because Let's Encrypt
/// rotates leaves every ~90 days; the leaf hash would be stale before a
/// release shipped.
///
/// Failure mode is intentional: when no pin matches, the request is
/// cancelled (`NSURLErrorCancelled` / `NSURLErrorServerCertificateUntrusted`)
/// and `BackendClient` surfaces it as a transport error. The user sees the
/// "Couldn't reach the server" banner. We never silently fall back to OS
/// trust — that would defeat the point of pinning.
///
/// Scope: only `api.aaavatar.nl` is pinned. The cutout upload flow PUTs
/// to a short-lived signed `*.supabase.co` URL; Supabase manages certs
/// across thousands of tenants and we can't pin those without baking in
/// constant maintenance. ATS still enforces hostname + chain validity on
/// the Supabase path.
///
/// Rotation: when Vercel switches CAs or Let's Encrypt issues a new
/// intermediate (R15+), extract the new chain via:
///
///   echo | openssl s_client -showcerts -servername api.aaavatar.nl \
///       -connect api.aaavatar.nl:443 2>/dev/null \
///       | openssl x509 -outform der \
///       | openssl dgst -sha256 -binary \
///       | openssl enc -base64
///
/// and add the new hash to `pinnedCertHashesBase64` BEFORE the old one is
/// retired. Users on older builds keep working until they update.
public enum TLSPinning {
    /// Hosts that get the pin check. Anything else uses the OS trust
    /// store (ATS still applies — hostname + chain validity are still
    /// enforced).
    public static let pinnedHosts: Set<String> = ["api.aaavatar.nl"]

    /// SHA256(cert-DER), base64. ANY match in the chain accepts.
    public static let pinnedCertHashesBase64: [String] = [
        // Let's Encrypt R13 — intermediate, signed by ISRG Root X1.
        // Valid until 2027-03-12. Currently issuing api.aaavatar.nl.
        "07EoIWqEP47xMhUB9d9Spd9Sk57iwZKXcSzT3k1Bk1Q=",
        // ISRG Root X1 — root, valid until 2035-06-04. Fallback if
        // Vercel hops between LE intermediates (R10..R14) without us
        // shipping an update.
        "lrzsBiZJdvN0YHeazyjFp8/oo8Cq4RqP/O4FwL3fCMY=",
    ]

    /// Long-lived URLSession with pinning + TLS 1.2+ enforced. One per
    /// process; reused by `BackendClient` for every request. URLSession
    /// keeps a strong reference to its delegate, so the delegate lives as
    /// long as the session does.
    public static let pinnedShared: URLSession = {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let delegate = TLSPinningDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
}

public final class TLSPinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedHosts: Set<String>
    private let pins: Set<Data>

    public init(
        pinnedHosts: Set<String> = TLSPinning.pinnedHosts,
        pinsBase64: [String] = TLSPinning.pinnedCertHashesBase64
    ) {
        self.pinnedHosts = pinnedHosts
        self.pins = Set(pinsBase64.compactMap { Data(base64Encoded: $0) })
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Unpinned hosts fall through to OS default — ATS still applies.
        if !pinnedHosts.contains(host) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Default trust evaluation first: hostname, chain, validity. If
        // the OS doesn't trust the cert, we shouldn't either. This catches
        // expired certs, mismatched SANs, etc. before we ever look at the
        // pin set.
        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if pinMatches(serverTrust: serverTrust) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Loud log so an unintended cert rotation surfaces in
            // production diagnostics before the user-facing banner.
            print("[TLSPinning] no pin match for \(host) — rejecting connection")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func pinMatches(serverTrust: SecTrust) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return false
        }
        for cert in chain {
            let der = SecCertificateCopyData(cert) as Data
            let hash = Data(SHA256.hash(data: der))
            if pins.contains(hash) {
                return true
            }
        }
        return false
    }
}
