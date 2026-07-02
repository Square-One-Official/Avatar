// E46.2 — banner-delete moet de E40.2-koppeling opruimen: portretten die hun
// achtergrond van de verwijderde banner overnamen verliezen alleen hun
// `backgroundBannerID`; de achtergrond-pixeldata blijft staan. Portretten die
// aan een ándere banner gekoppeld zijn blijven ongemoeid.

import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class BannerDeletionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Portrait2.self, BannerDoc.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// Koppel een portret aan een banner zoals BackgroundPanel dat doet
    /// (achtergrond-bytes overnemen + linkKey vastleggen).
    private func link(_ portrait: Portrait2, to banner: BannerDoc) {
        portrait.setBackground(.image(banner.previewImageData ?? Data()))
        portrait.backgroundBannerID = BannerDeletion.linkKey(for: banner)
    }

    func testDeleteWistKoppelingVanAlleGekoppeldePortretten() throws {
        let context = try makeContext()
        let banner = BannerDoc(name: "Cover", previewImageData: Data([1, 2, 3]))
        let other = BannerDoc(name: "Other", previewImageData: Data([9]))
        let linked1 = Portrait2(cutoutData: Data([1]))
        let linked2 = Portrait2(cutoutData: Data([2]))
        let otherLinked = Portrait2(cutoutData: Data([3]))
        let unlinked = Portrait2(cutoutData: Data([4]))
        [banner, other].forEach { context.insert($0) }
        [linked1, linked2, otherLinked, unlinked].forEach { context.insert($0) }
        try context.save() // permanente PersistentIdentifiers vóór het koppelen

        link(linked1, to: banner)
        link(linked2, to: banner)
        link(otherLinked, to: other)
        try context.save()

        BannerDeletion.delete(banner, in: context)
        try context.save()

        // Beide gekoppelde portretten: koppeling weg, pixeldata blijft.
        XCTAssertNil(linked1.backgroundBannerID)
        XCTAssertNil(linked2.backgroundBannerID)
        XCTAssertEqual(linked1.backgroundImageData, Data([1, 2, 3]))
        XCTAssertEqual(linked2.backgroundImageData, Data([1, 2, 3]))

        // Portretten gekoppeld aan een andere (of geen) banner: ongemoeid.
        // (Vergelijk op gedecodeerde identiteit — de encoded string zelf is
        // niet byte-stabiel, zie BannerDeletion.linkKey.)
        XCTAssertEqual(
            BannerDeletion.bannerID(from: otherLinked.backgroundBannerID),
            other.persistentModelID
        )
        XCTAssertNil(unlinked.backgroundBannerID)

        // De banner zelf is echt weg; de andere blijft.
        let banners = try context.fetch(FetchDescriptor<BannerDoc>())
        XCTAssertEqual(banners.count, 1)
        XCTAssertEqual(banners.first?.name, "Other")
    }

    func testDeleteZonderGekoppeldePortrettenVerwijdertAlleenDeBanner() throws {
        let context = try makeContext()
        let banner = BannerDoc(name: "Solo")
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(banner)
        context.insert(portrait)
        try context.save()

        BannerDeletion.delete(banner, in: context)
        try context.save()

        XCTAssertNil(portrait.backgroundBannerID)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BannerDoc>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Portrait2>()).count, 1)
    }

    /// linkKey ↔ bannerID moeten round-trippen naar de juiste identiteit. De
    /// encoded string zelf is NIET byte-stabiel (JSONEncoder garandeert geen
    /// sleutelvolgorde) — daarom vergelijkt de cleanup op de gedecodeerde
    /// `PersistentIdentifier`, en test deze test precies dat pad.
    func testLinkKeyRoundTriptNaarDeJuisteBanner() throws {
        let context = try makeContext()
        let a = BannerDoc(name: "A")
        let b = BannerDoc(name: "B")
        context.insert(a)
        context.insert(b)
        try context.save()

        let keyA = try XCTUnwrap(BannerDeletion.linkKey(for: a))
        XCTAssertEqual(BannerDeletion.bannerID(from: keyA), a.persistentModelID)
        XCTAssertNotEqual(BannerDeletion.bannerID(from: keyA), b.persistentModelID)

        // Corrupte of lege sleutels decoderen naar nil (en crashen dus nooit).
        XCTAssertNil(BannerDeletion.bannerID(from: nil))
        XCTAssertNil(BannerDeletion.bannerID(from: "geen-base64"))
        XCTAssertNil(BannerDeletion.bannerID(from: Data([1, 2, 3]).base64EncodedString()))
    }
}
