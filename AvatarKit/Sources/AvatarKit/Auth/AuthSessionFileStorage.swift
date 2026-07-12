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
        // E13.6: GEEN `.completeFileProtection` — met vergrendeld scherm
        // (keybag dicht) faalt élke protected-class file-creatie met EPERM,
        // waardoor een token-refresh terwijl de Mac op slot staat zijn sessie
        // niet kon persisteren (mogelijke wortel van de sessie-herstel-
        // klachten rond 921b1e7). Confidentialiteit komt al van de AES-GCM-
        // envelop (`AuthSessionEncryption`, sleutel in de Keychain) + 0600/0700-
        // permissies — de protection-class voegde hier niets aan toe.
        try payload.write(to: url, options: [.atomic])
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

        // 2.0 schrijft sessies altijd versleuteld in een eigen "Aaavatar2"-
        // submap, dus een niet-`magic` bestand hoort hier niet thuis — geen
        // plaintext-migratie meer. Anders zou een aanvaller met container-
        // schrijftoegang een sessie-JSON kunnen planten. Behandel als ongeldig:
        // opruimen en geen sessie melden.
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
