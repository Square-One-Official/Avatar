// Rename-modal (E19.3) — DS-stijl, getriggerd vanuit het sidebar-context-menu
// (E19.2). DSTextField op de portret-naam; Save schrijft door (SwiftData
// autosave), Cancel/kruis sluit.

import AvatarKit
import AvatarUI
import SwiftUI

struct RenameSheet: View {
    let portrait: Portrait2
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text("Rename").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small) { dismiss() }
                    .accessibilityLabel("Close")
            }
            DSTextField(label: "Name", placeholder: "Name", text: $draft)
                .onSubmit { save() }
            HStack(spacing: DSSpacing.gap3) {
                DSNeutralButton("Cancel", fullWidth: true) { dismiss() }
                DSPrimaryButton("Save", fullWidth: true) { save() }
            }
        }
        .padding(DSSpacing.gap8)
        .frame(width: 360)
        .background(DSColor.Background.app)
        .onAppear { draft = portrait.name }
    }

    private func save() {
        portrait.name = draft.trimmingCharacters(in: .whitespaces)
        portrait.touch()
        dismiss()
    }
}
