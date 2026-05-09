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

/// Persisted user preferences for the local-first pivot. Mirrors the
/// pattern in `MagicCutoutPreferences` — UserDefaults-backed, defaults
/// registered at init time so the onboarding sheet sees a sane initial
/// state. `@Observable` lets SwiftUI views bind to changes.
@MainActor
@Observable
final class PrivacyPreferences {

    static let modeKey   = "aiPrivacyMode"
    static let engineKey = "localCutoutEngine"

    /// Default for new users coming through onboarding is whatever they
    /// pick. Default for migrated existing users is `cloudAllowed`,
    /// preserving today's behaviour. Default for *anyone* who somehow
    /// reaches this without onboarding (e.g., a unit test) is also
    /// `cloudAllowed` so we never silently block a feature without
    /// explicit user consent to the privacy posture.
    var mode: AIPrivacyMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.modeKey),
                  let m = AIPrivacyMode(rawValue: raw)
            else { return .cloudAllowed }
            return m
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    /// Local engine selection. Only consulted when `mode == .localOnly`.
    /// Default Apple Vision so the cutout pipeline always has something
    /// to fall back to even if the user picked "downloaded model" but
    /// never completed the download (e.g., quit during first-use download).
    var engine: LocalCutoutEngine {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.engineKey),
                  let e = LocalCutoutEngine(rawValue: raw)
            else { return .appleVision }
            return e
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.engineKey) }
    }

    /// Convenience for call sites that just want a yes/no on cloud AI.
    /// Reads through `mode` so observers fire correctly.
    var cloudAllowed: Bool { mode == .cloudAllowed }

    init() {
        // Register defaults once at construction. `register` doesn't
        // overwrite values already set, so existing users who picked
        // a mode through onboarding keep their choice.
        UserDefaults.standard.register(defaults: [
            Self.modeKey: AIPrivacyMode.cloudAllowed.rawValue,
            Self.engineKey: LocalCutoutEngine.appleVision.rawValue,
        ])
    }
}
