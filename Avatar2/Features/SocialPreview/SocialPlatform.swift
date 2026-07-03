// Social-preview platform-model (E34.3). Canonieke maten + de plek van de
// profielcirkel in de cover wonen hier — één bron zodat de preview-mockup én
// de cover-export gelijk lopen. Instagram heeft geen cover (alleen een ronde
// profielfoto in de grid).

import CoreGraphics
import SwiftUI

enum SocialPlatform: String, CaseIterable, Identifiable {
    case linkedIn, x, instagram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linkedIn: "LinkedIn"
        case .x: "X"
        case .instagram: "Instagram"
        }
    }

    /// Heeft dit platform een cover/banner achter de profielfoto?
    var hasCover: Bool { coverSize != nil }

    /// Canonieke upload-maat van de cover/banner (px). nil = geen cover
    /// (Instagram-profiel heeft er geen).
    var coverSize: CGSize? {
        switch self {
        case .linkedIn: CGSize(width: 1584, height: 396)   // 4:1
        case .x:        CGSize(width: 1500, height: 500)   // 3:1
        case .instagram: nil
        }
    }

    /// Export-zijde (px) van de ronde profielfoto. Ruim boven elk platform-
    /// minimum (LinkedIn/X 400, IG 320) zodat de download crisp is.
    var profileExportSide: Int { 512 }

    /// Middelpunt van de profielcirkel BINNEN de cover, in cover-unit-coords
    /// (0–1, top-left origin). nil voor platforms zonder cover (Instagram).
    /// LinkedIn/X: linksonder, overlappend met de onderrand van de cover.
    var profileCenterInCover: UnitPoint? {
        switch self {
        case .linkedIn: UnitPoint(x: 0.14, y: 1.0)
        case .x:        UnitPoint(x: 0.13, y: 1.0)
        case .instagram: nil
        }
    }

    /// Diameter van de profielcirkel als fractie van de cover-HOOGTE. nil voor
    /// platforms zonder cover.
    var profileDiameterFraction: CGFloat? {
        switch self {
        case .linkedIn: 0.62
        case .x:        0.56
        case .instagram: nil
        }
    }
}
