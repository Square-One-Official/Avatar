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
/// commit history). `downloadedModel` is the optional ~90 MB BiRefNet_lite-
/// matting CoreML model the user can opt into for crisper hair (download
/// triggered first time the user imports under that engine — wired in a
/// later session).
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

    static let modeKey   = "aiPrivacyMode"
    static let engineKey = "localCutoutEngine"

    /// Default for new users coming through onboarding is whatever they
    /// pick. Default for migrated existing users is `cloudAllowed`,
    /// preserving today's behaviour. Default for anyone reaching this
    /// without onboarding (e.g., a unit test) is also `cloudAllowed`
    /// so we never silently block a feature without explicit user
    /// consent to the privacy posture.
    var mode: AIPrivacyMode = .cloudAllowed {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
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
    }
}
