// E46.2 — Centrale banner-delete. Eén plek die een `BannerDoc` verwijdert én de
// E40.2-koppeling opruimt: portretten die hun achtergrond van deze banner
// overnamen (`Portrait2.backgroundBannerID`) verliezen alleen de verwijzing —
// de achtergrond-pixeldata (`backgroundImageData`) blijft gewoon staan. Zonder
// deze opruiming blijft de ID dangling en kan de "Update"-badge in
// BackgroundPanel nooit meer matchen (audit-bevinding C9). ALLE banner-deletes
// horen via `BannerDeletion.delete(_:in:)` te lopen.

import Foundation
import SwiftData

enum BannerDeletion {
    /// Koppel-sleutel voor een banner: de encoded `PersistentIdentifier` als
    /// base64 — zelfde encoding als `bannerKey` in `BackgroundPanel` (de plek
    /// die de koppeling zet). LET OP: `JSONEncoder` garandeert geen
    /// sleutelvolgorde, dus twee encodes van dezélfde ID kunnen verschillende
    /// bytes opleveren. Sleutels dus nooit byte-vergelijken — altijd via
    /// `bannerID(from:)` decoderen en de `PersistentIdentifier`s vergelijken.
    static func linkKey(for doc: BannerDoc) -> String? {
        (try? JSONEncoder().encode(doc.persistentModelID))?.base64EncodedString()
    }

    /// Decodeert een opgeslagen koppel-sleutel terug naar de banner-identiteit.
    /// nil bij een corrupte/onleesbare sleutel.
    static func bannerID(from key: String?) -> PersistentIdentifier? {
        guard let key, let data = Data(base64Encoded: key) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    /// Verwijdert de banner uit de store en wist `backgroundBannerID` op alle
    /// portretten die aan deze banner gekoppeld zijn.
    static func delete(_ doc: BannerDoc, in context: ModelContext) {
        unlinkPortraits(from: doc, in: context)
        context.delete(doc)
    }

    /// Zet `backgroundBannerID` op nil bij elk portret dat naar `doc` wijst.
    /// Los aanroepbaar (en testbaar) zonder de delete zelf. Matcht op de
    /// gedecodeerde `PersistentIdentifier` (niet op de rauwe string, zie
    /// `linkKey`-doc), dus het predicate filtert alleen op "heeft een koppeling".
    static func unlinkPortraits(from doc: BannerDoc, in context: ModelContext) {
        let target = doc.persistentModelID
        let descriptor = FetchDescriptor<Portrait2>(
            predicate: #Predicate { $0.backgroundBannerID != nil }
        )
        guard let candidates = try? context.fetch(descriptor) else { return }
        for portrait in candidates where bannerID(from: portrait.backgroundBannerID) == target {
            portrait.backgroundBannerID = nil
        }
    }
}
