import Foundation

/// De vier Effects-stijlen (E09.2). De `rawValue` is exact de server-side
/// key uit `/v1/stylize` (STYLE_PROMPTS) — de prompt + identity-clausule
/// leven op de server (E09.1-bakeoff), de client kiest alleen de key. Geen
/// vrij prompt-veld: productie-gebruikers blijven binnen deze whitelist.
public enum StylizeStyle: String, CaseIterable, Sendable, Identifiable {
    case clay
    case wood
    case threeD = "3d"
    case scribble

    public var id: String { rawValue }

    /// Gebruikersgerichte naam op de stijl-kaart.
    public var label: String {
        switch self {
        case .clay: "Clay"
        case .wood: "Wood"
        case .threeD: "3D"
        case .scribble: "Scribble"
        }
    }
}
