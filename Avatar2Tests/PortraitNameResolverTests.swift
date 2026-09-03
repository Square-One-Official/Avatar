// Naamresolutie bij import: metadata-laag, validatie van model-antwoorden en
// de heuristiek-fallback. Het on-device model zelf (laag 2) staat hier uit —
// de uitkomst mag niet afhangen van Apple Intelligence op de test-Mac.

import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Avatar2

final class PortraitNameResolverTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PortraitNameResolver.onDeviceModelEnabled = false
    }

    override func tearDown() {
        PortraitNameResolver.onDeviceModelEnabled = true
        super.tearDown()
    }

    // MARK: - Laag 1: metadata

    func testMetadataTitelWintVanCameraBestandsnaam() async throws {
        let url = try makeJPEG(named: "IMG_4821.jpg", iptc: [kCGImagePropertyIPTCObjectName: "Jelle Looijen"])
        XCTAssertEqual(ImageNameHints.read(url: url).titles, ["Jelle Looijen"])
        let name = await PortraitNameResolver.resolve(url: url)
        XCTAssertEqual(name, "Jelle Looijen")
    }

    func testCaptionIsAlleenContextNietDeNaam() async throws {
        // Zonder model mag een caption géén naam worden ("Businessman" is geen persoon).
        let url = try makeJPEG(named: "IMG_0001.jpg", iptc: [
            kCGImagePropertyIPTCCaptionAbstract: "Businessman smiling at camera",
            kCGImagePropertyIPTCKeywords: ["office", "portrait"],
        ])
        let hints = ImageNameHints.read(url: url)
        XCTAssertEqual(hints.titles, [])
        XCTAssertEqual(hints.descriptions, ["Businessman smiling at camera", "office", "portrait"])
        let name = await PortraitNameResolver.resolve(url: url)
        XCTAssertEqual(name, "")
    }

    func testDataDropZonderMetadataBlijftLeeg() async throws {
        let url = try makeJPEG(named: "plain.jpg", iptc: [:])
        let name = await PortraitNameResolver.resolve(data: try Data(contentsOf: url))
        XCTAssertEqual(name, "")
    }

    func testDataDropMetTitelKrijgtNaam() async throws {
        let url = try makeJPEG(named: "plain.jpg", iptc: [kCGImagePropertyIPTCObjectName: "Anna de Winter"])
        let name = await PortraitNameResolver.resolve(data: try Data(contentsOf: url))
        XCTAssertEqual(name, "Anna de Winter")
    }

    // MARK: - Laag 3: heuristiek-fallback

    func testZonderMetadataValtTerugOpHeuristiek() async throws {
        let url = try makeJPEG(named: "jelle-looijen.74ZFkSVk_Z1GiMhz.jpg", iptc: [:])
        let name = await PortraitNameResolver.resolve(url: url)
        XCTAssertEqual(name, "Jelle Looijen")
    }

    // MARK: - Validatie van model-antwoorden

    func testValidatieAccepteertNaamUitDeInput() {
        XCTAssertEqual(
            PortraitNameResolver.validated("Jelle Looijen", against: ["jelle-looijen.74ZFkSVk_Z1GiMhz.webp"]),
            "Jelle Looijen"
        )
        XCTAssertEqual(
            PortraitNameResolver.validated("Anne-Marie O'Neill", against: ["anne_marie-oneill.png"]),
            "Anne-Marie O'Neill", "koppelteken/apostrof-ongevoelig"
        )
        XCTAssertEqual(
            PortraitNameResolver.validated("Zoë Müller", against: ["zoe-muller.jpg"]),
            "Zoë Müller", "accent-ongevoelig"
        )
    }

    func testValidatieGeloofdLeegAntwoord() {
        XCTAssertEqual(PortraitNameResolver.validated("  ", against: ["p1-man-beard.png"]), "")
    }

    func testValidatieWeigertVerzonnenOfOnhoudbareNaam() {
        XCTAssertNil(PortraitNameResolver.validated("Jelle Jansen", against: ["jelle-looijen.webp"]), "verzonnen achternaam")
        XCTAssertNil(PortraitNameResolver.validated("A B C D E F", against: ["a b c d e f.png"]), "te veel delen")
        XCTAssertNil(PortraitNameResolver.validated(String(repeating: "a", count: 61), against: [String(repeating: "a", count: 61)]))
    }

    // MARK: - Helpers

    private func makeJPEG(named fileName: String, iptc: [CFString: Any]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortraitNameResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [:]
        if !iptc.isEmpty { props[kCGImagePropertyIPTCDictionary] = iptc }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }
}
