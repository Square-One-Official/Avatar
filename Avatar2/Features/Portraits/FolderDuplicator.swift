// E50.5 — map dupliceren mét inhoud. Use-case: een effect (of andere set-brede
// actie) op het hele team toepassen zonder het origineel aan te raken: kopieer
// de map, werk in de kopie. Elk portret wordt volledig gekopieerd (cutout,
// origineel, achtergrond, Adjust-laag, frame, effect-cache — dus schakelen
// tussen al gegenereerde effecten blijft gratis), de map-default-achtergrond
// gaat mee. Eén undo-stap ("Duplicate Folder"): undo verwijdert de kopie en
// alle gekopieerde portretten, redo dupliceert opnieuw vanaf de bronmap.
//
// Dupliceren is géén import: de Starter-cap (`FreeTier.maxPortraits`) telt
// server-side cutout-claims en wordt hier niet geraakt.

import Foundation
import SwiftData

extension Portrait2 {
    /// Een losse, nog niet ingevoegde kopie met dezelfde pixels en instellingen.
    /// Wat bewust NIET meegaat: `lastOpenedAt` (Home-hero-historie), `v1ImportID`
    /// (de dedup-sleutel van de v1-back-up-import hoort bij het origineel),
    /// `folder` (zet de aanroeper) en de board-positie (`boardPlaced = false` →
    /// de board-lens van de nieuwe map doet z'n eigen auto-layout).
    func duplicate(createdAt: Date = .now) -> Portrait2 {
        let copy = Portrait2(
            name: name,
            role: role,
            createdAt: createdAt,
            cutoutData: cutoutData,
            originalData: originalData
        )
        copy.cutoutDerivesFromOriginal = cutoutDerivesFromOriginal
        copy.editSourceData = editSourceData
        copy.editSourceCutoutSig = editSourceCutoutSig
        copy.offsetX = offsetX
        copy.offsetY = offsetY
        copy.scale = scale
        copy.backgroundColorHex = backgroundColorHex
        copy.backgroundImageData = backgroundImageData
        copy.useOriginalBackground = useOriginalBackground
        copy.backgroundBannerID = backgroundBannerID
        copy.portraitBlur = portraitBlur
        copy.adjust = adjust
        copy.frameShapeRaw = frameShapeRaw
        copy.boardOrder = boardOrder
        copy.boardPlaced = false
        copy.effectBaseData = effectBaseData
        copy.effectActiveRaw = effectActiveRaw
        copy.effectCacheData = effectCacheData
        copy.bannerColorHex = bannerColorHex
        copy.bannerImageData = bannerImageData
        copy.bannerMatchesBackground = bannerMatchesBackground
        return copy
    }
}

@MainActor
enum FolderDuplicator {
    static let actionName = "Duplicate Folder"

    /// Resultaat van één duplicatie: de nieuwe map + haar portretten (in de
    /// volgorde van de bronmap, oudst → jongst).
    struct Copy {
        let folder: Folder2
        let portraits: [Portrait2]
    }

    /// Finder-stijl kopienaam: "Team copy", daarna "Team copy 2", "Team copy 3"…
    /// — uniek binnen `existingNames` (hoofdletter-ongevoelig, whitespace-
    /// getrimd). Een lege bronnaam wordt "Untitled folder copy".
    static func copyName(for name: String, existingNames: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = (base.isEmpty ? "Untitled folder" : base) + " copy"
        let taken = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !taken.contains(stem.lowercased()) { return stem }
        var n = 2
        while taken.contains("\(stem) \(n)".lowercased()) { n += 1 }
        return "\(stem) \(n)"
    }

    /// Maakt en voegt de kopie in (map + portretten), zonder undo-registratie.
    /// `portraits` = de te kopiëren inhoud (default: de hele map). De kopieën
    /// krijgen oplopende `updatedAt`-stempels vanaf `now`, zodat ze in elke lens
    /// bovenaan landen mét de onderlinge volgorde van de bronmap intact.
    @discardableResult
    static func duplicate(
        _ source: Folder2,
        portraits: [Portrait2]? = nil,
        existingNames: [String],
        in context: ModelContext,
        now: Date = .now
    ) -> Copy {
        let folder = Folder2(name: copyName(for: source.name, existingNames: existingNames), createdAt: now)
        folder.defaultBackgroundColorHex = source.defaultBackgroundColorHex
        folder.defaultBackgroundImageData = source.defaultBackgroundImageData
        context.insert(folder)

        let ordered = (portraits ?? source.portraits).sorted { $0.updatedAt < $1.updatedAt }
        var copies: [Portrait2] = []
        for (index, original) in ordered.enumerated() {
            let stamp = now.addingTimeInterval(Double(index) * 0.001)
            let copy = original.duplicate(createdAt: stamp)
            context.insert(copy)
            copy.folder = folder
            copies.append(copy)
        }
        return Copy(folder: folder, portraits: copies)
    }

    /// Dupliceert de map als één undo-groep en meldt zich bij de shell (compacte
    /// bon met Undo). `onUndo` krijgt de verwijderde kopie zodat de shell een
    /// selectie/lens die erop stond kan terugzetten. Redo maakt een verse kopie
    /// vanaf de (nog bestaande) bronmap.
    @discardableResult
    static func perform(
        _ source: Folder2,
        existingNames: [String],
        modelContext: ModelContext,
        undoManager: UndoManager?,
        reporter: SetActionReporter,
        onUndo: @escaping (Folder2) -> Void = { _ in }
    ) -> Copy {
        let copy = duplicate(source, existingNames: existingNames, in: modelContext)
        registerUndo(
            for: copy, source: source, existingNames: existingNames,
            modelContext: modelContext, undoManager: undoManager, onUndo: onUndo
        )
        let n = copy.portraits.count
        reporter.done(SetActionReceipt(
            title: n == 1 ? "Folder duplicated with 1 portrait" : "Folder duplicated with \(n) portraits",
            actionName: actionName,
            compact: true,
            undoManager: undoManager
        ))
        return copy
    }

    private static func registerUndo(
        for copy: Copy,
        source: Folder2,
        existingNames: [String],
        modelContext: ModelContext,
        undoManager: UndoManager?,
        onUndo: @escaping (Folder2) -> Void
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: modelContext) { [weak undoManager] context in
            for portrait in copy.portraits where !portrait.isDeleted {
                context.delete(portrait)
            }
            if !copy.folder.isDeleted {
                context.delete(copy.folder)
            }
            onUndo(copy.folder)
            // Redo = opnieuw dupliceren vanaf de bron (als die er nog is).
            guard let undoManager, !source.isDeleted else { return }
            undoManager.registerUndo(withTarget: context) { context in
                let again = duplicate(source, existingNames: existingNames, in: context)
                registerUndo(
                    for: again, source: source, existingNames: existingNames,
                    modelContext: context, undoManager: undoManager, onUndo: onUndo
                )
            }
            undoManager.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }
}
