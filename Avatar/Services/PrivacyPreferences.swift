import Foundation

/// User-facing AI privacy posture. Set during first-launch onboarding,
/// changeable any time from Settings → General → Privacy & AI.
///
/// `localOnly` is the strict promise: photo bytes never leave the Mac.
/// All cloud-backed features (Magic Cutout, Fill in Body, Colorize) are
/// hard-disabled — the corresponding buttons hide, network calls are
/// short-circuited before a signed PUT URL is ever requested.
///
/// `cloudAllowed` is today's behaviour: cloud AI features are available
/// (still gated on entitlement / per-feature toggle), photo bytes go via
/// signed Supabase Storage uploads to the Avatar backend for processing.
enum AIPrivacyMode: String, CaseIterable, Codable, Sendable {
    case localOnly
    case cloudAllowed
}

/// Which engine the local-only path uses for background removal.
/// `appleVision` is the always-available Subject Lift pipeline (free,
/// instant, decent — visible hair-edge limits documented in the V2
/// commit history). `downloadedModel` is the optional ~78 MB matting
/// CoreML model the user can opt into for crisper hair edges
/// (currently ORMBG — Apache 2.0, DIS-family, portrait-trained; see
/// `ModelManager` and the conversion script for the pivot history).
/// Download is user-driven from Settings → Privacy & AI, not auto-
/// triggered on import.
enum LocalCutoutEngine: String, CaseIterable, Codable, Sendable {
    case appleVision
    case downloadedModel
}

/// Persisted user preferences for the local-first pivot. UserDefaults-
/// backed via `didSet` rather than computed properties — `@Observable`'s
/// macro instruments stored properties for change tracking but does NOT
/// see through computed-over-UserDefaults accessors, which is why
/// `MagicCutoutPreferences` had to fall back to `@AppStorage` in
/// SettingsView. Stored-with-didSet keeps a single source of truth, lets
/// SwiftUI re-render on every mutation, and still persists across launches.
///
/// Memory state and disk state can drift only if a foreign process edits
/// the plist while the app is running — fine for our case (debug menu
/// "Reset Onboarding" deletes keys then prompts for a quit-and-relaunch).
@MainActor
@Observable
final class PrivacyPreferences {

    static let modeKey               = "aiPrivacyMode"
    static let engineKey             = "localCutoutEngine"
    static let shareDiagnosticsKey   = "shareAnonymousDiagnostics"

    /// Default for new users coming through onboarding is whatever they
    /// pick. Default for migrated existing users is `cloudAllowed`,
    /// preserving today's behaviour. Default for anyone reaching this
    /// without onboarding (e.g., a unit test) is also `cloudAllowed`
    /// so we never silently block a feature without explicit user
    /// consent to the privacy posture.
    var mode: AIPrivacyMode = .cloudAllowed {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            // Audit MEDIUM #26: localOnly users get an ephemeral device
            // fingerprint regenerated on every launch, so this Mac isn't
            // tracked across sessions by the backend's anti-cheat counter.
            // Flipping back to cloudAllowed restores the persisted UUID
            // so existing subscription / device_grants rows still match.
            applyFingerprintPolicy(for: mode)
        }
    }

    /// Centralised translation of `mode` → device-fingerprint strategy.
    /// Called from `didSet` and from `init` so a fresh launch in
    /// `localOnly` immediately goes ephemeral instead of waiting for the
    /// next mutation.
    private func applyFingerprintPolicy(for mode: AIPrivacyMode) {
        switch mode {
        case .localOnly:
            DeviceFingerprint.useEphemeralForThisLaunch()
        case .cloudAllowed:
            DeviceFingerprint.dropEphemeral()
        }
    }

    /// Local engine selection. Only consulted when `mode == .localOnly`.
    /// Default Apple Vision so the cutout pipeline always has something
    /// to fall back to even if the user picked "downloaded model" but
    /// never completed the download (e.g., quit during first-use download).
    var engine: LocalCutoutEngine = .appleVision {
        didSet {
            UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey)
        }
    }

    /// User-facing consent for anonymous diagnostics (audit MEDIUM #27).
    /// Today the app sends NO product analytics — but Sparkle's update
    /// channel can optionally include `SUEnableSystemProfiling` (macOS
    /// version, hardware model, locale; default off) and Supabase Auth
    /// internally records sign-in events. This flag is the contract we
    /// honour: while it is `false`, the app must not enable any
    /// optional telemetry and must prefer the most privacy-preserving
    /// path through any vendor SDK. Default `true` mirrors what the app
    /// does today (no telemetry beyond what Supabase Auth always logs);
    /// the toggle is forward-looking so a future Sparkle profile flip
    /// doesn't ship without an opt-out.
    var shareAnonymousDiagnostics: Bool = true {
        didSet {
            UserDefaults.standard.set(shareAnonymousDiagnostics, forKey: Self.shareDiagnosticsKey)
        }
    }

    /// Convenience for call sites that just want a yes/no on cloud AI.
    var cloudAllowed: Bool { mode == .cloudAllowed }

    init() {
        // Read persisted values, if any. `string(forKey:)` returns nil
        // for unset keys (defaults registration is intentionally not
        // used here — we want the actual disk state, not a synthetic
        // fallback that would mask a missing key on first launch).
        // Setting the stored property triggers didSet which writes back
        // to UserDefaults — redundant on the first run, idempotent
        // afterwards. Hop through helpers so init stays linear.
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let m = AIPrivacyMode(rawValue: raw) {
            self.mode = m
        }
        if let raw = UserDefaults.standard.string(forKey: Self.engineKey),
           let e = LocalCutoutEngine(rawValue: raw) {
            self.engine = e
        }
        // `bool(forKey:)` returns false for unset keys — guard with
        // `object(forKey:)` so a missing key keeps the default (true)
        // instead of silently opting the user out.
        if UserDefaults.standard.object(forKey: Self.shareDiagnosticsKey) != nil {
            self.shareAnonymousDiagnostics = UserDefaults.standard.bool(forKey: Self.shareDiagnosticsKey)
        }
        // didSet on `mode` doesn't run during property initialisation, so
        // apply the fingerprint policy explicitly on first launch.
        applyFingerprintPolicy(for: mode)
    }
}
