import CryptoKit
import Foundation
import Security

/// Envelope encryption for the on-disk Supabase auth blobs van Aaavatar 2.0.
/// Zelfde ontwerp als `AuthEncryption` in de v1-app (audit HIGH #7): één
/// AES-GCM-256-sleutel in de Keychain (vaste vorm, geen custom ACL → geen
/// "Always Allow"-prompts), het versleutelde sessiebestand op disk in de
/// app-container. Bij een signing-wijziging wordt de oude sleutel
/// onbereikbaar, faalt decrypt, en vraagt de app één keer opnieuw inloggen.
///
/// Eigen Keychain-service (≠ v1) zodat beide apps naast elkaar draaien
/// zonder dat de één het item van de ander probeert te updaten — generic-
/// password-items delen hun primary key (class+service+account) per
/// login-keychain, maar de ACL is per binary.
enum AuthSessionEncryption {
    private static let service = "nl.squareone.aaavatar2.AuthStorage"
    private static let account = "encryption-key.v1"

    /// Magic byte prefix on every encrypted file — onderscheidt een
    /// versleuteld blob van een plaintext JSON-sessie.
    static let magic: UInt8 = 0x01

    enum Failure: Error {
        case keychainStore(OSStatus)
        case keychainRead(OSStatus)
        case malformedCiphertext
    }

    /// Test seam: wanneer gezet wordt de Keychain niet aangeraakt. Alleen
    /// voor unit-tests — de testrunner is ongesigneerd en mag het login-
    /// keychain niet vervuilen.
    nonisolated(unsafe) static var keyOverrideForTesting: SymmetricKey?

    /// Encrypts `plaintext` under the app's symmetric key. Output format:
    /// `0x01 || AES.GCM.combined` (nonce ‖ ciphertext ‖ tag).
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try loadOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw Failure.malformedCiphertext }
        var out = Data(capacity: 1 + combined.count)
        out.append(magic)
        out.append(combined)
        return out
    }

    /// Decrypts a blob produced by `encrypt`. Throws on malformed input.
    static func decrypt(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count > 1, ciphertext.first == magic else {
            throw Failure.malformedCiphertext
        }
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext.dropFirst())
        return try AES.GCM.open(box, using: key)
    }

    // MARK: Keychain key management

    private static func loadOrCreateKey() throws -> SymmetricKey {
        if let override = keyOverrideForTesting { return override }
        if let existing = try readKey() { return existing }
        let key = SymmetricKey(size: .bits256)
        try writeKey(key)
        return key
    }

    private static func readKey() throws -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure.keychainRead(status)
        }
    }

    private static func writeKey(_ key: SymmetricKey) throws {
        let raw = key.withUnsafeBytes { Data($0) }
        // Update-first zodat we de access policy niet churnen bij rewrites.
        let updateQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData: raw] as CFDictionary)
        if updateStatus == errSecSuccess { return }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: raw,
            // After first unlock; ThisDeviceOnly schakelt iCloud-sync uit.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Failure.keychainStore(addStatus)
        }
    }
}
