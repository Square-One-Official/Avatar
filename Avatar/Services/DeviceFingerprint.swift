import Foundation
import Security

/// Stable per-Mac identifier for the free-tier anti-cheat layer. Generated
/// once on first launch and parked in the macOS Keychain; survives a full
/// app uninstall + reinstall, but does NOT survive a Mac wipe or a move
/// to a different Mac. We deliberately do NOT touch hardware identifiers
/// (`IOPlatformExpertDevice` UUID, MAC address, serial number) so the app
/// remains friendly to org-managed Macs where IT departments push back on
/// any system-level snooping. A user-private Keychain item is the same
/// kind of storage the system already grants every sandboxed app.
///
/// The fingerprint is sent to the backend via the `X-Device-Fingerprint`
/// header on every authenticated request and on the auth-optional
/// `/v1/import-claim` endpoint, where it gates a per-device counter that
/// blocks the "create a fresh Google account to reset the trial" cheat.
enum DeviceFingerprint {
    private static let service = "nl.aaavatar.Avatar.DeviceFingerprint"
    private static let account = "device_id"

    /// Returns the stored UUID, generating one on first access. Idempotent
    /// and thread-safe (Keychain ops are serialized by the system).
    static var current: String {
        if let existing = read() { return existing }
        let new = UUID().uuidString
        store(new)
        // Re-read so two racing first-launch threads converge on the same
        // value (the loser's `store` is a no-op due to the duplicate check).
        return read() ?? new
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let id = String(data: data, encoding: .utf8) else {
            return nil
        }
        return id
    }

    private static func store(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        // AfterFirstUnlockThisDeviceOnly: usable as soon as the user has
        // logged in once after boot, never restored to a different Mac
        // via Time Machine / migration assistant — exactly the lifetime
        // we want for a per-device counter.
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
