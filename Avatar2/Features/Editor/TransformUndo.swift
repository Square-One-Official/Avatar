// Undo/redo voor de canvas-transform (E06.2). Native NSUndoManager
// (environment) zodat Cmd+Z / Shift-Cmd+Z en het Edit-menu gratis
// meewerken. Per afgerond gebaar (drag/zoom uit E06.4, auto-frame uit
// E06.5) registreren we een before→after-paar; de canonieke recursieve
// registratie zorgt dat redo de inverse is.

import Foundation

enum TransformUndo {
    struct Snapshot: Equatable {
        var offsetX: Double
        var offsetY: Double
        var scale: Double
    }

    static func snapshot(of portrait: Portrait2) -> Snapshot {
        Snapshot(offsetX: portrait.offsetX, offsetY: portrait.offsetY, scale: portrait.scale)
    }

    private static func apply(_ s: Snapshot, to portrait: Portrait2) {
        portrait.offsetX = s.offsetX
        portrait.offsetY = s.offsetY
        portrait.scale = s.scale
        portrait.touch()
    }

    /// Registreert een undo die naar `before` terugzet en een redo naar
    /// `after`. Niets te doen als er niets veranderde. Recursieve undo/redo-
    /// motor: de gedeelde `ReversibleChange`.
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        portrait: Portrait2,
        undoTo before: Snapshot,
        redoTo after: Snapshot,
        actionName: String
    ) {
        guard before != after else { return }
        ReversibleChange.register(
            undoManager, target: portrait, from: before, to: after, actionName: actionName
        ) { target, snapshot in
            apply(snapshot, to: target)
        }
    }
}
