// Banner-bibliotheek-model (E35.1). Een herbruikbare, WIJDE banner die de
// gebruiker maakt in de Banners-sectie en in de social-preview achter de
// profielfoto kiest. Eén beeld (upload/gradient/preset/later AI) als externe
// blob; per platform aspect-fill'd in de cover (BannerCompositor). Eigen
// SwiftData-store-entiteit náást Portrait2/Folder2.

import Foundation
import SwiftData

@Model
final class Banner2 {
    var name: String
    var createdAt: Date
    /// Laatst bewerkt; lichtgewicht migratie via `.distantPast` (zoals Portrait2).
    var updatedAt: Date = Date.distantPast
    /// Het bron-bannerbeeld (wijd). Wordt bij keuze in de preview als bytes naar
    /// het portret gekopieerd (`bannerBackground = .image`), zodat er geen
    /// SwiftData-relatie/migratie nodig is.
    @Attribute(.externalStorage) var imageData: Data

    init(name: String = "", createdAt: Date = .now, imageData: Data) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.imageData = imageData
    }

    func touch() { updatedAt = .now }
}
