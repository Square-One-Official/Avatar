// E53.8 — de Apple-Intelligence-sheet leeft op een stabiele host.
//
// De presentatiestate zat in de chip zelf (diep in het Enhance-paneel), dus een
// tab-/lens-wissel bouwde die view opnieuw, zette de @State-vlag terug op false
// en gooide de sheet weg — inclusief een generatie die tientallen seconden kon
// lopen. Deze suite borgt het contract van de presenter die dat vervangt.

import AppKit
import Foundation
import XCTest
@testable import Avatar2

@MainActor
final class ImagePlaygroundPresenterTests: XCTestCase {

    override func tearDown() {
        ImagePlaygroundPresenter.shared.dismiss()
        super.tearDown()
    }

    private func writeTempPNG() throws -> URL {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playground-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    func testPresentPublishesStateAndSource() {
        let presenter = ImagePlaygroundPresenter.shared
        let source = NSImage(size: NSSize(width: 8, height: 8))

        presenter.present(sourceImage: source) { _ in }

        XCTAssertTrue(presenter.isPresented)
        XCTAssertNotNil(presenter.sourceImage, "de bron hoort bij de presenter te liggen, niet bij de knop")
    }

    /// De kern van de story: de state hangt níét aan de view die 'm opende.
    /// Dat is wat een tab-wissel overleeft.
    func testStateSurvivesTheCallSiteGoingAway() {
        let presenter = ImagePlaygroundPresenter.shared
        do {
            // Scope die de "chip" voorstelt — die mag verdwijnen.
            let source = NSImage(size: NSSize(width: 8, height: 8))
            presenter.present(sourceImage: source) { _ in }
        }
        XCTAssertTrue(presenter.isPresented)
        XCTAssertNotNil(presenter.sourceImage)
    }

    func testCompleteDeliversDataAndCloses() throws {
        let presenter = ImagePlaygroundPresenter.shared
        let url = try writeTempPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        var received: Data?
        presenter.present(sourceImage: nil) { received = $0 }
        presenter.complete(url: url)

        XCTAssertNotNil(received, "een geslaagde generatie hoort bij de call site te landen")
        XCTAssertFalse(presenter.isPresented)
        XCTAssertNil(presenter.sourceImage)
    }

    /// Onleesbaar resultaat = stil sluiten. De callback met lege data roepen zou
    /// een leeg beeld over het portret zetten.
    func testUnreadableResultClosesWithoutCallingBack() {
        let presenter = ImagePlaygroundPresenter.shared
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).png")

        var called = false
        presenter.present(sourceImage: nil) { _ in called = true }
        presenter.complete(url: missing)

        XCTAssertFalse(called)
        XCTAssertFalse(presenter.isPresented)
    }

    /// Na een Cancel mag een volgende sessie niet de vórige call site terugbellen.
    func testDismissClearsTheCallback() throws {
        let presenter = ImagePlaygroundPresenter.shared
        let url = try writeTempPNG()
        defer { try? FileManager.default.removeItem(at: url) }

        var firstCalled = false
        presenter.present(sourceImage: nil) { _ in firstCalled = true }
        presenter.dismiss()

        presenter.complete(url: url)
        XCTAssertFalse(firstCalled, "de callback van een geannuleerde sessie hoort weg te zijn")
    }
}
