// Smoke-tests voor E03.3: body-evaluatie van toolbar, paneel en container
// (geen snapshot-infra; rendert naar een afbeelding zodat de hele view-tree
// daadwerkelijk wordt opgebouwd).

import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

final class DSEditPanelTests: XCTestCase {

    private enum Tool: String, CaseIterable {
        case edit, effects, clothing, hair, background, images
    }

    private var items: [DSToolbarItem<Tool>] {
        Tool.allCases.map {
            DSToolbarItem(id: $0, icon: Image(systemName: "circle"), label: $0.rawValue)
        }
    }

    @MainActor
    func testBottomToolbarRendert() {
        let view = DSBottomToolbar(items: items, selection: .constant(.effects))
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testEditPanelRendert() {
        let view = DSEditPanel(title: "Effects") { Text("inhoud") }
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testContainerRendertMetEnZonderActiefPaneel() {
        for tool in [Tool?.none, .effects] {
            let view = DSEditPanelContainer(
                tools: items,
                activeTool: .constant(tool),
                photo: { Color.gray.frame(width: 200, height: 200) },
                panel: { _ in DSEditPanel(title: "Effects") { Text("inhoud") } }
            )
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}

// E03.11 — glass-toolknop
extension DSEditPanelTests {

    @MainActor
    func testToolButtonRendertActiefEnInactief() {
        for active in [true, false] {
            let view = DSToolButton(
                Image(systemName: "sparkles"), label: "Effects", isActive: active
            ) {}
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}

// E03.12 — canvas-kaart + dot-grid
extension DSEditPanelTests {

    @MainActor
    func testCanvasCardRendertMetEnZonderDotGrid() {
        for dots in [true, false] {
            let view = DSCanvasCard(showsDotGrid: dots) {
                Color.clear
            }
            .frame(width: 465, height: 456)
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }
}

// E03.16 — layoutgarantie (bevinding 19): op de minimummaat 800×600 met
// geopend paneel zijn toolbar en paneel nooit afgekapt; de foto (rood) is
// het enige flexibele element. Pixel-probe op de render.
extension DSEditPanelTests {

    private func pixel(_ cg: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(
            data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // doel-pixel (top-based y) naar (0,0) schuiven; CG tekent bottom-up
        ctx.draw(cg, in: CGRect(
            x: -CGFloat(x), y: -CGFloat(cg.height - 1 - y),
            width: CGFloat(cg.width), height: CGFloat(cg.height)
        ))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    @MainActor
    func testToolbarEnPaneelNooitAfgekaptOpMinimummaat() {
        let foto = Color(red: 1, green: 0, blue: 0)
        let paneelInhoud = Color(red: 0, green: 0, blue: 1)
        let view = DSEditPanelContainer(
            tools: [DSToolbarItem(id: "a", icon: Image(systemName: "sparkles"), label: "A")],
            activeTool: .constant("a")
        ) {
            foto
        } panel: { _ in
            DSEditPanel(title: "Panel") { paneelInhoud.frame(height: 200) }
        }
        .frame(width: 800, height: 600)

        guard let cg = ImageRenderer(content: view).cgImage else {
            return XCTFail("render mislukt")
        }
        XCTAssertEqual(cg.width, 800)
        XCTAssertEqual(cg.height, 600)

        // Zelfcheck: bovenin domineert de foto (rood).
        let top = pixel(cg, x: 400, y: 40)
        XCTAssertGreaterThan(top.r, 180, "foto hoort bovenin te staan: \(top)")

        // Toolbar-zone (onderste 64pt, gemeten náást de glass-cirkel —
        // de materiaallagen geven in ImageRenderer artefactkleuren):
        // nooit foto- of paneelpixels.
        for y in [600 - 12, 600 - 32, 600 - 56] {
            for x in [100, 700] {
                let p = pixel(cg, x: x, y: y)
                XCTAssertFalse(p.r > 180 && p.g < 80, "foto lekt in toolbar-zone op (\(x),\(y)): \(p)")
                XCTAssertFalse(p.b > 180 && p.r < 80, "paneel lekt in toolbar-zone op (\(x),\(y)): \(p)")
            }
        }

        // Paneel-zone: E18.22 — het paneel OVERLAPT nu de onderkant van de
        // foto (glas) i.p.v. een eigen rij. Bovenin is de foto helder rood;
        // in de onderste foto-band dempt de glas-kaart dat rood merkbaar. Eis
        // dus dat de onderband donkerder is dan de bovenband → paneel ligt
        // erover. (ImageRenderer rastert blur/scroll-inhoud niet, maar de
        // Background.card.opacity-laag dempt het rood wél.)
        // E23: de DSColor-tokens zijn nu theme-bewust; in de headless
        // ImageRenderer (geen window-appearance) resolven ze naar de light-
        // variant. De invariant blijft echter theme-onafhankelijk: het paneel
        // ligt over de onderkant en DEMPT het pure rood — donker in dark
        // (r<150) óf licht in light (de witte card@82% tilt g van ~0 naar hoog).
        // Nooit nog puur rood = paneel ligt erover.
        let onderband = stride(from: 600 - 64 - 16, through: 600 - 64 - 120, by: -8).map {
            pixel(cg, x: 400, y: $0)
        }
        XCTAssertTrue(
            onderband.contains { $0.r < 150 || $0.g > 120 },
            "glas-paneel hoort de onderkant van de foto te dempen: \(onderband.map(\.r))"
        )
    }
}
