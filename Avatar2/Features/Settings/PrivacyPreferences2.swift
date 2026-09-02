// Privacy/engine-voorkeuren 2.0 — dezelfde UserDefaults-keys en rawValues
// als v1 (aiPrivacyMode, localCutoutEngine, shareAnonymousDiagnostics) in
// het eigen defaults-domein van Avatar2, conform de E04.3-notities.
//
// UI is Local only / Cloud. Intern blijft `appleCloud` leesbaar en migreert
// naar `thirdParty`. Legacy `mode` blijft als computed bridge naar v1-keys.

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
    static let tierKey = "aiPrivacyTier"
    static let engineKey = "localCutoutEngine"
    static let shareDiagnosticsKey = "shareAnonymousDiagnostics"

    /// Opgeslagen voorkeur (UI-selectie). Apple Private Cloud migreert naar Cloud.
    var tier: AIPrivacyTier = .onDevice {
        didSet {
            if tier == .appleCloud {
                tier = .thirdParty
                return
            }
            persistTier(tier)
            applyFingerprintPolicy(for: effectiveTier)
        }
    }

    /// Tier die gates en features daadwerkelijk gebruiken.
    var effectiveTier: AIPrivacyTier { tier.userFacing }

    /// Legacy bridge — leest/schrijft via `tier`.
    var mode: AIPrivacyMode2 {
        get { effectiveTier.legacyMode }
        set { tier = newValue == .localOnly ? .onDevice : .thirdParty }
    }

    var allowsAppleCloud: Bool { effectiveTier >= .appleCloud }
    var allowsThirdPartyCloud: Bool { effectiveTier >= .thirdParty }

    /// Her-evalueer fingerprint na macOS/AI-statuswijziging (app-focus).
    func reapplyFingerprintPolicy() {
        applyFingerprintPolicy(for: effectiveTier)
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
        if let raw = defaults.string(forKey: Self.tierKey),
           let stored = AIPrivacyTier(storageKey: raw) {
            tier = stored.userFacing
        } else if let raw = defaults.string(forKey: Self.modeKey),
                  let legacy = AIPrivacyMode2(rawValue: raw) {
            tier = legacy == .localOnly ? .onDevice : .thirdParty
        }
        if let raw = defaults.string(forKey: Self.engineKey),
           let stored = LocalCutoutEngine2(rawValue: raw) {
            engine = stored
        }
        if defaults.object(forKey: Self.shareDiagnosticsKey) != nil {
            shareAnonymousDiagnostics = defaults.bool(forKey: Self.shareDiagnosticsKey)
        }
        applyFingerprintPolicy(for: effectiveTier)
    }

    private func persistTier(_ tier: AIPrivacyTier) {
        UserDefaults.standard.set(tier.storageKey, forKey: Self.tierKey)
        UserDefaults.standard.set(tier.legacyMode.rawValue, forKey: Self.modeKey)
    }

    private func applyFingerprintPolicy(for tier: AIPrivacyTier) {
        switch tier {
        case .onDevice:
            DeviceFingerprint.useEphemeralForThisLaunch()
        case .appleCloud, .thirdParty:
            DeviceFingerprint.dropEphemeral()
        }
    }
}
