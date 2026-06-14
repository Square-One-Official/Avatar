// Undo/redo voor de niet-destructieve Adjust-laag (E24.14). Net als
// TransformUndo (E06.2) en ImageEnhanceUndo (E12.1) registreren we een
// before→after-paar op de native NSUndoManager (Cmd+Z / Edit-menu werken
// gratis mee). I.t.t. ImageEnhanceUndo vervangt dit géén beeld maar de vier
// Adjust-params op het portret; `apply` (doorgaans ShellModel.commitAdjust)
// zet de params en hercomputeert het canvas. cutoutData blijft ongemoeid,
// dus deze stack is orthogonaal aan de beeld-undo.

import Foundation

enum AdjustUndo {
    /// Registreert een undo die `before` terugzet en een redo naar `after`.
    /// `apply` zet de Adjust-laag + hercomputeert het canvas; `target` houdt de
    /// registratie levend (het portret-model). No-op als er niets verandert.
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        target: AnyObject,
        apply: @escaping (PortraitAdjust) -> Void,
        undoTo before: PortraitAdjust,
        redoTo after: PortraitAdjust,
        actionName: String
    ) {
        guard let undoManager, before != after else { return }
        undoManager.registerUndo(withTarget: target) { target in
            apply(before)
            register(undoManager, target: target, apply: apply, undoTo: after, redoTo: before, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
