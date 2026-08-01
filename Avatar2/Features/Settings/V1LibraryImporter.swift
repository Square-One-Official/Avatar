// E13.2 — migratiepad: Aaavatar 1-back-up → Portrait2-store.
//
// De gebruiker exporteert in v1 (Settings → bibliotheek-back-up, een .zip) en
// kiest dat bestand hier. Read-only aan de v1-kant: we lezen alleen het
// archief; v1's eigen store wordt nooit aangeraakt (kan ook niet — andere
// sandbox). Idempotent aan de v2-kant: elk portret onthoudt zijn v1-UUID
// (`Portrait2.v1ImportID`), dus nogmaals importeren maakt geen duplicaten.
//
// Wat er meekomt en wat niet — en waarom:
// - cutout + naam + datums: mee. De cutout is het werkstuk.
// - originele foto: v1's back-up bevat 'm niet (alleen een bookmark op de
//   bronmachine), dus `originalData` blijft nil — v2 verbergt dan zelf de
//   Original-achtergrondkeuze (bestaand legacy-pad).
// - v1-tags: v2 heeft geen tags-veld. Ze lijken in de praktijk op rollen
//   ("CEO", "Marketing") → we zetten ze in `role`, het veld dat v2 op de
//   kaart toont. Fout gegokt = één klik hernoemen; weggooien = onherstelbaar.
// - transform/adjust: NIET mee. v1's offset/scale leven in een 1024-canvas
//   met een ander achtergrondmodel; half-kloppende geometrie oogt kapotter
//   dan een nette her-layout in v2's eigen systeem.
// - Er lopen geen backend-calls en er worden geen credits geraakt: de cutout
//   ís al vrijstaand, er valt niets te genereren.

import AppKit
import AvatarKit
import SwiftData
import SwiftUI

@MainActor
enum V1LibraryImporter {

    struct Summary: Equatable {
        var imported = 0
        /// Al aanwezig (zelfde v1-UUID) — overgeslagen, niet overschreven:
        /// de gebruiker kan het portret in v2 al bewerkt hebben.
        var duplicates = 0
        /// Records zonder cutout in het archief (benoemd, niet stil gesnoeid).
        var withoutCutout = 0

        var userMessage: String {
            var parts: [String] = []
            parts.append(imported == 1 ? "1 portrait imported" : "\(imported) portraits imported")
            if duplicates > 0 { parts.append("\(duplicates) already present") }
            if withoutCutout > 0 { parts.append("\(withoutCutout) skipped (no image in backup)") }
            return parts.joined(separator: " · ")
        }
    }

    static let importFolderName = "Aaavatar 1"

    /// Importeert een gelezen back-up in de store. Puur op modelniveau — de
    /// file-picker en toasts leven bij de call site — zodat dit met een
    /// in-memory container testbaar is.
    static func importLibrary(_ library: V1LibraryArchive.Library, into context: ModelContext) throws -> Summary {
        var summary = Summary()
        summary.withoutCutout = library.skippedWithoutCutout

        // Bestaande v1-id's één keer ophalen i.p.v. één query per record.
        let existing = try context.fetch(
            FetchDescriptor<Portrait2>(predicate: #Predicate { $0.v1ImportID != nil })
        )
        var seen = Set(existing.compactMap(\.v1ImportID))

        guard library.portraits.contains(where: { !seen.contains($0.id.uuidString) }) else {
            summary.duplicates = library.portraits.count
            return summary
        }

        // Alles landt in één "Aaavatar 1"-map: de datums blijven de échte
        // v1-datums (dus oude portretten komen netjes in "Earlier"), en de
        // gebruiker ziet in één oogopslag wat er uit de migratie komt.
        let folder = try findOrCreateImportFolder(in: context)

        for payload in library.portraits {
            if seen.contains(payload.id.uuidString) {
                summary.duplicates += 1
                continue
            }
            let portrait = Portrait2(
                name: payload.name,
                role: payload.tags,
                createdAt: payload.createdAt,
                cutoutData: payload.cutoutPNG
            )
            portrait.updatedAt = payload.updatedAt
            portrait.v1ImportID = payload.id.uuidString
            portrait.folder = folder
            context.insert(portrait)
            seen.insert(payload.id.uuidString)
            summary.imported += 1
        }
        try context.save()
        return summary
    }

    private static func findOrCreateImportFolder(in context: ModelContext) throws -> Folder2 {
        let name = importFolderName
        let hit = try context.fetch(
            FetchDescriptor<Folder2>(predicate: #Predicate { $0.name == name })
        ).first
        if let hit { return hit }
        let folder = Folder2(name: name)
        context.insert(folder)
        return folder
    }

    // MARK: - UI-instap (file-picker)

    /// Toont de open-panel, leest en importeert. Resultaat/fout gaat via de
    /// completion terug naar de call site (die toast/alert kiest).
    static func presentImportPanel(
        modelContext: ModelContext,
        onDone: @escaping (Result<Summary, Error>) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Import Aaavatar 1 backup"
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the backup file you exported from Aaavatar 1 (Settings → Export library)."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let library = try V1LibraryArchive.read(from: url)
                    let summary = try importLibrary(library, into: modelContext)
                    onDone(.success(summary))
                } catch {
                    onDone(.failure(error))
                }
            }
        }
    }
}
