import AppKit

/// Gebundelde scène-foto's achter de Portrait-tegel (E53.10). Besluit Thierry
/// 2026-09-02: 2–3 gebundelde Pexels-scènes, willekeurig per paneel — offline,
/// geen API, geen conflict met Local only.
///
/// PLACEHOLDERS: de huidige assets zijn procedurele bokeh-scènes (zie
/// plan/ASSETS.md #6); Thierry levert de definitieve foto's in de asset-batch.
enum EnhancePreviewScenes {
    static let names = [
        "EnhanceScenePlaceholder1",
        "EnhanceScenePlaceholder2",
        "EnhanceScenePlaceholder3"
    ]

    static func image(named name: String) -> NSImage? {
        NSImage(named: name)
    }

    static func random() -> NSImage? {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> NSImage? {
        guard let name = names.randomElement(using: &generator) else { return nil }
        return image(named: name)
    }
}
