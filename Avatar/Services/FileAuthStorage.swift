import Foundation
import Auth

/// `AuthLocalStorage` implementation backed by a sandboxed file instead of the
/// Keychain.
///
/// Why not Keychain: the macOS Keychain ACL is bound to the binary's code
/// signature, so every signed release rebuilds the ACL and the user is
/// re-prompted for "Always Allow" — multiple times per launch (Supabase
/// reads the session, refreshes the token, then writes it back). On a
/// shipping app that releases regularly, the prompts pile up and the
/// auth flow feels broken. DeviceFingerprint moved to UserDefaults for
/// the same reason; this is the same trade-off applied to the auth
/// session.
///
/// Threat model: the app is sandboxed (`com.apple.security.app-sandbox`),
/// so the storage directory lives inside the per-app Container at
/// `~/Library/Containers/com.thierry.Avatar/Data/Library/Application
/// Support/Avatar/auth/`. Other apps cannot read that directory without
/// TCC permission. Files are written with mode `0600` (owner read/write
/// only). Practical security is comparable to Keychain for the threats
/// that matter here ("other apps trying to steal my session"); we lose
/// the theoretical benefit of Keychain's encrypted storage at rest, but
/// macOS Keychain on a logged-in account is effectively decrypted in
/// memory anyway.
struct FileAuthStorage: AuthLocalStorage {
    private let directory: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        directory = base
            .appendingPathComponent("Aaavatar", isDirectory: true)
            .appendingPathComponent("auth", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func store(key: String, value: Data) throws {
        let url = fileURL(for: key)
        try value.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    func retrieve(key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func remove(key: String) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// True iff at least one auth blob is on disk. Used by `MainWindow` to
    /// detect "user upgraded from a Keychain build and has nothing in the
    /// new file storage" so we can re-show the sign-in sheet instead of
    /// silently rendering a signed-out state.
    func hasAnySession() -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return !contents.isEmpty
    }

    private func fileURL(for key: String) -> URL {
        // Whitelist filename characters so a key like `supabase.auth.token`
        // round-trips cleanly. Anything outside is hex-escaped to keep the
        // mapping unambiguous; in practice Supabase only uses dot-separated
        // ASCII keys.
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))
        let escaped = key.unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            return String(format: "_%02X", scalar.value)
        }.joined()
        return directory.appendingPathComponent("\(escaped).bin")
    }
}
