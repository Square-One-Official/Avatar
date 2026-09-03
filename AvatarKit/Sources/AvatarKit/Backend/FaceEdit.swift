import Foundation

/// Face beauty-presets voor het Face-paneel (E32.1). De `rawValue` is exact de
/// server-side key uit `/v1/stylize` (FACE_PRESETS) — de prompt + de "verander
/// alleen het gevraagde gezichtsdetail"-clausule leven op de server. Net als
/// HairStyle/RemoteEffect: geen vrij promptveld, productie blijft binnen deze
/// whitelist.
public enum FaceEdit: String, CaseIterable, Sendable, Identifiable {
    case whitenTeeth = "whiten-teeth"
    case applyMakeup = "apply-makeup"
    case reduceWrinkles = "reduce-wrinkles"

    public var id: String { rawValue }

    /// Gebruikersgerichte naam op de face-kaart (matcht FaceActionsPanel).
    public var label: String {
        switch self {
        case .whitenTeeth: "Whiten teeth"
        case .applyMakeup: "Apply make-up"
        case .reduceWrinkles: "Reduce wrinkles"
        }
    }
}
