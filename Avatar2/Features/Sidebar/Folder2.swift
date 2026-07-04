// PoC (left-nav): persistente map/werkruimte voor het organiseren van
// portretten ("Portraits"-galerij, Riverside-stijl). Eigen SwiftData-model,
// losjes naast Portrait2 — een portret hoort in hoogstens één map (optionele
// to-one); `folder == nil` = "Unfiled". De inverse-relatie woont hier
// (`@Relationship(inverse:)`), Portrait2 houdt alleen de kale `folder?`.
// Lichtgewicht migratie: nieuw model + nieuwe optionele relatie → bestaande
// rijen krijgen `folder = nil`.

import Foundation
import SwiftData

@Model
final class Folder2 {
    var name: String
    var createdAt: Date
    /// Sorteervolgorde in de galerij (handmatig herschikbaar later).
    var order: Int = 0
    /// Optionele tag-kleur (Riverside-stijl), hex #RRGGBB. nil = neutraal.
    var colorHex: String?

    /// Standaardachtergrond voor nieuwe imports in deze map (kleur xor
    /// afbeelding). Beide nil = geen default — imports blijven transparant.
    /// Lichtgewicht migratie via nil-defaults.
    var defaultBackgroundColorHex: String?
    @Attribute(.externalStorage) var defaultBackgroundImageData: Data?

    /// De portretten in deze map. `nullify` zodat het verwijderen van een map
    /// de portretten zelf niet wist — ze vallen terug naar "Unfiled".
    @Relationship(deleteRule: .nullify, inverse: \Portrait2.folder)
    var portraits: [Portrait2] = []

    init(name: String, createdAt: Date = .now, order: Int = 0, colorHex: String? = nil) {
        self.name = name
        self.createdAt = createdAt
        self.order = order
        self.colorHex = colorHex
    }

    /// De geconfigureerde standaardachtergrond, of nil wanneer geen default is
    /// ingesteld (imports in deze map krijgen dan geen achtergrond).
    var defaultBackground: PortraitBackground? {
        if let defaultBackgroundColorHex { return .color(defaultBackgroundColorHex) }
        if let defaultBackgroundImageData { return .image(defaultBackgroundImageData) }
        return nil
    }

    /// Zet of wist de map-default (`.transparent` = geen default). `.original`
    /// is op mapniveau geen zinvolle keuze en wordt genegeerd.
    func setDefaultBackground(_ background: PortraitBackground) {
        switch background {
        case .transparent, .original:
            defaultBackgroundColorHex = nil
            defaultBackgroundImageData = nil
        case .color(let hex):
            defaultBackgroundColorHex = hex
            defaultBackgroundImageData = nil
        case .image(let data):
            defaultBackgroundColorHex = nil
            defaultBackgroundImageData = data
        }
    }
}
