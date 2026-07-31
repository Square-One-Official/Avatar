// macOS-native double-click (E33 naam-chip). SwiftUI's `.onTapGesture(count: 2)`
// vuurt op macOS soms al bij een enkelklik; deze overlay gebruikt AppKit's
// `clickCount` zodat de actie alléén bij een echte dubbelklik loopt.

import AppKit
import SwiftUI

public extension View {
    /// Roept `perform` alléén aan bij een dubbelklik; enkelklikken worden genegeerd.
    func onDoubleClick(perform: @escaping () -> Void) -> some View {
        overlay(DoubleClickCatcher(action: perform))
    }
}

private struct DoubleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    final class CatcherView: NSView {
        var action: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else { return }
            action?()
        }

        // Vang links-kliks voor clickCount; hover/scroll vallen door naar SwiftUI.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            guard let type = NSApp.currentEvent?.type else { return nil }
            switch type {
            case .leftMouseDown, .leftMouseUp:
                return self
            default:
                return nil
            }
        }
    }
}
