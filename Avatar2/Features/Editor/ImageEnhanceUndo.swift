// Undo/redo voor lokale beeld-vervangende edits (E12.1: one-click retouch,
// improve lighting). Net als TransformUndo (E06.2) registreren we een
// before→after-paar op de native NSUndoManager, zodat Cmd+Z / het Edit-menu
// gratis meewerken. I.t.t. de transform-undo vervangt dit het hele beeld op
// het canvas (via `apply`, doorgaans ShellModel.applyEffectResult), dus
// before/after zijn NSImages.

import AppKit
import Foundation

enum ImageEnhanceUndo {
    /// Registreert een undo die `before` terugzet en een redo naar `after`.
    /// `apply` is de canvas+cutout-vervanger; `target` houdt de registratie
    /// levend (het portret-model). `before`/`after` zijn de hele beelden. Géén
    /// no-op-guard: NSImage is niet Equatable, dus gelijkheid is hier niet
    /// gedefinieerd (de aanroeper bepaalt of er iets te undo'en valt).
    /// E18.4: async apply — wacht op her-isolatie vóór de toast weg mag.
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        target: AnyObject,
        apply: @escaping (NSImage) async -> Void,
        undoTo before: NSImage,
        redoTo after: NSImage,
        actionName: String
    ) {
        ReversibleChange.register(
            undoManager, target: target, from: before, to: after, actionName: actionName
        ) { _, image in
            Task { await apply(image) }
        }
    }

    /// Sync apply (flip/boost — geen her-isolatie).
    @MainActor
    static func register(
        _ undoManager: UndoManager?,
        target: AnyObject,
        apply: @escaping (NSImage) -> Void,
        undoTo before: NSImage,
        redoTo after: NSImage,
        actionName: String
    ) {
        ReversibleChange.register(
            undoManager, target: target, from: before, to: after, actionName: actionName
        ) { _, image in
            apply(image)
        }
    }
}
