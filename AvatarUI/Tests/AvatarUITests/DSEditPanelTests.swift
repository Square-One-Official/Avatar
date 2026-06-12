// Smoke-tests voor E03.3: body-evaluatie van toolbar, paneel en container
// (geen snapshot-infra; rendert naar een afbeelding zodat de hele view-tree
// daadwerkelijk wordt opgebouwd).

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
