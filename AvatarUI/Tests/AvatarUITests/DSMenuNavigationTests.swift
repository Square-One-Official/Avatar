// Keyboard-/hover-model van de DS-contextmenu's (E57.1): volgorde op frame,
// wrap + disabled overslaan, submenu open/dicht via →/←, en de tree kiest
// het diepste open niveau.

import AppKit
import XCTest
@testable import AvatarUI

@MainActor
final class DSMenuNavigationTests: XCTestCase {
    private func makeLevel(
        parent: DSMenuLevel? = nil,
        rows: [(UUID, CGFloat, Bool, Bool)]
    ) -> DSMenuLevel {
        let level = DSMenuLevel(parent: parent)
        for (id, y, isSubmenu, disabled) in rows {
            level.register(id, isSubmenu: isSubmenu, isDisabled: disabled) {}
            level.updateFrame(id, CGRect(x: 8, y: y, width: 200, height: 32))
        }
        return level
    }

    func testOrderFollowsFramesNotRegistration() {
        let top = UUID(), middle = UUID(), bottom = UUID()
        // Andersom registreren: de frames bepalen de volgorde.
        let level = makeLevel(rows: [(bottom, 80, false, false), (top, 8, false, false), (middle, 44, false, false)])
        XCTAssertEqual(level.order, [top, middle, bottom])
    }

    func testDownWrapsAndSkipsDisabled() {
        let a = UUID(), b = UUID(), c = UUID()
        let level = makeLevel(rows: [(a, 8, false, false), (b, 44, false, true), (c, 80, false, false)])
        level.moveFocus(by: 1)
        XCTAssertEqual(level.focusedID, a, "zonder markering start ↓ bovenaan")
        level.moveFocus(by: 1)
        XCTAssertEqual(level.focusedID, c, "disabled rij overgeslagen")
        level.moveFocus(by: 1)
        XCTAssertEqual(level.focusedID, a, "wrap naar boven")
        level.moveFocus(by: -1)
        XCTAssertEqual(level.focusedID, c, "wrap naar onder")
    }

    func testUpWithoutFocusStartsAtBottom() {
        let a = UUID(), b = UUID()
        let level = makeLevel(rows: [(a, 8, false, false), (b, 44, false, false)])
        level.moveFocus(by: -1)
        XCTAssertEqual(level.focusedID, b)
    }

    func testActivateRunsTheRowAction() {
        let level = DSMenuLevel()
        let id = UUID()
        var fired = 0
        level.register(id, isSubmenu: false, isDisabled: false) { fired += 1 }
        level.updateFrame(id, CGRect(x: 0, y: 0, width: 100, height: 32))
        level.moveFocus(by: 1)
        XCTAssertTrue(level.activateFocused())
        XCTAssertEqual(fired, 1)
    }

    func testActivateOnSubmenuRowOpensItWithChildFocus() {
        let sub = UUID()
        let level = makeLevel(rows: [(sub, 8, true, false)])
        level.moveFocus(by: 1)
        XCTAssertTrue(level.activateFocused())
        XCTAssertEqual(level.openSubmenuID, sub)
        XCTAssertTrue(level.pendingChildFocus, "keyboard-open → kind focust z'n eerste rij")
    }

    func testHoverExitKeepsOpenSubmenuRowMarked() {
        let sub = UUID(), other = UUID()
        let level = makeLevel(rows: [(sub, 8, true, false), (other, 44, false, false)])
        level.hoverEntered(sub)
        level.openSubmenu(sub, focusChild: false)
        level.hoverExited(sub)
        XCTAssertEqual(level.focusedID, sub, "open submenu-rij blijft gemarkeerd")
        level.hoverEntered(other)
        level.hoverExited(other)
        XCTAssertNil(level.focusedID, "gewone rij laat los bij hover-exit")
    }

    func testDisabledRowIgnoresHover() {
        let id = UUID()
        let level = makeLevel(rows: [(id, 8, false, true)])
        level.hoverEntered(id)
        XCTAssertNil(level.focusedID)
    }

    func testTreeRightOpensSubmenuAndLeftClosesIt() {
        let tree = DSMenuTree()
        let sub = UUID()
        let root = makeLevel(rows: [(sub, 8, true, false)])
        tree.attach(root)
        XCTAssertTrue(tree.handle(.down))
        XCTAssertTrue(tree.handle(.right))
        XCTAssertEqual(root.openSubmenuID, sub)

        let child = makeLevel(parent: root, rows: [(UUID(), 8, false, false)])
        tree.attach(child)
        XCTAssertTrue(tree.active === child, "diepste open niveau is actief")

        XCTAssertTrue(tree.handle(.left))
        XCTAssertNil(root.openSubmenuID)
        XCTAssertTrue(tree.active === root, "zonder open submenu valt de tree terug op de root")
        XCTAssertEqual(root.focusedID, sub, "de trigger-rij blijft gemarkeerd na ←")
    }

    func testTreeIgnoresDetachedSiblingLevels() {
        // Sibling-submenu opent vóór het vorige is afgemeld: alleen het kind
        // van de rij die nú open staat telt.
        let tree = DSMenuTree()
        let a = UUID(), b = UUID()
        let root = makeLevel(rows: [(a, 8, true, false), (b, 44, true, false)])
        tree.attach(root)
        root.openSubmenu(a, focusChild: false)
        let childA = makeLevel(parent: root, rows: [(UUID(), 8, false, false)])
        tree.attach(childA)
        root.openSubmenu(b, focusChild: false)
        let childB = makeLevel(parent: root, rows: [(UUID(), 8, false, false)])
        tree.attach(childB)
        // Beide kinderen hangen aan root; de eerste match wint — na detach
        // van A is het ondubbelzinnig.
        tree.detach(childA)
        XCTAssertTrue(tree.active === childB)
    }

    func testTreeWithoutLevelsPassesKeysThrough() {
        let tree = DSMenuTree()
        XCTAssertFalse(tree.handle(.down))
    }

    func testKeyMappingIgnoresCommandShortcuts() {
        func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: keyCode
            )!
        }
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 125)), .down)
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 126)), .up)
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 123)), .left)
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 124)), .right)
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 36)), .activate)
        XCTAssertEqual(DSMenuTree.key(for: event(keyCode: 49)), .activate)
        XCTAssertNil(DSMenuTree.key(for: event(keyCode: 53)), "Esc is van de floating-panel-monitor")
        XCTAssertNil(DSMenuTree.key(for: event(keyCode: 125, modifiers: .command)), "⌘↓ is een app-shortcut")
    }
}
