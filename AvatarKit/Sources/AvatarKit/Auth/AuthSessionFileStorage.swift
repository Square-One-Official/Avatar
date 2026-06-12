import Auth
import Foundation

/// `AuthLocalStorage` voor Aaavatar 2.0 — zelfde ontwerp als v1's
/// `FileAuthStorage`: één bestand per key in de app-container, AES-GCM-
/// versleuteld via `AuthSessionEncryption`, bestanden `0600`, map `0700`.
/// Eigen submap ("Aaavatar2") zodat een toekomstige unsandboxed build of
/// gedeelde container nooit met v1-blobs botst.
public struct AuthSessionFileStorage: AuthLocalStorage {
    private let directory: URL

    public init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        self.init(directory: base
            .appendingPathComponent("Aaavatar2", isDirectory: true)
            .appendingPathComponent("auth", isDirectory: true))
    }

    /// Expliciete map — gebruikt door tests om in een tempdir te draaien.
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    public func store(key: String, value: Data) throws {
        let url = fileURL(for: key)
        let payload = try AuthSessionEncryption.encrypt(value)
        try payload.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public func retrieve(key: String) throws -> Data? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let onDisk = try Data(contentsOf: url)

        if let first = onDisk.first, first == AuthSessionEncryption.magic {
            do {
                return try AuthSessionEncryption.decrypt(onDisk)
            } catch {
                // Stale sleutel (signing-wijziging, Keychain-reset): geen
                // sessie melden zodat de app opnieuw om inloggen vraagt.
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }

        // Plaintext blob (zou in 2.0 niet moeten voorkomen, maar dezelfde
        // migratie als v1 is goedkoop): her-versleutel in place.
        if AuthSessionEncryption.looksLikePlaintextSession(onDisk) {
            try? store(key: key, value: onDisk)
            return onDisk
        }
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    public func remove(key: String) throws {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for key: String) -> URL {
        // Whitelist zodat een key als `supabase.auth.token` schoon
        // round-tript; al het andere hex-escaped.
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
