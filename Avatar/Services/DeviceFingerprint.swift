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

    /// Process-local ephemeral fingerprint. Generated lazily on first
    /// access via `useEphemeralForThisLaunch`, regenerated on next launch
    /// (it's in-memory only). Audit MEDIUM #26.
    nonisolated(unsafe) private static var ephemeral: String?

    /// Returns the stored UUID, generating one on first access. Idempotent.
    ///
    /// When `useEphemeralForThisLaunch` has been called (currently from
    /// `PrivacyPreferences` whenever `mode == .localOnly`), this returns
    /// a fresh UUID generated once per process and held only in memory.
    /// Trade-off: per-device free-trial counters reset on every launch in
    /// that mode, which is acceptable because localOnly users opt out of
    /// the cloud features the counter primarily protects.
    static var current: String {
        if let eph = ephemeral { return eph }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        defaults.set(new, forKey: key)
        return new
    }

    /// Switch this process into ephemeral mode — `current` returns a
    /// fresh UUID generated lazily on next access, held only in memory.
    /// The persisted UserDefaults UUID is intentionally left alone so
    /// flipping the privacy mode back to `cloudAllowed` (mid-launch or
    /// next launch) returns the stable identity.
    static func useEphemeralForThisLaunch() {
        guard ephemeral == nil else { return }
        ephemeral = UUID().uuidString
    }

    /// Drop ephemeral mode for the rest of the process — `current` goes
    /// back to reading the UserDefaults UUID. Called when the user
    /// switches OUT of localOnly so a cloud sign-in attempt in the same
    /// session picks up the stable identity the backend already knows.
    static func dropEphemeral() {
        ephemeral = nil
    }
}
