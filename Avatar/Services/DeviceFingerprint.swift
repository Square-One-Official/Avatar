import Foundation

/// Stable per-Mac identifier for the free-tier anti-cheat layer. Generated
/// once on first access and parked in `UserDefaults` (the standard `.plist`
/// in `~/Library/Containers/.../Preferences` for sandboxed builds, or
/// `~/Library/Preferences/nl.avatar.app.plist` outside the sandbox).
///
/// Survives a full app uninstall + reinstall on the same Mac (the prefs file
/// lives outside the app bundle), but does not leak to the backend before
/// the user signs in — the value is only read when `BackendClient` builds a
/// request, and is sent in the `X-Device-Fingerprint` header gating the
/// per-device counter on `/v1/import-claim`.
///
/// We deliberately do NOT touch hardware identifiers (`IOPlatformExpertDevice`
/// UUID, MAC address, serial number) so the app remains friendly to
/// org-managed Macs where IT pushes back on system-level snooping. We also
/// don't use the Keychain: the ACL on a Keychain item is bound to the binary
/// signature, which means every certificate change (Apple Development →
/// Developer ID, dev → MAS) triggers a "type your login password" prompt
/// for an orphaned item from a previous install. The threat model here is
/// "create a fresh Google account on the same Mac to reset the trial",
/// which a plain UserDefaults UUID defeats just as effectively.
enum DeviceFingerprint {
    private static let key = "nl.aaavatar.Avatar.DeviceFingerprint.id"

    /// Returns the stored UUID, generating one on first access. Idempotent.
    static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        defaults.set(new, forKey: key)
        return new
    }
}
