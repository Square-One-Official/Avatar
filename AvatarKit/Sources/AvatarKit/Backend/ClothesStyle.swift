import Foundation

/// Outfit-presets voor het Clothes-paneel (E10.4). De `rawValue` is exact de
/// server-side key uit `/v1/stylize` (CLOTHES_PRESETS) — de prompt + de
/// "verander alleen de kleding"-clausule (het harde acceptatiecriterium)
/// leven op de server. Labels = de chips uit E10.2.
public enum ClothesStyle: String, CaseIterable, Sendable, Identifiable {
    case tshirt
    case polo
    case blazer
    case hoody
    case sweater

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tshirt: "T-Shirt"
        case .polo: "Polo"
        case .blazer: "Blazer"
        case .hoody: "Hoody"
        case .sweater: "Sweater"
        }
    }
}
