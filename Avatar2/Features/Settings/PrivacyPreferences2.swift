// Privacy/engine-voorkeuren 2.0 — dezelfde UserDefaults-keys en rawValues
// als v1 (aiPrivacyMode, localCutoutEngine, shareAnonymousDiagnostics) in
// het eigen defaults-domein van Avatar2, conform de E04.3-notities. De
// onboarding-privacy-stap (E04.3, FEAT) schrijft straks via deze klasse —
// E15.2 (AI & Models) leest/schrijft hem nu al: "één download-state, twee
// vensters" geldt ook voor de voorkeuren.
//
// Zelfde patroon als v1: stored properties met didSet (geen computed-over-
// UserDefaults — @Observable ziet daar niet doorheen). Fingerprint-beleid
// 1-op-1: localOnly → ephemeral DeviceFingerprint per launch.

import AvatarKit
import Foundation
import Observation

enum AIPrivacyMode2: String, CaseIterable, Codable, Sendable {
    case localOnly
    case cloudAllowed
}

enum LocalCutoutEngine2: String, CaseIterable, Codable, Sendable {
    case appleVision
    case downloadedModel
}

@MainActor
@Observable
final class PrivacyPreferences2 {

    static let shared = PrivacyPreferences2()

    static let modeKey = "aiPrivacyMode"
    static let engineKey = "localCutoutEngine"
    static let shareDiagnosticsKey = "shareAnonymousDiagnostics"

    var mode: AIPrivacyMode2 = .cloudAllowed {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            applyFingerprintPolicy(for: mode)
        }
    }

    /// Alleen geraadpleegd voor het lokale cutout-pad; default Apple Vision
    /// zodat er altijd een werkende engine is, ook als de download nooit
    /// is afgerond.
    var engine: LocalCutoutEngine2 = .appleVision {
        didSet {
            UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey)
        }
    }

    var shareAnonymousDiagnostics: Bool = true {
        didSet {
            UserDefaults.standard.set(shareAnonymousDiagnostics, forKey: Self.shareDiagnosticsKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.modeKey),
           let stored = AIPrivacyMode2(rawValue: raw) {
            mode = stored
        }
        if let raw = defaults.string(forKey: Self.engineKey),
           let stored = LocalCutoutEngine2(rawValue: raw) {
            engine = stored
        }
        if defaults.object(forKey: Self.shareDiagnosticsKey) != nil {
            shareAnonymousDiagnostics = defaults.bool(forKey: Self.shareDiagnosticsKey)
        }
        applyFingerprintPolicy(for: mode)
    }

    private func applyFingerprintPolicy(for mode: AIPrivacyMode2) {
        switch mode {
        case .localOnly:
            DeviceFingerprint.useEphemeralForThisLaunch()
        case .cloudAllowed:
            DeviceFingerprint.dropEphemeral()
        }
    }
}
