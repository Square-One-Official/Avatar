// E49.3: begrens de undo-history van het venster. `levelsOfUndo` stond
// nergens gezet (NSUndoManager-default = onbegrensd), terwijl beeld-edits
// (CutoutDataUndo/ImageEnhanceUndo) volledige PNG-`Data` in hun closures
// vasthouden — een lange sessie stapelde zo multi-MB payloads zonder plafond.
// Twintig stappen dekt ruim een editorsessie en houdt het geheugen begrensd.

import SwiftUI

extension View {
    /// Zet `levelsOfUndo` op de venster-`UndoManager` zodra die beschikbaar is
    /// (en opnieuw als het venster een andere manager krijgt).
    func undoHistoryCap(_ levels: Int = 20) -> some View {
        modifier(UndoHistoryCapModifier(levels: levels))
    }
}

private struct UndoHistoryCapModifier: ViewModifier {
    @Environment(\.undoManager) private var undoManager
    let levels: Int

    func body(content: Content) -> some View {
        content.task(id: undoManager.map(ObjectIdentifier.init)) {
            undoManager?.levelsOfUndo = levels
        }
    }
}
