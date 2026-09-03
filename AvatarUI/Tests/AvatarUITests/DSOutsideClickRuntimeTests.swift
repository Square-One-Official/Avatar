// Runtime-check van DSOutsideClick met een échte NSWindow: een open
// `dsDropdownMenu` sluit bij een muisklik waar dan ook in het venster buiten
// anker + menu, blijft open bij een klik op het menu of het anker, en sluit
// op Esc.
//
// Env-gated (DS_FLOATING_WINDOW_TESTS=1): heeft een window server nodig,
// zelfde patroon als DSFloatingWindowRuntimeTests.
//
//   DS_FLOATING_WINDOW_TESTS=1 swift test --package-path AvatarUI --filter DSOutsideClickRuntimeTests

import AppKit
import SwiftUI
import XCTest
@testable import AvatarUI

@MainActor
final class DSOutsideClickRuntimeTests: XCTestCase {
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
        @Published var open = false
    }

    private struct Harness: View {
        @ObservedObject var stage: Stage
        var body: some View {
            Color.gray
                .overlay(alignment: .topLeading) {
                    DSDropdownButton(isPresented: $stage.open, anchorHeight: 32, minWidth: 160) {
                        Text("Anchor").frame(width: 120, height: 32)
                    } menu: {
                        ForEach(0..<4, id: \.self) { i in
                            DSMenuRow("Row \(i)", icon: "circle") {}
                        }
                    }
                    .padding(20)
                }
        }
    }

    private func pump(_ seconds: TimeInterval = 0.3) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Probes van DSOutsideClick (privaat type) — gevonden op klassenaam;
    /// frames in window-coördinaten (AppKit, y omhoog).
    private func probeFrames() -> [CGRect] {
        var out: [CGRect] = []
        func walk(_ v: NSView) {
            if String(describing: type(of: v)).contains("ProbeView") {
                out.append(v.convert(v.bounds, to: nil))
            }
            v.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        return out
    }

    private func click(_ point: CGPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return XCTFail("kon geen muis-event maken") }
            NSApp.sendEvent(event)
        }
        pump()
    }

    private func pressEscape() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false, keyCode: 53
        ) else { return XCTFail("kon geen key-event maken") }
        NSApp.sendEvent(event)
        pump()
    }

    private func openMenu(_ stage: Stage) -> (anchor: CGRect, menu: CGRect)? {
        stage.open = true
        pump()
        let frames = probeFrames().sorted { $0.width * $0.height < $1.width * $1.height }
        guard frames.count == 2 else {
            XCTFail("verwacht 2 probes (anker + menu), kreeg \(frames)")
            return nil
        }
        // Anker zit bovenaan (hoogste y in AppKit-space), menu eronder.
        let anchor = frames.max { $0.minY < $1.minY }!
        let menu = frames.min { $0.minY < $1.minY }!
        return (anchor, menu)
    }

    func testClickOutsideAnchorAndMenuCloses() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        guard let (anchor, menu) = openMenu(stage) else { return }

        let outside = CGPoint(x: 550, y: 40)  // rechtsonder in het venster
        XCTAssertFalse(anchor.contains(outside) || menu.contains(outside))
        click(outside)
        XCTAssertFalse(stage.open, "klik buiten anker+menu sluit het menu")
    }

    func testClickInsideMenuOrAnchorKeepsOpen() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        guard let (anchor, menu) = openMenu(stage) else { return }

        click(CGPoint(x: menu.midX, y: menu.midY))
        XCTAssertTrue(stage.open, "klik op het menu laat het open")

        // Anker: de monitor grijpt niet in (de toggle-knop regelt sluiten
        // zelf op mouseUp) — hier alleen de monitor testen, via mouseDown.
        guard let down = NSEvent.mouseEvent(
            with: .leftMouseDown, location: CGPoint(x: anchor.midX, y: anchor.midY),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) else { return XCTFail("kon geen muis-event maken") }
        NSApp.sendEvent(down)
        pump()
        XCTAssertTrue(stage.open, "mouseDown op het anker sluit het menu niet via de monitor")
    }

    func testEscapeCloses() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        guard openMenu(stage) != nil else { return }
        pressEscape()
        XCTAssertFalse(stage.open, "Esc sluit het menu")
    }

    func testMonitorIsRemovedAfterClose() {
        let stage = Stage()
        window.contentView = NSHostingView(rootView: Harness(stage: stage))
        pump()
        guard openMenu(stage) != nil else { return }
        stage.open = false
        pump()
        // Heropenen via state (niet via klik) en dan buiten klikken: nog steeds
        // precies één keer sluiten — geen dubbele/lekkende monitor die het
        // binding-schrijven verstoort.
        stage.open = true
        pump()
        click(CGPoint(x: 550, y: 40))
        XCTAssertFalse(stage.open)
        stage.open = true
        pump()
        XCTAssertTrue(stage.open, "zonder klik blijft een heropend menu open")
    }
}
