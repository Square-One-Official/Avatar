// Runtime-check van DSFloatingWindow met échte NSWindows: het menu leeft in een
// child window dat over de rand van het hostvenster mag steken, en de
// z-volgorde tussen toast en menu is "laatst verschenen bovenop".
//
// Env-gated (DS_FLOATING_WINDOW_TESTS=1): maakt vensters aan en heeft een
// window server nodig — niet geschikt voor headless CI (zelfde patroon als
// de Enhance-tile snapshot-dump).
//
//   DS_FLOATING_WINDOW_TESTS=1 swift test --package-path AvatarUI --filter DSFloatingWindowRuntimeTests

import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

@MainActor
final class DSFloatingWindowRuntimeTests: XCTestCase {
    private var window: NSWindow!

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DS_FLOATING_WINDOW_TESTS"] == "1",
            "zet DS_FLOATING_WINDOW_TESTS=1 om de venster-tests te draaien"
        )
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
    }

    private final class Stage: ObservableObject {
        @Published var toast: String?
        @Published var menuAnchor: CGRect?
        @Published var panelAnchor: CGRect?
    }

    private struct Harness: View {
        @ObservedObject var stage: Stage
        var body: some View {
            Color.gray
                .overlay(alignment: .bottomTrailing) {
                    if let toast = stage.toast {
                        DSFloatingWindowAnchor(
                            placement: .corner(.bottomTrailing, padding: DSSpacing.gap5),
                            mode: .toast,
                            identity: toast
                        ) {
                            DSToast(title: toast)
                        }
                    }
                }
                .overlay {
                    if let anchor = stage.menuAnchor {
                        DSContextMenuOverlay(anchor: anchor, onDismiss: { stage.menuAnchor = nil }) {
                            DSContextMenuPanel {
                                ForEach(0..<8, id: \.self) { i in
                                    DSMenuRow("Row \(i)", icon: "circle") {}
                                }
                                // E57.1: submenu als laatste rij (keyboard: ↑ → …).
                                DSMenuSubmenu("More", icon: "ellipsis") {
                                    DSMenuRow("Sub A", icon: "circle") {}
                                    DSMenuRow("Sub B", icon: "circle") {}
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if let anchor = stage.panelAnchor {
                        DSContextMenuOverlay(
                            anchor: anchor, bounds: .window, kind: .panel,
                            onDismiss: { stage.panelAnchor = nil }
                        ) {
                            DSTextField(label: nil, placeholder: "RRGGBB", text: .constant(""))
                                .frame(width: 200)
                                .padding()
                                .dsPanelSurface()
                        }
                    }
                }
        }
    }

    private func pump(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private var panels: [DSFloatingPanel] {
        (window.childWindows ?? []).compactMap { $0 as? DSFloatingPanel }
    }

    /// Z-volgorde volgens de window server (front → back); kleinste index =
    /// bovenop. `NSApp.orderedWindows` laat panels weg, vandaar CGWindowList.
    private func zIndex(of panel: NSWindow) -> Int? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.firstIndex { ($0[kCGWindowNumber as String] as? Int) == panel.windowNumber }
    }

    /// Toets in de event-queue: de lokale monitors (menu-navigatie, Esc)
    /// zien 'm bij de volgende pump, net als een echte toetsaanslag.
    private func press(keyCode: UInt16) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        )!
        NSApp.sendEvent(event)
        pump()
    }

    /// E57.1: een submenu is een child window van het menu-panel, rechts
    /// ervan, en gaat open/dicht via →/← en helemaal weg via Esc.
    func testSubmenuOpensBesideMenuViaKeyboardAndClosesWithIt() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        stage.menuAnchor = CGRect(x: 100, y: 60, width: 0, height: 0)
        pump()
        guard let menu = panels.first else { return XCTFail("geen menu-panel") }
        XCTAssertTrue((menu.childWindows ?? []).isEmpty, "submenu dicht bij openen")

        press(keyCode: 126) // ↑ → onderste rij = "More"
        press(keyCode: 124) // → opent het submenu
        let submenus = (menu.childWindows ?? []).compactMap { $0 as? DSFloatingPanel }
        XCTAssertEqual(submenus.count, 1, "submenu hangt als child window onder het menu")
        guard let submenu = submenus.first else { return }
        XCTAssertTrue(submenu.isVisible)
        XCTAssertTrue(submenu.parent === menu)
        XCTAssertGreaterThan(submenu.frame.midX, menu.frame.midX, "rechts van het menu")
        XCTAssertTrue(
            DSFloatingPanelController.isInside(submenu, panelOrDescendantOf: menu),
            "klik in het submenu telt als binnen het menu"
        )

        press(keyCode: 123) // ← sluit het submenu
        XCTAssertTrue((menu.childWindows ?? []).isEmpty, "← sluit alleen het submenu")
        XCTAssertNotNil(stage.menuAnchor, "…het menu zelf blijft open")

        press(keyCode: 124) // → opnieuw open (trigger bleef gemarkeerd)
        XCTAssertEqual((menu.childWindows ?? []).count, 1)
        press(keyCode: 53) // Esc sluit alles
        XCTAssertNil(stage.menuAnchor, "Esc sluit het hele menu")
        XCTAssertTrue(panels.isEmpty)
    }

    func testMenuNearBottomEdgeExtendsBeyondHostWindow() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        // Rechtsklik 30pt boven de onderrand van het venster (SwiftUI .global,
        // y omlaag): een menu van 8 rijen past daar nooit onder.
        stage.menuAnchor = CGRect(x: 300, y: 370, width: 0, height: 0)
        pump()

        XCTAssertEqual(panels.count, 1, "het menu leeft in precies één child window")
        guard let menu = panels.first else { return }
        XCTAssertTrue(menu.isVisible)
        let menuFrame = menu.frame
        XCTAssertLessThan(menuFrame.minY, window.frame.minY, "menu mag onder de vensterrand uitsteken")
        XCTAssertGreaterThanOrEqual(menuFrame.minY, (window.screen ?? NSScreen.main!).visibleFrame.minY, "…maar blijft op het scherm")

        stage.menuAnchor = nil
        pump()
        XCTAssertTrue(panels.isEmpty, "sluiten haalt het child window weg")
    }

    /// De selectie-achtergrondkiezer (`.panel`) moet een venster-/appwissel
    /// overleven en toetsen kunnen ontvangen; een contextmenu (`.menu`) blijft
    /// transient en nooit key.
    func testPanelSurvivesAppDeactivationWhereMenuDoesNot() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()

        stage.menuAnchor = CGRect(x: 100, y: 100, width: 0, height: 0)
        stage.panelAnchor = CGRect(x: 300, y: 100, width: 0, height: 0)
        pump()
        XCTAssertEqual(panels.count, 2)
        guard let menuPanel = panels.first(where: { !$0.allowsKeyboardFocus }),
              let floatingPanel = panels.first(where: { $0.allowsKeyboardFocus }) else {
            return XCTFail("verwacht een menu- én een paneel-child window: \(panels.map(\.allowsKeyboardFocus))")
        }
        XCTAssertFalse(menuPanel.canBecomeKey, "menu wordt nooit key")
        XCTAssertTrue(floatingPanel.canBecomeKey, "paneel kan key worden (tekstvelden)")
        XCTAssertFalse(floatingPanel.becomesKeyOnlyIfNeeded)

        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        pump()
        XCTAssertNil(stage.menuAnchor, "menu sluit bij app-deactivatie")
        XCTAssertNotNil(stage.panelAnchor, "paneel blijft staan bij app-deactivatie")
        XCTAssertEqual(panels.count, 1)

        // Verplaatsen van het hostvenster sluit ook het paneel (anker is stale).
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + 40, y: window.frame.origin.y))
        pump()
        XCTAssertNil(stage.panelAnchor, "paneel sluit bij verplaatsen van het hostvenster")
        XCTAssertTrue(panels.isEmpty)
    }

    func testLastShownIsOnTop() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()

        // 1. Toast eerst, dan menu → menu bovenop.
        stage.toast = "Framing already matches"
        pump(0.5)
        stage.menuAnchor = CGRect(x: 300, y: 100, width: 0, height: 0)
        pump()
        XCTAssertEqual(panels.count, 2)
        guard let toastPanel = panels.first(where: { $0.isToast }),
              let menuPanel = panels.first(where: { !$0.isToast }),
              let toastZ = zIndex(of: toastPanel), let menuZ = zIndex(of: menuPanel) else {
            return XCTFail("verwacht een toast- en een menu-panel in de window-list: \(panels.map { ($0.isToast, $0.frame, $0.isVisible) })")
        }
        XCTAssertLessThan(menuZ, toastZ, "menu dat ná de toast opende staat bovenop")

        // 2. Nieuwe toast terwijl het menu open is → toast bovenop.
        stage.toast = "Matched framing on 3 portraits"
        pump(0.5)
        guard let toastZ2 = zIndex(of: toastPanel), let menuZ2 = zIndex(of: menuPanel) else {
            return XCTFail("panels verdwenen uit orderedWindows")
        }
        XCTAssertLessThan(toastZ2, menuZ2, "toast die ná het menu verschijnt staat bovenop")

        // 3. Menu opnieuw openen → weer bovenop de toast.
        stage.menuAnchor = nil
        pump()
        stage.menuAnchor = CGRect(x: 320, y: 120, width: 0, height: 0)
        pump()
        guard let menuPanel2 = panels.first(where: { !$0.isToast }),
              let toastZ3 = zIndex(of: toastPanel), let menuZ3 = zIndex(of: menuPanel2) else {
            return XCTFail("verwacht een nieuw menu-panel")
        }
        XCTAssertLessThan(menuZ3, toastZ3, "heropend menu staat weer bovenop")

        stage.menuAnchor = nil
        stage.toast = nil
        pump(0.5)
        XCTAssertTrue(panels.isEmpty)
    }
}
