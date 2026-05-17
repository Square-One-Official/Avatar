import CryptoKit
import Foundation
import Security

/// Envelope encryption for the on-disk Supabase auth blobs (audit HIGH #7).
/// Keeps the storage shape that `FileAuthStorage` already uses — one file
/// per key under the sandbox container — but wraps each blob in
/// AES-GCM-256. The symmetric key lives in the Keychain, scoped to this
/// app's code signature; the auth payload itself stays on disk.
///
/// Threat model the encryption closes:
///   - Local privilege escalation / disk theft / Time Machine restore
///     where the Container files are reachable but the Keychain remains
///     bound to this Mac + user. Without the key, the file is opaque.
///   - Tooling that reads files from the Container with sandbox
///     entitlements but cannot read other apps' Keychain items.
///
/// Why not store the whole blob in the Keychain? The original
/// `FileAuthStorage` switched off the Keychain because the macOS Keychain
/// ACL is bound to the binary signature and re-prompts the user on every
/// signing change (each release, each cert rotation, dev ↔ Mac App Store).
/// Storing just a 32-byte key under
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` with no custom
/// `kSecAccess` avoids the "Always Allow" prompt entirely — the owning
/// app reads its own item without UI. When the signing identity *does*
/// change, the old key becomes invisible to the new build, the encrypted
/// file fails to decrypt, and `FileAuthStorage` treats the session as
/// missing — which forces a fresh sign-in. That matches the audit's
/// "refresh aggressively so the steal window stays short" guidance.
enum AuthEncryption {
    /// Keychain `kSecAttrService` — distinct from anything Supabase writes
    /// directly so a future Supabase Swift release can't collide.
    private static let service = "nl.aaavatar.Avatar.AuthStorage"
    /// Single fixed account because we only ever store one key.
    private static let account = "encryption-key.v1"

    /// Magic byte prefix on every encrypted file. Lets `decrypt` tell an
    /// encrypted v1 blob apart from a legacy plaintext Supabase session
    /// JSON document so we can migrate in place without losing the
    /// existing sign-in.
    static let magic: UInt8 = 0x01

    enum Failure: Error {
        case keychainStore(OSStatus)
        case keychainRead(OSStatus)
        case malformedCiphertext
    }

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

    /// Decrypts a v1 blob produced by `encrypt`. Throws on malformed input
    /// (caller is expected to fall back to the plaintext-migration path).
    static func decrypt(_ ciphertext: Data) throws -> Data {
        guard ciphertext.count > 1, ciphertext.first == magic else {
            throw Failure.malformedCiphertext
        }
        let key = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext.dropFirst())
        return try AES.GCM.open(box, using: key)
    }

    /// True when the bytes look like a Supabase JSON session blob (starts
    /// with `{` after optional UTF-8 BOM). Used by the migration path in
    /// `FileAuthStorage` so a one-time upgrade encrypts the existing
    /// session in place instead of dumping the user back to sign-in.
    static func looksLikePlaintextSession(_ data: Data) -> Bool {
        var bytes = data
        // Strip an optional UTF-8 BOM.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        guard let first = bytes.first else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    // MARK: Keychain key management

    private static func loadOrCreateKey() throws -> SymmetricKey {
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
        // Try update-first so we don't churn the access policy on rewrites
        // (which can prompt the user on some macOS versions).
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
            // After first unlock so the app can read it on relaunch
            // without the user having to be at the keyboard the moment
            // we initialise. ThisDeviceOnly disables iCloud sync — the
            // key is meaningless on another Mac anyway.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Failure.keychainStore(addStatus)
        }
    }
}
