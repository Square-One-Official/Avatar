// Gedeelde undo/redo-motor (audit-cleanup). Alle before→after-undo's in v2
// (transform, adjust, beeld-vervanging, cutout-bytes, board-positie) deelden
// hetzelfde recursieve `registerUndo(withTarget:)`-patroon: undo zet `before`
// terug en registreert meteen de inverse zodat redo werkt. Dat patroon staat
// nu één keer hier; de domein-specifieke facades (TransformUndo, AdjustUndo,
// ImageEnhanceUndo, CutoutDataUndo, BoardMoveUndo) blijven bestaan als
// intentie-onthullende ingangen en delegeren hiernaartoe.

import Foundation

enum ReversibleChange {
    /// Registreer een omkeerbare wijziging op de native `NSUndoManager`. `apply`
    /// past één waarde toe (op `target`, dat de registratie levend houdt); undo
    /// zet `before` terug en registreert de inverse zodat de redo-keten klopt.
    /// De no-op-guard (niets veranderd) hoort bij de aanroeper, omdat niet elk
    /// waarde-type Equatable is (bv. NSImage bij beeld-vervanging).
    @MainActor
    static func register<Target: AnyObject, Value>(
        _ undoManager: UndoManager?,
        target: Target,
        from before: Value,
        to after: Value,
        actionName: String,
        apply: @escaping (Target, Value) -> Void
    ) {
        guard let undoManager else { return }
        // `withTarget` levert het target terug aan de handler (manager houdt 'm
        // zwak vast) → geen sterke capture van het portret in de undo-stack.
        undoManager.registerUndo(withTarget: target) { tgt in
            apply(tgt, before)
            register(undoManager, target: tgt, from: after, to: before, actionName: actionName, apply: apply)
        }
        undoManager.setActionName(actionName)
    }
}
