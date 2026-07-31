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
    /// True wanneer de cursor boven open chrome (menu/paneel) staat dat zelf moet
    /// scrollen — dan laat de catcher scroll/pinch/spatie-drag dóór i.p.v. de
    /// canvas te bewegen. Default: nooit (bv. de board kent geen overlappende
    /// menu's).
    var chromeHovered: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator(camera: $camera) }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.camera = $camera
        context.coordinator.chromeHovered = chromeHovered
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

    // MARK: - Scroll-delta-schaling (E27.9, audit C2)
    // Een trackpad meldt PUNTEN (`hasPreciseScrollingDeltas == true`); een
    // muiswiel meldt LINE-deltas (~±1 per tik). Apple's docs: vermenigvuldig
    // line-deltas met de regelhoogte. Zonder die schaal was een wiel-tik
    // ~0,75pt pan en ~1% zoom — "het board scrollt niet" met een muis.
    // Statisch + puur zodat Avatar2Tests de schaling kan dekken.

    /// Regelhoogte-benadering voor muiswiel-line-deltas (plan 27.9: ×20–40).
    static let mouseWheelLineHeight: CGFloat = 24
    /// Zoomgevoeligheid van ⌘-scroll (per punt scroll-delta).
    static let zoomPerScrollUnit: CGFloat = 0.01

    /// Scroll-delta → pan-delta in viewport-punten.
    static func scrollPanDelta(_ delta: CGFloat, precise: Bool) -> CGFloat {
        precise ? delta : delta * mouseWheelLineHeight
    }

    /// Scroll-delta → zoomfactor voor ⌘-scroll. Trackpad: ongewijzigd gedrag
    /// (kleine punt-deltas op event-rate). Muiswiel: line-delta × regelhoogte,
    /// geclampt zodat één (door macOS versnelde) wiel-tik de zoom niet in één
    /// klap laat springen.
    static func scrollZoomFactor(deltaY: CGFloat, precise: Bool) -> CGFloat {
        if precise { return 1 - deltaY * zoomPerScrollUnit }
        let factor = 1 - deltaY * mouseWheelLineHeight * zoomPerScrollUnit
        return min(max(factor, 0.75), 1.33)
    }

    final class Coordinator {
        var camera: Binding<CanvasCamera>
        var chromeHovered = false
        private weak var view: NSView?
        private var monitor: Any?
        private var spaceDown = false

        private let spaceKeyCode: UInt16 = 49

        init(camera: Binding<CanvasCamera>) { self.camera = camera }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .magnify, .keyDown, .keyUp, .leftMouseDragged]
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
            // Cursor boven een open menu/paneel → laat scroll/pinch/spatie-drag
            // dóór zodat dat element scrollt i.p.v. de canvas.
            if chromeHovered,
               event.type == .scrollWheel || event.type == .magnify || event.type == .leftMouseDragged {
                return event
            }
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
                // E27.9 (audit C2): muiswiel-line-deltas naar punten schalen;
                // trackpad-deltas (hasPreciseScrollingDeltas) zijn al punten.
                let precise = event.hasPreciseScrollingDeltas
                var cam = camera.wrappedValue
                if event.modifierFlags.contains(.command) {
                    // ⌘-scroll = zoom rond de cursor.
                    let factor = CanvasInteractionCatcher.scrollZoomFactor(
                        deltaY: event.scrollingDeltaY, precise: precise
                    )
                    cam.zoom(by: factor, around: point, in: viewBoundsSize())
                } else {
                    // Gewone scroll / two-finger = pan.
                    cam.offset.width += CanvasInteractionCatcher
                        .scrollPanDelta(event.scrollingDeltaX, precise: precise)
                    cam.offset.height += CanvasInteractionCatcher
                        .scrollPanDelta(event.scrollingDeltaY, precise: precise)
                }
                camera.wrappedValue = cam
                return nil
            case .magnify:
                // Trackpad-pinch = zoom rond de cursor. Op NSEvent-niveau (i.p.v.
                // een SwiftUI MagnifyGesture) → werkt óók als het onderwerp
                // geselecteerd is (de handle-overlay zit er dan bovenop).
                guard let point = pointInCanvas(for: event) else { return event }
                var cam = camera.wrappedValue
                cam.zoom(by: 1 + event.magnification, around: point, in: viewBoundsSize())
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
