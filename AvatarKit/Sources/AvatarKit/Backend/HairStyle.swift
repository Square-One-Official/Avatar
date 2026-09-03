import Foundation

/// Kapsel-presets voor het Hair-paneel (E11.2). De `rawValue` is exact de
/// server-side key uit `/v1/stylize` (HAIR_PRESETS) — de prompt + de
/// "verander alleen het haar"-clausule leven op de server (E09.1-bakeoff).
/// Copy uit het figma-design-review-voorstel.
public enum HairStyle: String, CaseIterable, Sendable, Identifiable {
    case trimFlyaways = "trim-flyaways"
    case curly
    case straight
    case short
    case updo

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .trimFlyaways: "Trim flyaways"
        case .curly: "Curly"
        case .straight: "Straight"
        case .short: "Short"
        case .updo: "Updo"
        }
    }
}
