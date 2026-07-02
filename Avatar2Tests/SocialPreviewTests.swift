// E47.3 — social-preview platform-switch-logica (E34). De segmented control
// stuurt via `PreviewTab.platforms` welke platform-mockups renderen; de
// platform-geometrie (cover-maat/-ratio, profielcirkel) is de gedeelde bron
// van mockup én cover-export. Banner-vulling: `BannerResolver` vertaalt de
// banner-keuze (match/kleur/afbeelding) naar een compositor-fill.

import AvatarKit
import SwiftData
import XCTest
@testable import Avatar2

@MainActor
final class SocialPreviewTests: XCTestCase {

    // MARK: - PreviewTab → platforms (de switch-logica achter de segmented control)

    func testEnkelePlatformTabsTonenAlleenZichzelf() {
        XCTAssertEqual(PreviewTab.linkedIn.platforms, [.linkedIn])
        XCTAssertEqual(PreviewTab.x.platforms, [.x])
        XCTAssertEqual(PreviewTab.instagram.platforms, [.instagram])
    }

    func testAllTabToontAllePlatformsInCanoniekeVolgorde() {
        XCTAssertEqual(PreviewTab.all.platforms, SocialPlatform.allCases)
        XCTAssertEqual(PreviewTab.all.platforms, [.linkedIn, .x, .instagram])
    }

    func testElkPlatformKomtInPreciesEenEnkeleTabVoor() {
        // Elke platform-mockup moet via precies één niet-All-tab bereikbaar zijn —
        // een nieuw platform zonder eigen tab zou stilletjes alleen onder All vallen.
        let singleTabs = PreviewTab.allCases.filter { $0 != .all }
        for platform in SocialPlatform.allCases {
            let hits = singleTabs.filter { $0.platforms == [platform] }
            XCTAssertEqual(hits.count, 1, "\(platform) hoort in precies één eigen tab")
        }
    }

    // MARK: - Platform-geometrie (mockup en cover-export delen deze bron)

    func testInstagramHeeftGeenCoverLinkedInEnXWel() {
        XCTAssertFalse(SocialPlatform.instagram.hasCover)
        XCTAssertNil(SocialPlatform.instagram.coverSize)
        XCTAssertNil(SocialPlatform.instagram.profileCenterInCover)
        XCTAssertNil(SocialPlatform.instagram.profileDiameterFraction)

        XCTAssertTrue(SocialPlatform.linkedIn.hasCover)
        XCTAssertTrue(SocialPlatform.x.hasCover)
    }

    func testCoverMatenVolgenDePlatformRatios() throws {
        let linkedIn = try XCTUnwrap(SocialPlatform.linkedIn.coverSize)
        XCTAssertEqual(linkedIn.width / linkedIn.height, 4, accuracy: 0.001, "LinkedIn-cover is 4:1")
        let x = try XCTUnwrap(SocialPlatform.x.coverSize)
        XCTAssertEqual(x.width / x.height, 3, accuracy: 0.001, "X-cover is 3:1")
    }

    // MARK: - BannerResolver (banner-vulling die de preview toont)

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Portrait2.self, configurations: config)
        return ModelContext(container)
    }

    func testMatchPortraitVolgtDeVlakkeAchtergrondkleur() throws {
        let context = try makeContext()
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)
        portrait.setBackground(.color("#FF0000"))

        guard case let .color(r, g, b) = BannerResolver.fill(for: portrait, banner: .matchPortrait) else {
            return XCTFail("verwacht een kleur-fill die de portret-achtergrond matcht")
        }
        XCTAssertEqual(r, 1, accuracy: 0.005)
        XCTAssertEqual(g, 0, accuracy: 0.005)
        XCTAssertEqual(b, 0, accuracy: 0.005)
    }

    func testMatchPortraitZonderKleurEnOrigineelValtTerugOpNeutraal() throws {
        let context = try makeContext()
        // Transparante achtergrond + geen originalData → niets te matchen.
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)

        guard case let .color(r, g, b) = BannerResolver.fill(for: portrait, banner: .matchPortrait),
              case let .color(nr, ng, nb) = BannerResolver.neutralFallback else {
            return XCTFail("verwacht de neutrale fallback-kleur")
        }
        XCTAssertEqual(r, nr); XCTAssertEqual(g, ng); XCTAssertEqual(b, nb)
    }

    func testOngeldigeBannerHexValtTerugOpNeutraal() throws {
        let context = try makeContext()
        let portrait = Portrait2(cutoutData: Data([1]))
        context.insert(portrait)

        guard case let .color(r, g, b) = BannerResolver.fill(for: portrait, banner: .color("not-a-hex")),
              case let .color(nr, ng, nb) = BannerResolver.neutralFallback else {
            return XCTFail("verwacht de neutrale fallback-kleur bij een onparseerbare hex")
        }
        XCTAssertEqual(r, nr); XCTAssertEqual(g, ng); XCTAssertEqual(b, nb)
    }
}
