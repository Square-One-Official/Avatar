import Foundation
import Auth

/// `AuthLocalStorage` implementation backed by a sandboxed file, with
/// AES-GCM envelope encryption for the JWT / refresh-token blobs at rest
/// (audit HIGH #7). The encryption key lives in the macOS Keychain; the
/// auth payload itself stays on disk under the per-app Container.
///
/// History: this storage initially landed *unencrypted* because the macOS
/// Keychain ACL is bound to the binary's code signature, so every signed
/// release rebuilt the ACL and the user was re-prompted for "Always Allow"
/// — multiple times per launch (Supabase reads the session, refreshes the
/// token, then writes it back). The new design keeps a fixed-shape
/// Keychain item (a 32-byte symmetric key, no custom ACL) which the
/// owning app reads without UI; on the rare signing-identity change the
/// old key becomes unreachable, the encrypted file fails to decrypt, and
/// the user is asked to sign in once — same UX as a fresh install.
///
/// Threat model the encryption now closes (vs. the old plaintext shape):
///   - Local privilege escalation / disk theft / Time Machine restore
///     where the Container files are reachable but the Keychain remains
///     bound to this Mac + user. Without the key, the file is opaque.
///
/// Threat model the encryption deliberately does *not* close:
///   - A live, unlocked user session with the Avatar app running — at
///     that point CryptoKit holds the unwrapped key in memory.
///
/// Sandbox + filesystem hardening from the original design carries over:
/// the storage directory lives at
/// `~/Library/Containers/com.thierry.Avatar/Data/Library/Application
/// Support/Avatar/auth/`, files are written with mode `0600`, and the
/// directory is `0700`.
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
        let payload = try AuthEncryption.encrypt(value)
        try payload.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    func retrieve(key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let onDisk = try Data(contentsOf: url)

        // Fast path — encrypted v1 blob.
        if let first = onDisk.first, first == AuthEncryption.magic {
            do {
                return try AuthEncryption.decrypt(onDisk)
            } catch {
                // Stale key (signing-identity change, Keychain reset, etc.):
                // surface "no session" so the caller asks the user to sign
                // in again. Removing the file keeps subsequent reads cheap.
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }

        // Legacy plaintext payload from before the encryption rollover. If
        // it parses as a Supabase session blob, re-encrypt in place so the
        // user keeps their session; otherwise treat as missing.
        if AuthEncryption.looksLikePlaintextSession(onDisk) {
            try? store(key: key, value: onDisk)
            return onDisk
        }
        try? FileManager.default.removeItem(at: url)
        return nil
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
