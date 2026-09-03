// E03.19: DSBottomToolbar rendert met en zonder trailing accessoire-slot.
// De accessory-init mag bestaande tools-only call sites niet breken (EmptyView-
// extensie) en moet de accessoires in dezelfde strip meenemen.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSBottomToolbarTests: XCTestCase {

    private func items() -> [DSToolbarItem<Int>] {
        (0..<3).map { DSToolbarItem(id: $0, icon: Image(systemName: "circle"), label: "Tool \($0)") }
    }

    @MainActor
    func testRendertZonderAccessoires() {
        let view = DSBottomToolbar(items: items(), selection: .constant(nil))
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testRendertMetTrailingAccessoires() {
        let view = DSBottomToolbar(items: items(), selection: .constant(1)) {
            DSToolButton(Image(systemName: "arrow.uturn.backward"), label: "Undo") {}
            DSToolButton(Image(systemName: "arrow.uturn.forward"), label: "Redo") {}
        }
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testRendertCapsuleMetOverflow() {
        // E31.1: gelabelde pillen + overflow `⋯` + accessoires.
        let view = DSBottomToolbar(
            items: items(),
            selection: .constant(0),
            overflow: [DSToolbarItem(id: 9, icon: Image(systemName: "photo"), label: "Background")]
        ) {
            DSToolButton(Image(systemName: "arrow.uturn.backward"), label: "Undo") {}
        }
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testContainerForwardtAccessoireSlot() {
        let view = DSEditPanelContainer(
            tools: items(),
            activeTool: .constant(nil),
            photo: { Color.clear },
            panel: { _ in EmptyView() },
            toolbarAccessory: {
                DSToolButton(Image(systemName: "rectangle.2.swap"), label: "Compare") {}
            }
        )
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}
