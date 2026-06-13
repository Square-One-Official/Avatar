// Undo/redo voor cutout-byte-vervangende set-acties (E12.2: Match lighting).
// Net als TransformUndo registreren we een before→after-paar op de native
// NSUndoManager; de recursieve registratie maakt redo de inverse. Gebruikt
// voor set-brede edits die de opgeslagen cutout-PNG van portretten wijzigen
// (niet op het canvas — de sidebar-thumbs verversen via SwiftData).

import Foundation

enum CutoutDataUndo {
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        portrait: Portrait2,
        undoTo before: Data,
        redoTo after: Data,
        actionName: String
    ) {
        guard let undoManager, before != after else { return }
        undoManager.registerUndo(withTarget: portrait) { target in
            target.cutoutData = before
            target.touch()
            register(undoManager, portrait: target, undoTo: after, redoTo: before, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
