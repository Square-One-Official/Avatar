import Foundation
import SwiftData
import AppKit

enum SeedData {
    static func seedIfNeeded(context: ModelContext) {
        seedExportPresetsIfNeeded(context: context)
        seedDefaultBackgroundIfNeeded(context: context)
    }

    private static func seedExportPresetsIfNeeded(context: ModelContext) {
        // Platform guidelines:
        //  - LinkedIn accepts up to 8MB; 800×800 is the recommended profile size
        //    and LinkedIn itself masks to a circle, so we ship a SQUARE.
        //  - Slack requires square, minimum 512×512 (Slack masks corners).
        //  - Email (signatures) are rendered as-is by most clients, square is safe.
        //  - Generiek S/M/L for arbitrary use — default to square, user can
        //    toggle the canvas shape to circle before export if they need it.
        let builtIns: [(String, Int, Int, ExportShape)] = [
            ("LinkedIn",   800,  800, .square),
            ("Slack",      512,  512, .square),
            ("Email",      400,  400, .square),
            ("Generiek L", 1024, 1024, .square),
            ("Generiek M", 512,  512, .square),
            ("Generiek S", 256,  256, .square),
        ]

        // Upsert by name so existing installs pick up corrected values
        // (e.g. LinkedIn was previously circle; should be square). User-renamed
        // or user-deleted built-ins are left alone.
        let descriptor = FetchDescriptor<ExportPreset>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let byName = Dictionary(uniqueKeysWithValues: existing.map { ($0.name, $0) })

        for (idx, item) in builtIns.enumerated() {
            if let current = byName[item.0] {
                current.width = item.1
                current.height = item.2
                current.shape = item.3
                current.sortOrder = idx
            } else {
                context.insert(ExportPreset(
                    name: item.0, width: item.1, height: item.2,
                    shape: item.3, isBuiltIn: true, sortOrder: idx
                ))
            }
        }
        try? context.save()
    }

    private static func seedDefaultBackgroundIfNeeded(context: ModelContext) {
        // (resource filename without extension, all known localized display names, isDefault).
        // We track every localized variant so switching language between launches doesn't
        // reinsert the same seed under a new name (which would orphan a second isDefault=true).
        let seeds: [(resource: String, names: [String], isDefault: Bool)] = [
            ("Mesh 01", ["Mesh 01"], true),
            ("Mesh 02", ["Mesh 02"], false),
            ("Mesh 03", ["Mesh 03"], false),
            ("Mesh 04", ["Mesh 04"], false),
            ("Mesh 05", ["Mesh 05"], false),
            ("Mesh 06", ["Mesh 06"], false),
        ]

        let descriptor = FetchDescriptor<BackgroundPreset>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existing.map(\.name))

        var didInsert = false
        for seed in seeds {
            if seed.names.contains(where: { existingNames.contains($0) }) { continue }

            var data: Data? = nil
            if let url = Bundle.main.url(forResource: seed.resource, withExtension: "png") {
                data = try? Data(contentsOf: url)
            }
            guard data != nil else { continue }

            let preset = BackgroundPreset(
                name: seed.names.first ?? seed.resource,
                kind: .image,
                imageData: data,
                color: (0.94, 0.95, 0.97, 1.0),
                isDefault: seed.isDefault
            )
            context.insert(preset)
            didInsert = true
        }

        let didRemove = removeLegacyDefaultBackground(context: context)
        normalizeDefaultBackground(context: context)
        if didInsert || didRemove { try? context.save() }
    }

    /// Removes the legacy seeded white "Default"/"Standaard" preset that older
    /// builds shipped. Portraits pointing at it are reset to nil so the canvas
    /// falls back to whichever preset currently carries `isDefault == true`.
    @discardableResult
    private static func removeLegacyDefaultBackground(context: ModelContext) -> Bool {
        let legacyNames: Set<String> = ["Default", "Standaard"]
        let descriptor = FetchDescriptor<BackgroundPreset>(
            predicate: #Predicate { legacyNames.contains($0.name) }
        )
        let legacy = (try? context.fetch(descriptor)) ?? []
        guard !legacy.isEmpty else { return false }

        let legacyIDs = Set(legacy.map(\.id))
        let portraits = (try? context.fetch(FetchDescriptor<Portrait>())) ?? []
        for portrait in portraits {
            if let bgID = portrait.backgroundPresetID, legacyIDs.contains(bgID) {
                portrait.backgroundPresetID = nil
            }
        }
        for bg in legacy { context.delete(bg) }

        // If we just deleted the only preset that carried `isDefault`, promote
        // the first remaining preset (typically Mesh 01) so the picker still
        // has a highlighted chip on next launch.
        let remainingDefaults = (try? context.fetch(FetchDescriptor<BackgroundPreset>(
            predicate: #Predicate { $0.isDefault == true }
        ))) ?? []
        if remainingDefaults.isEmpty {
            let allRemaining = (try? context.fetch(FetchDescriptor<BackgroundPreset>(
                sortBy: [SortDescriptor(\.createdAt)]
            ))) ?? []
            allRemaining.first?.isDefault = true
        }
        return true
    }

    /// Ensures at most one BackgroundPreset has `isDefault == true`. When several do
    /// (older builds re-seeded across locale switches, CloudKit merges, etc.), keep
    /// the most recently created one — that matches the user's latest "Set as default"
    /// choice — and clear the rest.
    private static func normalizeDefaultBackground(context: ModelContext) {
        let descriptor = FetchDescriptor<BackgroundPreset>(
            predicate: #Predicate { $0.isDefault == true }
        )
        let defaults = (try? context.fetch(descriptor)) ?? []
        guard defaults.count > 1 else { return }
        let keep = defaults.max(by: { $0.createdAt < $1.createdAt })
        for bg in defaults where bg !== keep {
            bg.isDefault = false
        }
        try? context.save()
    }
}
