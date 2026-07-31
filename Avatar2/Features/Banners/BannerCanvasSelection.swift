// E37.8 + E37.16 — Canvas-selectie in Banner Studio. Een set verplaatsbare
// elementen (tekst-id's + het logo). De achtergrond-fill is GEEN element maar een
// aparte, exclusieve toestand (heel canvas, eigen reframe-chrome) en zit dus niet
// in deze set en niet in marquee/multi-selectie.

import Foundation

/// Een selecteerbaar/verplaatsbaar element op het banner-canvas.
enum BannerElementRef: Hashable, Sendable {
    case text(UUID)
    case logo
}

extension BannerElementRef {
    /// De tekst-id als dit een tekst-element is, anders `nil`.
    var textID: UUID? {
        if case let .text(id) = self { return id }
        return nil
    }

    var isLogo: Bool { self == .logo }
}

extension Set where Element == BannerElementRef {
    /// Het enige geselecteerde element (alleen als er precies één is).
    var singleElement: BannerElementRef? {
        count == 1 ? first : nil
    }

    /// De id's van alle geselecteerde tekst-lagen.
    var textIDs: [UUID] {
        compactMap { $0.textID }
    }
}
