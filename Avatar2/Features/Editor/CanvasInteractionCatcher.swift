// Canvas-interactie-catcher (E27.1, plan-stap b) — vangt trackpad/muis-scroll
// (= pan), ⌘-scroll (= zoom rond de cursor) en spatie-drag (= pan) voor de
// camera, ZONDER gewone clicks/drags op het onderwerp te stelen.
//
// Aanpak: een onzichtbare NSView die zelf alle muis-clicks DOORLAAT
// (`hitTest` → nil), plus een lokale NSEvent-monitor die scroll/magnify/
// spatie-drag afvangt. De monitor draait vóór de SwiftUI-dispatch: `nil`
// terug = event geconsumeerd (camera), het event terug = doorgelaten (zodat
// de subject-drag (E24.32) en de deselect-tap ongemoeid blijven). Een
// leftMouseDragged wordt alléén geconsumeerd terwijl de spatiebalk ingedrukt
// is — zonder spatie valt 'ie door naar de SwiftUI-gestures.

import AppKit
import SwiftUI

struct CanvasInteractionCatcher: NSViewRepresentable {
    @Binding var camera: CanvasCamera

    func makeCoordinator() -> Coordinator { Coordinator(camera: $camera) }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.camera = $camera
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// NSView die élke muis-hit doorlaat (clicks bereiken de SwiftUI-views);
    /// `isFlipped` zodat de cursor-y top-down loopt, gelijk aan SwiftUI/offset.
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isFlipped: Bool { true }
    }

    final class Coordinator {
        var camera: Binding<CanvasCamera>
        private weak var view: NSView?
        private var monitor: Any?
        private var spaceDown = false

        // Zoomgevoeligheid van ⌘-scroll (per scroll-eenheid).
        private let zoomPerScrollUnit: CGFloat = 0.01
        private let spaceKeyCode: UInt16 = 49

        init(camera: Binding<CanvasCamera>) { self.camera = camera }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .keyDown, .keyUp, .leftMouseDragged]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// `nil` = consumeren (camera), anders = doorlaten.
        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            case .keyDown where event.keyCode == spaceKeyCode:
                // Spatie = pan-modus aan; doorlaten (geen tekstveld in de editor).
                spaceDown = true
                return event
            case .keyUp where event.keyCode == spaceKeyCode:
                spaceDown = false
                return event
            case .leftMouseDragged:
                // Alléén pannen terwijl de spatie ingedrukt is én de cursor boven
                // de canvas valt; anders doorlaten (subject-drag E24.32).
                guard spaceDown, pointInCanvas(for: event) != nil else { return event }
                var cam = camera.wrappedValue
                cam.offset.width += event.deltaX
                cam.offset.height += event.deltaY
                camera.wrappedValue = cam
                return nil
            case .scrollWheel:
                guard let point = pointInCanvas(for: event) else { return event }
                var cam = camera.wrappedValue
                if event.modifierFlags.contains(.command) {
                    // ⌘-scroll = zoom rond de cursor.
                    let factor = 1 - event.scrollingDeltaY * zoomPerScrollUnit
                    cam.zoom(by: factor, around: point, in: viewBoundsSize())
                } else {
                    // Gewone scroll / two-finger = pan.
                    cam.offset.width += event.scrollingDeltaX
                    cam.offset.height += event.scrollingDeltaY
                }
                camera.wrappedValue = cam
                return nil
            default:
                return event
            }
        }

        /// De cursorlocatie in viewport-punten als het event boven de canvas
        /// valt; anders nil (event wordt dan doorgelaten / niet afgehandeld).
        private func pointInCanvas(for event: NSEvent) -> CGPoint? {
            guard let view, let window = view.window, event.window === window else { return nil }
            let pInView = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(pInView) else { return nil }
            return pInView
        }

        private func viewBoundsSize() -> CGSize {
            view?.bounds.size ?? .zero
        }
    }
}
