// Rename-modal (E19.3, uitgebreid E24.21) — DS-stijl, gedeeld door het
// sidebar-context-menu (E19.2/24.22) én de Name/Role-knop op het canvas
// (24.21). Bevat Name ÉN Role; Save schrijft door (SwiftData autosave),
// Cancel/kruis sluit.

import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct RenameSheet: View {
    private let inlinePortraits: [Portrait2]
    private let portraitIDs: [PersistentIdentifier]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var draftName = ""
    @State private var draftRole = ""

    init(portrait: Portrait2) {
        inlinePortraits = [portrait]
        portraitIDs = []
    }

    init(portraits: [Portrait2]) {
        inlinePortraits = portraits
        portraitIDs = []
    }

    /// E53.7: ID-snapshot vanuit BoardView — stabiel op ShellView-host.
    init(portraitIDs: [PersistentIdentifier]) {
        inlinePortraits = []
        self.portraitIDs = portraitIDs
    }

    private var targets: [Portrait2] {
        if !inlinePortraits.isEmpty { return inlinePortraits }
        return portraitIDs.compactMap { modelContext.model(for: $0) as? Portrait2 }
    }

    private var isBulk: Bool { targets.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text(isBulk ? "Rename \(targets.count) portraits" : "Rename")
                    .dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), label: "Close", size: .small) { dismiss() }
            }
            DSTextField(label: "Name", placeholder: "Name", text: $draftName)
                .onSubmit { save() }
            DSTextField(label: "Role", placeholder: "Role", text: $draftRole)
                .onSubmit { save() }
            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton("Cancel", fullWidth: true) { dismiss() }
                DSPrimaryButton("Save", fullWidth: true) { save() }
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 360)
        .background(DSColor.Background.app)
        .appliedAppearancePreference()
        .onAppear {
            draftName = commonValue(\.name)
            draftRole = commonValue(\.role)
        }
    }

    private func commonValue(_ key: KeyPath<Portrait2, String>) -> String {
        guard let first = targets.first?[keyPath: key] else { return "" }
        return targets.allSatisfy { $0[keyPath: key] == first } ? first : ""
    }

    private func save() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let role = draftRole.trimmingCharacters(in: .whitespaces)
        for portrait in targets {
            portrait.name = name
            portrait.role = role
            portrait.touch()
        }
        dismiss()
    }
}
