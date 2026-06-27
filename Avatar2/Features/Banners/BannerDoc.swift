// Banner Studio-document (E37.1). Een BEWERKBAAR, herbruikbaar banner-document:
// in tegenstelling tot het platte `Banner2` (één PNG) bewaart `BannerDoc` een
// geserialiseerde LAAG-stack (fill · tekst · logo · shaders) zodat de Banner
// Studio (E37.2) het document opnieuw kan openen en bewerken. Zware image-bytes
// (fill-afbeelding, logo) staan als losse externalStorage-blobs náást de
// lichtgewicht JSON-laagstack; een gecachte `previewImageData` (gerenderde wijde
// PNG) voedt de thumbnails en de social-preview-compat (BannerChooser/-Resolver).
//
// Eigen SwiftData-store-entiteit náást Portrait2/Folder2/Banner2. `Banner2`
// blijft bestaan (migratiepad: een platte banner opent als één image-fill-laag —
// geen dataverlies; zie `BannerDoc.from(banner2:)`).

import Foundation
import SwiftData
import CoreGraphics

@Model
final class BannerDoc {
    var name: String
    var createdAt: Date
    /// Laatst bewerkt; lichtgewicht migratie via `.distantPast` (zoals Portrait2/Banner2).
    var updatedAt: Date = Date.distantPast

    /// Canvas-maat in pixels (wijd). Default 1500×500 (X-cover). Non-destructief
    /// herschaalbaar via de Size-preset (E37.6).
    var canvasWidth: Double = 1500
    var canvasHeight: Double = 500

    /// De lichtgewicht laag-stack als JSON (`BannerLayers`). externalStorage houdt
    /// de rij licht; zware beeld-bytes staan apart (hieronder).
    @Attribute(.externalStorage) var layersData: Data
    /// Bron-bytes voor `BannerFill.image` (upload/CMS/AI). nil tenzij de fill een
    /// afbeelding is.
    @Attribute(.externalStorage) var fillImageData: Data?
    /// Bron-bytes voor de logo-laag (PNG met alpha). nil tenzij er een logo is.
    @Attribute(.externalStorage) var logoImageData: Data?
    /// Gecachte gerenderde wijde PNG (thumbnails + social-preview-compat). Wordt
    /// bij Done (E37.6) / debounced auto-bake ververst.
    @Attribute(.externalStorage) var previewImageData: Data?

    /// Genormaliseerd brandpunt (0…1) voor `.image`-fill — verschuift aspect-fill.
    var fillImageFocalX: Double = 0.5
    var fillImageFocalY: Double = 0.5
    /// Zoom t.o.v. aspect-fill (1 = fit-fill; >1 zoomt in).
    var fillImageZoom: Double = 1.0

    init(
        name: String = "",
        createdAt: Date = .now,
        canvasSize: CGSize = CGSize(width: 1500, height: 500),
        layers: BannerLayers = .empty,
        fillImageData: Data? = nil,
        logoImageData: Data? = nil,
        previewImageData: Data? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.canvasWidth = canvasSize.width
        self.canvasHeight = canvasSize.height
        self.layersData = (try? JSONEncoder().encode(layers)) ?? Data()
        self.fillImageData = fillImageData
        self.logoImageData = logoImageData
        self.previewImageData = previewImageData
    }

    func touch() { updatedAt = .now }

    var canvasSize: CGSize { CGSize(width: canvasWidth, height: canvasHeight) }

    /// Zet een image-fill atomisch: bytes + fill-type + optioneel framing-reset.
    func applyFillImage(_ png: Data, resetFraming: Bool = true) {
        fillImageData = png
        if resetFraming {
            fillImageFocalX = 0.5
            fillImageFocalY = 0.5
            fillImageZoom = 1.0
        }
        var l = layers
        l.fill = .image
        layers = l
    }

    /// De gedecodeerde laag-stack. Setter her-encodeert + `touch()`. Faalt een
    /// decode (corrupte/lege blob) dan valt 'ie terug op `.empty`.
    var layers: BannerLayers {
        get { (try? JSONDecoder().decode(BannerLayers.self, from: layersData)) ?? .empty }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) { layersData = encoded }
            touch()
        }
    }

    /// Migratiepad (E35→E37): open een bestaande platte `Banner2` als één
    /// image-fill-`BannerDoc` zonder dataverlies.
    static func from(banner2: Banner2) -> BannerDoc {
        BannerDoc(
            name: banner2.name,
            createdAt: banner2.createdAt,
            layers: BannerLayers(fill: .image),
            fillImageData: banner2.imageData,
            previewImageData: banner2.imageData
        )
    }
}

// MARK: - Laag-stack (Codable value-types)

/// De volledige, serialiseerbare laag-stack van een banner. Zware beeld-bytes
/// leven NIET hier maar als losse externalStorage-blobs op `BannerDoc`; deze
/// value-types houden alleen lichtgewicht descriptoren (hex/stops/tekst/params/
/// transforms) vast.
struct BannerLayers: Codable, Equatable, Sendable {
    var fill: BannerFill
    var texts: [BannerTextLayer]
    var logo: BannerLogoLayer?
    /// Forward-compat voor de shaders-engine (E38): geordende procedurale lagen.
    var shaders: [BannerShaderLayer]

    init(
        fill: BannerFill = .solid(hex: "#1C1917"),
        texts: [BannerTextLayer] = [],
        logo: BannerLogoLayer? = nil,
        shaders: [BannerShaderLayer] = []
    ) {
        self.fill = fill
        self.texts = texts
        self.logo = logo
        self.shaders = shaders
    }

    static let empty = BannerLayers()
}

/// De achtergrond-vulling. `.image` verwijst naar `BannerDoc.fillImageData`.
enum BannerFill: Equatable, Sendable {
    case solid(hex: String)
    case meshGradient(stops: [MeshStop])
    case image
}

extension BannerFill: Codable {
    private enum CodingKeys: String, CodingKey {
        case solid, meshGradient, image
    }

    init(from decoder: Decoder) throws {
        // Legacy: `"fill": "image"` (plain string i.p.v. keyed enum).
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            if raw == "image" {
                self = .image
                return
            }
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let hex = try container.decodeIfPresent(String.self, forKey: .solid) {
            self = .solid(hex: hex)
            return
        }
        if let stops = try container.decodeIfPresent([MeshStop].self, forKey: .meshGradient) {
            self = .meshGradient(stops: stops)
            return
        }
        if container.contains(.image) {
            _ = try container.decodeNil(forKey: .image)
            self = .image
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown BannerFill"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .solid(hex):
            try container.encode(hex, forKey: .solid)
        case let .meshGradient(stops):
            try container.encode(stops, forKey: .meshGradient)
        case .image:
            try container.encodeNil(forKey: .image)
        }
    }
}

/// Eén kleur-stop van een mesh-gradient, op genormaliseerde (0…1) positie.
struct MeshStop: Codable, Equatable, Sendable {
    var hex: String
    var x: Double
    var y: Double
}

/// Een tekstlaag. Positie/rotatie genormaliseerd t.o.v. het canvas (0…1) zodat
/// een Size-herschaling (E37.6) de lay-out behoudt.
struct BannerTextLayer: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var string: String = "Text"
    var fontName: String?       // nil = systeemfont
    var fontSize: Double = 64   // in canvas-pixels
    var weightRaw: Int = 0      // mapt op NSFont.Weight (zie BannerTextLayer.weight)
    var colorHex: String = "#FFFFFF"
    var alignRaw: Int = 0       // 0=left 1=center 2=right
    var x: Double = 0.5         // genormaliseerd middelpunt
    var y: Double = 0.5
    var rotation: Double = 0    // graden
    var tracking: Double = 0
    var lineSpacing: Double = 0
}

/// Een logo/merkbeeld-laag; bytes in `BannerDoc.logoImageData`.
struct BannerLogoLayer: Codable, Equatable, Sendable {
    var x: Double = 0.5         // genormaliseerd middelpunt
    var y: Double = 0.5
    var scale: Double = 0.25    // breedte als fractie van het canvas
}

/// Forward-compat (E38): een procedurale shader-laag. `params` als [naam:waarde]
/// blijft Codable-vriendelijk; de engine (E38.1) verfijnt het type later.
struct BannerShaderLayer: Codable, Equatable, Sendable, Identifiable {
    var id: UUID = UUID()
    var key: String
    var params: [String: Double] = [:]
    var enabled: Bool = true
}
