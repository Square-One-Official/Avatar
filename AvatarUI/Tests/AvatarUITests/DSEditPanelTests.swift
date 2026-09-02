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
    func testCapsuleToolButtonIconOnlyRendertZonderLegeNaam() {
        let view = DSCapsuleToolButton(
            isActive: true,
            size: .compact,
            action: {}
        ) {
            Image(systemName: "square.grid.2x2")
        }
        .accessibilityLabel("Grid")
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testEditPanelRendert() {
        let view = DSEditPanel(title: "Effects") { Text("inhoud") }
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    // E55.4 — header-accessoireslot: de nieuwe primary init rendert mét
    // accessoire; de EmptyView-convenience (hierboven) dekt de back-compat.
    @MainActor
    func testEditPanelRendertMetHeaderAccessory() {
        let view = DSEditPanel(
            title: "Effects",
            credits: "⚡4",
            headerAccessory: {
                DSGhostButton("Create", icon: Image(systemName: "plus"), size: .small) {}
            }
        ) { Text("inhoud") }
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

    /// Cirkel-clip moet ook de CONTENT knippen: een punt in de vierkante hoek
    /// (binnen xl4-rounded-rect, buiten de ingeschreven cirkel) mag niet wit zijn.
    @MainActor
    func testCanvasCardCircleClipHeeftGeenVierkanteHoeken() {
        let view = DSCanvasCard(
            showsDotGrid: false,
            backgroundColor: .white,
            surfaceClip: AnyShape(Circle())
        ) {
            Color.white
        }
        .frame(width: 100, height: 100)
        .background(Color.black)

        guard let cg = ImageRenderer(content: view).cgImage else {
            return XCTFail("render mislukt")
        }
        let center = pixel(cg, x: 50, y: 50)
        XCTAssertGreaterThan(center.r, 180, "centrum hoort wit te zijn: \(center)")
        for (x, y) in [(12, 12), (87, 12), (12, 87), (87, 87)] {
            let p = pixel(cg, x: x, y: y)
            XCTAssertLessThan(p.r, 40, "hoek (\(x),\(y)) hoort buiten de cirkel te vallen: \(p)")
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

        // Besluit Thierry (2026-06-24): het canvas loopt door tot de onderrand en
        // de toolbar ZWEEFT eroverheen — geen eigen rij, dus geen lege band onder
        // de toolbar. Twee invarianten:
        //  (1) Onder de gezwevende capsule (midden) dekt de toolbar de foto af →
        //      géén puur rood. De capsule is Background.card (licht/donker per
        //      thema), nooit (r>180, g<80).
        for y in [600 - 24, 600 - 40] {
            let p = pixel(cg, x: 400, y: y)
            XCTAssertFalse(p.r > 180 && p.g < 80, "toolbar dekt de foto niet af op (400,\(y)): \(p)")
        }
        //  (2) Het canvas loopt door tot de rand: aan de zijkanten (buiten de
        //      smalle capsule) en in de gap onder de capsule blijft de foto (rood)
        //      zichtbaar — bewijs dat er géén band de canvas afkapt.
        for (x, y) in [(60, 600 - 24), (740, 600 - 24), (400, 600 - 4)] {
            let p = pixel(cg, x: x, y: y)
            XCTAssertTrue(p.r > 180 && p.g < 80, "canvas hoort door te lopen tot de rand op (\(x),\(y)): \(p)")
        }

        // Paneel-zone: E18.22 — het paneel OVERLAPT nu de onderkant van de
        // foto i.p.v. een eigen rij. Bovenin is de foto helder rood; in de
        // onderste foto-band dempt de solid-card-kleur dat rood merkbaar. Eis
        // dus dat de onderband donkerder is dan de bovenband → paneel ligt
        // erover. E23: DSColor-tokens zijn theme-bewust; in de headless
        // ImageRenderer resolven ze naar de light-variant. Invariant:
        // donker in dark (r<150) óf licht in light (g>120). Nooit puur rood.
        let onderband = stride(from: 600 - 64 - 16, through: 600 - 64 - 120, by: -8).map {
            pixel(cg, x: 400, y: $0)
        }
        XCTAssertTrue(
            onderband.contains { $0.r < 150 || $0.g > 120 },
            "solid-paneel hoort de onderkant van de foto te dempen: \(onderband.map(\.r))"
        )
    }

    /// `dsPanelSurface` mag child-overlays niet clippen: Enhance-dropdowns
    /// zijn breder dan hun tegel en moeten over de kaart-rand vallen.
    @MainActor
    func testPanelSurfaceLaatOverflowingOverlayOngeclipt() {
        let card: CGFloat = 80
        let canvas: CGFloat = 200
        let overflow: CGFloat = 24
        let view = ZStack {
            Color.red
            Color.clear
                .frame(width: card, height: card)
                .overlay(alignment: .topLeading) {
                    Color.blue
                        .frame(width: overflow, height: overflow)
                        .offset(x: -overflow)
                }
                .dsPanelSurface(cornerRadius: 8, solid: true)
        }
        .frame(width: canvas, height: canvas)

        guard let cg = ImageRenderer(content: view).cgImage else {
            return XCTFail("render mislukt")
        }

        // Kaart gecentreerd: linker rand op (200-80)/2 = 60. Overlay steekt
        // 24pt uit → blauw van x=36 tot x=60, y=60 tot y=84.
        let p = pixel(cg, x: 48, y: 72)
        XCTAssertGreaterThan(p.b, 180, "dropdown-overlay hoort over de kaart-rand te vallen, niet geclipt: \(p)")
        XCTAssertLessThan(p.r, 80, "geclipt overlay zou het rode canvas tonen: \(p)")
    }
}
