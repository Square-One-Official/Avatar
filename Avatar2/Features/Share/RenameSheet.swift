// Rename-modal (E19.3, uitgebreid E24.21) — DS-stijl, gedeeld door het
// sidebar-context-menu (E19.2/24.22) én de Name/Role-knop op het canvas
// (24.21). Bevat Name ÉN Role; Save schrijft door (SwiftData autosave),
// Cancel/kruis sluit.

import AvatarKit
import AvatarUI
import SwiftUI

struct RenameSheet: View {
    let portrait: Portrait2
    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var draftRole = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text("Rename").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small) { dismiss() }
                    .accessibilityLabel("Close")
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
        .onAppear { draftName = portrait.name; draftRole = portrait.role }
    }

    private func save() {
        portrait.name = draftName.trimmingCharacters(in: .whitespaces)
        portrait.role = draftRole.trimmingCharacters(in: .whitespaces)
        portrait.touch()
        dismiss()
    }
}
