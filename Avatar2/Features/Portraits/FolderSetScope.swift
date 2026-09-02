// E50.1 — map-brede selectie/actie-scope. Pure helpers voor "hele map in één
// actie": dezelfde item-scope als de Portraits-lenzen (map-filter + jongste
// eerst, zoals de @Query op updatedAt reverse) zodat map-acties uit de left-nav
// en ⌘A in de lenzen exact dezelfde set raken als wat er op het scherm staat.

import Foundation
import SwiftData

enum FolderSetScope {
    /// De zichtbare portretten voor een map-scope (nil = alle portretten),
    /// in lens-volgorde (jongst bewerkt eerst — spiegelt de @Query van
    /// `PortraitsGalleryView`).
    static func items(in portraits: [Portrait2], folderID: PersistentIdentifier?) -> [Portrait2] {
        let scoped = folderID == nil
            ? portraits
            : portraits.filter { $0.folder?.persistentModelID == folderID }
        return scoped.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Referentie voor een map-brede Match lighting zonder aangeklikte tegel:
    /// het jongst bewerkte portret (bovenaan in elke lens — voorspelbaar).
    /// E50.3: niet langer dé referentie — `PortraitSetActions.matchLighting`
    /// kiest zelf het doel; dit is alleen nog de tie-break bij gelijke stand.
    static func matchLightingReference(_ items: [Portrait2]) -> Portrait2? {
        items.max { $0.updatedAt < $1.updatedAt }
    }
}
