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
    /// `after`. Niets te doen als er niets veranderde.
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        portrait: Portrait2,
        undoTo before: Snapshot,
        redoTo after: Snapshot,
        actionName: String
    ) {
        guard let undoManager, before != after else { return }
        undoManager.registerUndo(withTarget: portrait) { target in
            apply(before, to: target)
            // We zitten nu in een undo → deze registratie belandt op de
            // redo-stack en zet straks `after` terug (met before/after
            // omgewisseld zodat de keten heen-en-weer blijft werken).
            register(undoManager, portrait: target, undoTo: after, redoTo: before, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
