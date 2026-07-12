import Foundation

/// Credit-metering per feature (E14.3) — de client-zijde contract dat élke
/// cloud-actie z'n kosten in credits laat tonen (ProChip-label) vóór
/// uitvoering, en aangeeft of een actie cloud vereist (E03.7 cloud/AI-glyph).
///
/// Bron van waarheid voor de DISPLAY; de werkelijke aftrek gebeurt
/// server-side (MODEL_REGISTRY.credits per CloudFeature) op de echte call.
/// De tarieven hier spiegelen de besluit-tabel (Thierry 2026-06-12,
/// netto-correctie): kosten-proportioneel, AI-kostenbescherming.
///
/// | Actie                    | Credits |
/// |--------------------------|---------|
/// | Magic Cutout             | 1       |
/// | Colorize                 | 1       |
/// | Fill body                | 2       |
/// | Generatief standaard     | 4       |
/// | Generatief premium       | 7       |
///
/// On-device-acties zitten NIET in deze tabel — die tonen geen credits.
public enum CreditMeter {

    /// Elke betaalde cloud-actie. (On-device acties hebben geen case: geen
    /// kosten, geen chip.)
    public enum Action: String, Sendable, CaseIterable {
        case magicCutout
        case colorize
        /// Upscale Regular (E41.5, besluit Thierry 2026-07-12): google/upscaler,
        /// 1 credit — vaste modelprijs $0,02/beeld ≈ de credit-opbrengst.
        case upscale
        /// Upscale High quality (E41.5): Topaz High Fidelity V2, 3 credits —
        /// dekt Topaz' $0,05-unit (server capt de input op 6 MP).
        case upscaleHigh
        case fillBody
        /// Generatieve stijl/kleding/haar — standaardmodel (nano-banana c.s.).
        case generativeStandard
        /// Generatieve premium (alleen als de E09.1-bakeoff het rechtvaardigt).
        case generativePremium
    }

    /// Kosten in credits voor een actie (besluit-tabel).
    public static func credits(for action: Action) -> Int {
        switch action {
        case .magicCutout, .colorize, .upscale: return 1
        case .fillBody: return 2
        case .upscaleHigh: return 3
        case .generativeStandard: return 4
        case .generativePremium: return 7
        }
    }

    /// Label voor de ProChip, bv. "1 credit" / "4 credits".
    public static func chipLabel(for action: Action) -> String {
        let n = credits(for: action)
        return n == 1 ? "1 credit" : "\(n) credits"
    }

    /// Heeft de gebruiker genoeg saldo voor de actie?
    public static func canAfford(_ action: Action, creditsRemaining: Int) -> Bool {
        creditsRemaining >= credits(for: action)
    }
}
