// Sidebar/set-model (E05.4). Eigen SwiftData-store van Avatar2, volledig
// los van de v1-store (andere bundle-id én eigen container) — v1 blijft
// onaangeraakt. Cutout als externe blob; thumbnails rendert de sidebar
// uit dezelfde data.

import Foundation
import SwiftData

@Model
final class Portrait2 {
    var name: String
    var role: String
    var createdAt: Date
    /// Laatst bewerkt (visuele pass punt 13) — bijgewerkt bij elke mutatie
    /// (naam/rol/cutout; achtergrond zodra dat veld bestaat). Sidebar
    /// sorteert hierop (jongste bovenaan) en launch selecteert de jongste.
    /// Migratie: lichtgewicht via de default `.distantPast`; ShellModel
    /// zet bestaande rijen eenmalig op `createdAt` (de bedoelde default —
    /// SwiftData kan niet naar een ander veld defaulten).
    var updatedAt: Date = Date.distantPast
    @Attribute(.externalStorage) var cutoutData: Data
    /// Originele importfoto (E06.2 hold-to-compare): ingedrukt houden toont
    /// dit i.p.v. de cutout. Optioneel + externalStorage; bestaande rijen
    /// (migratie default nil) verbergen de compare-knop.
    @Attribute(.externalStorage) var originalData: Data?

    /// Canvas-transform (E06.4) in 1024-units canvasruimte (v1-conventie):
    /// het cutout-beeld tekent op (offsetX, offsetY) × scale binnen het
    /// 1:1-canvas. scale 0 = nog geen transform — de editor toont dan de
    /// berekende fill-fit en persisteert pas bij het eerste gebaar.
    /// Lichtgewicht migratie via de defaults.
    var offsetX: Double = 0
    var offsetY: Double = 0
    var scale: Double = 0

    /// Achtergrond (E07.1): kleur (hex #RRGGBB) óf afbeelding (preset/
    /// upload). Eén van beide is gezet, of beide nil = geen achtergrond
    /// (dot-grid). Export-kwaliteit compositing volgt in E07.2; dit is de
    /// selectie + preview-bron. Migratie: defaults nil.
    var backgroundColorHex: String?
    @Attribute(.externalStorage) var backgroundImageData: Data?

    /// Adjust-laag (E24.14): NIET-destructieve color-correctie als bovenste
    /// filterlaag op de rauwe cutout. `cutoutData` blijft ongewijzigd; canvas
    /// én export passen deze params live toe (WYSIWYG). Neutraal = identiteit
    /// (brightness 0, contrast 1, saturation 1, temperature 0). Lichtgewicht
    /// migratie via de defaults. Heropenen van Adjust toont de stand terug.
    var adjustBrightness: Double = 0
    var adjustContrast: Double = 1
    var adjustSaturation: Double = 1
    var adjustTemperature: Double = 0

    /// Frame-vorm (E24.16): de zichtbare vorm van het portret op canvas + in de
    /// export. Default `circle` (merkvorm; bevestiging-TODO). Opgeslagen als
    /// rawValue van `ExportShape`; lichtgewicht migratie via de default.
    /// Bestaande rijen (default "circle") krijgen dus de cirkel — bedoeld.
    var frameShapeRaw: String = ExportShape.circle.rawValue

    /// E27.4: board-view-positie (scene-graph node), in board-space-punten (het
    /// MIDDEN van de node). `boardPlaced` = false → nog niet geplaatst, de board
    /// doet een auto-layout (grid) en schrijft dan echte coördinaten + zet de
    /// vlag. Een aparte Bool i.p.v. een nan-sentinel omdat SwiftData's
    /// lichtgewicht migratie nieuwe Double-kolommen met 0 (niet de Swift-default)
    /// vult voor bestaande rijen — een Bool defaultt wél betrouwbaar naar false.
    /// `boardOrder` bepaalt de auto-layout-volgorde + de z-stapeling.
    var boardX: Double = 0
    var boardY: Double = 0
    var boardOrder: Int = 0
    var boardPlaced: Bool = false

    /// E24.33: Effects-cache op het portret. `effectBaseData` = de cutout van
    /// vóór er een effect werd toegepast ("None"/origineel voor de Effects-
    /// feature, eenmalig vastgelegd). `effectActiveRaw` = het actieve effect
    /// (StylizeStyle.rawValue), nil = None. `effectCacheData` = JSON van
    /// [rawValue: PNG-Data] met de al gegenereerde resultaten → schakelen tussen
    /// None/effecten is INSTANT en kost geen nieuwe credits (alleen het refresh-
    /// icoon hergenereert bewust). Lichtgewicht migratie via de defaults.
    @Attribute(.externalStorage) var effectBaseData: Data?
    var effectActiveRaw: String?
    @Attribute(.externalStorage) var effectCacheData: Data?

    /// E24.33: de effect-cache als [rawValue: PNG-Data] (JSON in `effectCacheData`).
    var effectCache: [String: Data] {
        get {
            guard let effectCacheData,
                  let decoded = try? JSONDecoder().decode([String: Data].self, from: effectCacheData)
            else { return [:] }
            return decoded
        }
        set { effectCacheData = try? JSONEncoder().encode(newValue) }
    }

    /// E24.31: "Original"-achtergrond — toon de ORIGINELE importfoto (mét eigen
    /// achtergrond) i.p.v. de cutout + gekozen achtergrond. Cutout blijft de
    /// default (false); de Background-menu-keuze is omkeerbaar (Original ↔
    /// Transparent ↔ kleur/afbeelding) zonder opnieuw te importeren. Vereist
    /// `originalData`. Lichtgewicht migratie via de default. Een kleur/-
    /// afbeeldingskeuze of "Transparent" zet dit weer op false.
    var useOriginalBackground: Bool = false

    init(
        name: String = "",
        role: String = "",
        createdAt: Date = .now,
        cutoutData: Data,
        originalData: Data? = nil
    ) {
        self.name = name
        self.role = role
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.cutoutData = cutoutData
        self.originalData = originalData
    }

    /// Markeer als zojuist bewerkt.
    func touch() {
        updatedAt = .now
    }

    /// E24.14: de Adjust-laag als waarde-object (lezen/schrijven van de vier
    /// `adjust*`-velden in één keer).
    var adjust: PortraitAdjust {
        get {
            PortraitAdjust(
                brightness: adjustBrightness, contrast: adjustContrast,
                saturation: adjustSaturation, temperature: adjustTemperature
            )
        }
        set {
            adjustBrightness = newValue.brightness
            adjustContrast = newValue.contrast
            adjustSaturation = newValue.saturation
            adjustTemperature = newValue.temperature
        }
    }

    /// E24.16: de frame-vorm als enum (val terug op `.circle` bij een
    /// onbekende rawValue).
    var frameShape: ExportShape {
        get { ExportShape(rawValue: frameShapeRaw) ?? .circle }
        set { frameShapeRaw = newValue.rawValue }
    }

    /// Audit-cleanup (DDD): de achtergrond-keuze als ÉÉN waarde-object i.p.v.
    /// de drie losse velden (`useOriginalBackground`/`backgroundColorHex`/
    /// `backgroundImageData`). De "precies één modus"-invariant woont nu in de
    /// entity i.p.v. handmatig herhaald in BackgroundPanel/board-batch/export.
    var background: PortraitBackground {
        if useOriginalBackground { return .original }
        if let backgroundColorHex { return .color(backgroundColorHex) }
        if let backgroundImageData { return .image(backgroundImageData) }
        return .transparent
    }

    /// Zet de achtergrond-modus (wist de andere twee velden) + `touch()`.
    func setBackground(_ background: PortraitBackground) {
        switch background {
        case .transparent:
            useOriginalBackground = false; backgroundColorHex = nil; backgroundImageData = nil
        case .original:
            useOriginalBackground = true; backgroundColorHex = nil; backgroundImageData = nil
        case .color(let hex):
            useOriginalBackground = false; backgroundColorHex = hex; backgroundImageData = nil
        case .image(let data):
            useOriginalBackground = false; backgroundColorHex = nil; backgroundImageData = data
        }
        touch()
    }
}

/// Audit-cleanup (DDD): de achtergrond-modus van een portret. Precies één van:
/// transparant (vrijstaande cutout), origineel (importfoto vol), kleur (hex) of
/// afbeelding (preset/gradient/upload — als PNG-bytes).
enum PortraitBackground: Equatable {
    case transparent
    case original
    case color(String)
    case image(Data)
}

/// E24.14: niet-destructieve Adjust-laag (brightness/contrast/saturation/
/// temperature) als waarde-object. Neutraal = identiteit.
struct PortraitAdjust: Equatable {
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var temperature: Double = 0

    static let neutral = PortraitAdjust()
    var isNeutral: Bool { self == .neutral }
}
