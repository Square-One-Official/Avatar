// Rechtermuis-detectie (E24.22) — SwiftUI heeft geen rechtsklik-modifier op
// macOS. Deze overlay-NSView vangt ALLEEN rechtskliks (rightMouseDown) en laat
// links-kliks/hover ongemoeid doorgaan naar de SwiftUI-view eronder (hitTest
// geeft alleen self terug bij een rechtsklik-event). Zo kun je een eigen
// DS-menu tonen i.p.v. het native `.contextMenu`.

import AppKit
import SwiftUI

public extension View {
    /// Roept `perform` aan bij een rechtsklik; links-klik/hover gaan door.
    func onRightClick(perform: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: perform))
    }
}

private struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = CatcherView()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        // Vang alléén rechtskliks; alle andere events (links-klik, hover, scroll)
        // vallen door naar de onderliggende SwiftUI-view.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let type = NSApp.currentEvent?.type,
                  type == .rightMouseDown || type == .rightMouseUp else { return nil }
            return self
        }
    }
}
