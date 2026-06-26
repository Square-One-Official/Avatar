// E37.9 — Curated banner-fonts (~10 faces die op banner-schaal werken).

import Foundation

enum BannerFontCatalog {
    struct Entry: Identifiable, Sendable {
        let id: String
        let label: String
        /// `nil` = systeemfont (weight uit de laag).
        let fontName: String?
    }

    static let curated: [Entry] = [
        Entry(id: "system", label: "System", fontName: nil),
        Entry(id: "helvetica", label: "Helvetica Neue", fontName: "HelveticaNeue"),
        Entry(id: "avenir", label: "Avenir", fontName: "Avenir-Book"),
        Entry(id: "georgia", label: "Georgia", fontName: "Georgia"),
        Entry(id: "futura", label: "Futura", fontName: "Futura-Medium"),
        Entry(id: "gill", label: "Gill Sans", fontName: "GillSans"),
        Entry(id: "copperplate", label: "Copperplate", fontName: "Copperplate"),
        Entry(id: "didot", label: "Didot", fontName: "Didot"),
        Entry(id: "american", label: "American Typewriter", fontName: "AmericanTypewriter"),
        Entry(id: "impact", label: "Impact", fontName: "Impact"),
    ]

    static func label(for fontName: String?) -> String {
        if fontName == nil { return "System" }
        return curated.first { $0.fontName == fontName }?.label ?? fontName ?? "System"
    }
}
