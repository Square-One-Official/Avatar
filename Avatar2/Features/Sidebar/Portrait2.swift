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
    /// Of `cutoutData` nog een schone isolatie van de originele foto is (zo ja:
    /// true) of dat een generatieve edit de pixels heeft vervangen (false). Stuurt
    /// "Remove background": bij true her-isoleren we de ORIGINELE foto (volle
    /// kleurcontext = scherpste haar-matte, gelijk aan de import), bij false het
    /// huidige beeld zelf (anders zou je de edit weggooien). Default true (verse
    /// import); elke generatieve cutout-overschrijving zet 'm op false.
    var cutoutDerivesFromOriginal: Bool = true
    /// Het laatste VOLLE generatieve resultaat (onderwerp + door de AI toegevoegde
    /// achtergrond), vóór isolatie — bewaard zodat "Remove background" het later met
    /// ORMBG schoon kan her-isoleren (nieuw haar behouden, per-ongeluk-achtergrond
    /// weg). Niet voor Face-edits (die hergebruiken de alpha). nil = geen generatieve
    /// edit te her-isoleren; wordt gewist zodra de cutout weer een schone
    /// origineel-isolatie is. ~1 vol beeld per generatief-bewerkt portret.
    @Attribute(.externalStorage) var editSourceData: Data?
    /// Stabiele signature (`Portrait2.cutoutSignature`) van de `cutoutData` waarvan
    /// `editSourceData` de bron is. Stempel om staleness te detecteren: wijkt de
    /// signature van de huidige `cutoutData` hiervan af (bv. na een undo/redo of een
    /// Match Lighting die de cutout terugzette/verving), dan hoort `editSourceData`
    /// niet meer bij dit beeld → "Remove background" negeert het (geen edit-resurrectie).
    /// Een content-signature i.p.v. alleen `count` zodat twee verschillende cutouts met
    /// toevallig gelijke grootte niet vals matchen.
    var editSourceCutoutSig: Int = 0

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

    /// PoC (left-nav): de map waarin dit portret is ingedeeld (Portraits-
    /// galerij). Optionele to-one; de inverse + delete-rule wonen op
    /// `Folder2.portraits`. nil = "Unfiled". Lichtgewicht migratie via nil.
    var folder: Folder2?

    /// E24.33: Effects-cache op het portret. `effectBaseData` = de cutout van
    /// vóór er een effect werd toegepast ("None"/origineel voor de Effects-
    /// feature, eenmalig vastgelegd). `effectActiveRaw` = het actieve effect
    /// (RemoteEffect.key), nil = None. `effectCacheData` = binaire plist van
    /// [key: PNG-Data] met de al gegenereerde resultaten → schakelen tussen
    /// None/effecten is INSTANT en kost geen nieuwe credits (alleen het refresh-
    /// icoon hergenereert bewust). Lichtgewicht migratie via de defaults.
    @Attribute(.externalStorage) var effectBaseData: Data?
    var effectActiveRaw: String?
    @Attribute(.externalStorage) var effectCacheData: Data?

    /// E24.33: de effect-cache als [key: PNG-Data] in `effectCacheData`.
    /// E49.3: opslag = binaire plist (Data blijft rauw) i.p.v. JSON, dat élke
    /// PNG base64'de (+33% opslag). Lezen valt terug op JSON voor portretten
    /// die vóór deze wissel zijn geschreven; de eerstvolgende set herschrijft
    /// als plist.
    var effectCache: [String: Data] {
        get {
            guard let effectCacheData else { return [:] }
            if let decoded = try? PropertyListDecoder()
                .decode([String: Data].self, from: effectCacheData) {
                return decoded
            }
            let json = try? JSONDecoder().decode([String: Data].self, from: effectCacheData)
            return json ?? [:]
        }
        set {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            effectCacheData = try? encoder.encode(newValue)
        }
    }

    /// De gestylede VOLLE afbeelding (incl. gestylede achtergrond) van het ACTIEVE
    /// effect — gebruikt als Original-achtergrondlaag zodat de backdrop bij het
    /// effect past. Sinds effects de volle originele foto styleren (i.p.v. de
    /// cutout) ÍS de `effectCache`-waarde dat volle beeld. nil = geen actief effect
    /// → val terug op de rauwe originele foto.
    /// In-memory cache (niet gepersisteerd/geobserveerd) zodat herhaalde reads
    /// niet telkens de hele effect-cache-JSON parsen — zelfde patroon als
    /// `BannerDoc.layers`. Sleutel = actief effect + bron-bytes; bij wijziging mist
    /// de cache en herberekent.
    @Transient @ObservationIgnored private var cachedEffectBg: Data? = nil
    @Transient @ObservationIgnored private var cachedEffectBgActive: String? = nil
    @Transient @ObservationIgnored private var cachedEffectBgSource: Data? = nil

    var effectBackgroundData: Data? {
        guard let key = effectActiveRaw, let effectCacheData else { return nil }
        if cachedEffectBgActive == key, cachedEffectBgSource == effectCacheData {
            return cachedEffectBg
        }
        // Alleen de ACTIEVE entry uitpakken i.p.v. via `effectCache` de héle
        // [key: PNG]-dict te decoderen. E49.3: opslag is binaire plist
        // (PropertyListSerialization geeft [key: Data] zonder base64-stap);
        // JSON-pad blijft als leesfallback voor pre-E49.3-portretten, waar
        // JSONEncoder `Data` als base64-string schreef.
        var decoded: Data?
        if let plist = try? PropertyListSerialization
            .propertyList(from: effectCacheData, options: [], format: nil) as? [String: Data] {
            decoded = plist[key]
        } else if let object = try? JSONSerialization.jsonObject(with: effectCacheData) as? [String: String],
                  let base64 = object[key] {
            decoded = Data(base64Encoded: base64)
        }
        cachedEffectBg = decoded
        cachedEffectBgActive = key
        cachedEffectBgSource = effectCacheData
        return decoded
    }

    /// E24.31: "Original"-achtergrond. Sinds 2026-06-23 (Thierry) = gebruik de
    /// ORIGINELE importfoto als achtergrondLAAG met het (scherpe, bewerkte)
    /// onderwerp eroverheen — i.p.v. de hele originele foto vol te tonen. Zo kan
    /// Portrait de echte achtergrond vervagen en volgen onderwerp-edits mee.
    /// Cutout-default (false); de Background-keuze is omkeerbaar (Original ↔
    /// Transparent ↔ kleur/afbeelding) zonder opnieuw te importeren. Vereist
    /// `originalData`. Lichtgewicht migratie via de default.
    var useOriginalBackground: Bool = false

    /// Portrait-modus (Thierry 2026-06-23; "Portrait"-chip in Enhance) — vervaagt
    /// de achtergrondLAAG (origineel óf custom afbeelding) terwijl het onderwerp
    /// scherp blijft, zoals de macOS-webcam-Portrait. Niet-destructief, per
    /// portret, undo'baar. Zonder gekozen achtergrond valt het render-time terug
    /// op de originele foto. Lichtgewicht migratie via de default (false).
    var portraitBlur: Bool = false

    /// E34: Banner-achtergrond voor de social-preview-covers (LinkedIn/X). APART
    /// van de portret-`background`: de banner is wijd (4:1 / 3:1) en kan de
    /// portret-achtergrond MATCHEN óf ervan afwijken (eigen kleur/afbeelding). De
    /// "precies één modus"-invariant woont in `bannerBackground`/`setBannerBackground`
    /// (spiegelt `background`). Default = `.matchPortrait` (zero-config: de banner
    /// volgt de avatar-achtergrond). Lichtgewicht migratie via de defaults
    /// (`bannerMatchesBackground` = true, kleur/afbeelding nil).
    var bannerColorHex: String?
    @Attribute(.externalStorage) var bannerImageData: Data?
    var bannerMatchesBackground: Bool = true

    /// E40.2: stabiele verwijzing (encoded `PersistentIdentifier`) naar de
    /// `BannerDoc` waarvan de huidige `.image`-achtergrond is overgenomen — nil
    /// als de achtergrond niet (meer) van een banner komt. Maakt een "Update
    /// background"-actie mogelijk wanneer die banner later in de Studio wijzigt
    /// (de opgeslagen bytes lopen dan achter op `BannerDoc.previewImageData`).
    /// Wordt door elke `setBackground` gewist en alléén door de banner-bron weer
    /// gezet. Lichtgewicht migratie via de default (nil).
    var backgroundBannerID: String?

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

    /// E13.2: v1-UUID wanneer dit portret uit een Aaavatar 1-back-up komt —
    /// de dedup-sleutel die her-import idempotent maakt. nil voor alles wat in
    /// v2 zelf is gemaakt. Lichtgewicht migratie via de nil-default.
    var v1ImportID: String?

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

    /// Zet de achtergrond-modus (wist de andere twee velden) + `touch()`. Wist
    /// ook de E40.2-bannerkoppeling; de banner-bron zet 'm daarna expliciet
    /// terug zodat alleen een uit-een-banner overgenomen achtergrond gekoppeld
    /// blijft.
    func setBackground(_ background: PortraitBackground) {
        backgroundBannerID = nil
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

    /// E34: de banner-keuze als ÉÉN waarde-object (spiegelt `background`).
    /// Precies één van: match-portret (default), kleur (hex) of afbeelding
    /// (upload/gradient/CMS/AI — wijde PNG-bytes).
    var bannerBackground: BannerBackground {
        if bannerMatchesBackground { return .matchPortrait }
        if let bannerColorHex { return .color(bannerColorHex) }
        if let bannerImageData { return .image(bannerImageData) }
        return .matchPortrait
    }

    /// Zet de banner-modus (wist de andere velden) + `touch()`.
    func setBannerBackground(_ banner: BannerBackground) {
        switch banner {
        case .matchPortrait:
            bannerMatchesBackground = true; bannerColorHex = nil; bannerImageData = nil
        case .color(let hex):
            bannerMatchesBackground = false; bannerColorHex = hex; bannerImageData = nil
        case .image(let data):
            bannerMatchesBackground = false; bannerColorHex = nil; bannerImageData = data
        }
        touch()
    }

    /// Stabiele, launch-onafhankelijke content-signature van cutout-bytes voor de
    /// `editSourceCutoutSig`-staleness-stempel. Swift's `Hasher` is per-launch
    /// gerandomiseerd → onbruikbaar om te persisteren; deze FNV-1a over grootte +
    /// ~256 verspreide bytes is deterministisch en botst vrijwel nooit tussen twee
    /// verschillende cutouts. Goedkoop (constante samples), alleen op knop-tik/edit.
    static func cutoutSignature(_ data: Data) -> Int {
        var h: UInt64 = 1469598103934665603
        let prime: UInt64 = 1099511628211
        h = (h ^ UInt64(truncatingIfNeeded: data.count)) &* prime
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard buf.count > 0 else { return }
            let step = max(1, buf.count / 256)
            var i = 0
            while i < buf.count {
                h = (h ^ UInt64(buf[i])) &* prime
                i += step
            }
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
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

/// E34: de banner-achtergrond-modus (social-preview-covers). Precies één van:
/// match-portret (leid af uit `Portrait2.background`), kleur (hex) of afbeelding
/// (upload/gradient/CMS/AI — wijde PNG-bytes). Een aparte enum i.p.v.
/// `PortraitBackground`: de banner heeft een match-modus die het portret niet
/// kent, is wijd-aspect, en mag bewust van de portret-achtergrond afwijken.
enum BannerBackground: Equatable {
    case matchPortrait
    case color(String)
    case image(Data)
}

/// E24.14: niet-destructieve Adjust-laag (brightness/contrast/saturation/
/// temperature) als waarde-object. Neutraal = identiteit.
struct PortraitAdjust: Equatable, Sendable {
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var temperature: Double = 0

    static let neutral = PortraitAdjust()
    var isNeutral: Bool { self == .neutral }
}
