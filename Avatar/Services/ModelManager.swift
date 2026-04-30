import Foundation

/// User preference for the Pro Magic Cutout feature. The cutout itself runs
/// server-side via Replicate (`851-labs/background-remover`); this class only
/// persists whether the toggle is on. The processing path is gated by both
/// `ProEntitlement.canUseProCutout` and `enabled` — see
/// `ImportFlow.shouldUseMagicCutout`.
@MainActor
@Observable
final class MagicCutoutPreferences {

    private static let prefKey = "magicCutoutEnabled"

    /// Default-on so new users see Pro cutout quality on their very first
    /// import (server enforces the free-trial cap). Existing users who
    /// already toggled it off keep their choice — `register(defaults:)`
    /// only fills in the value when the key is missing.
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.prefKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.prefKey) }
    }

    init() {
        UserDefaults.standard.register(defaults: [Self.prefKey: true])
        Self.removeLegacyLocalModel()
    }

    private static func removeLegacyLocalModel() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first
        guard let modelsDir = appSupport?
            .appendingPathComponent("Avatar")
            .appendingPathComponent("Models") else { return }
        let mlmodelc = modelsDir.appendingPathComponent("BiRefNet.mlmodelc")
        if FileManager.default.fileExists(atPath: mlmodelc.path) {
            try? FileManager.default.removeItem(at: mlmodelc)
        }
        let sidecar = modelsDir.appendingPathComponent(".model_version")
        if FileManager.default.fileExists(atPath: sidecar.path) {
            try? FileManager.default.removeItem(at: sidecar)
        }
    }
}
