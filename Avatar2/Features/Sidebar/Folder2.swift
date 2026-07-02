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

    /// De portretten in deze map. `nullify` zodat het verwijderen van een map
    /// de portretten zelf niet wist — ze vallen terug naar "Unfiled".
    @Relationship(deleteRule: .nullify, inverse: \Portrait2.folder)
    var portraits: [Portrait2] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }
}
