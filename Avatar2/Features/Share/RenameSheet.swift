// Rename-modal (E19.3, uitgebreid E24.21) — DS-stijl, gedeeld door het
// sidebar-context-menu (E19.2/24.22) én de Name/Role-knop op het canvas
// (24.21). Bevat Name ÉN Role; Save schrijft door (SwiftData autosave),
// Cancel/kruis sluit.

import AvatarKit
import AvatarUI
import SwiftUI

struct RenameSheet: View {
    /// Eén of meer portretten. Bij ≥2 zet Save dezelfde naam + rol op állemaal
    /// (board-multiselectie); bij één het bekende enkel-rename-gedrag.
    let portraits: [Portrait2]
    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var draftRole = ""

    init(portrait: Portrait2) { self.portraits = [portrait] }
    init(portraits: [Portrait2]) { self.portraits = portraits }

    private var isBulk: Bool { portraits.count >= 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            HStack {
                Text(isBulk ? "Rename \(portraits.count) portraits" : "Rename")
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
        // Prefill met de gedeelde waarde; bij afwijkende waarden (gemengde
        // selectie) leeg, zodat Save bewust een nieuwe naam/rol op alles zet.
        .onAppear {
            draftName = commonValue(\.name)
            draftRole = commonValue(\.role)
        }
    }

    /// De gemeenschappelijke waarde van een veld over alle portretten, of "" als
    /// ze verschillen (of er geen zijn).
    private func commonValue(_ key: KeyPath<Portrait2, String>) -> String {
        guard let first = portraits.first?[keyPath: key] else { return "" }
        return portraits.allSatisfy { $0[keyPath: key] == first } ? first : ""
    }

    private func save() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let role = draftRole.trimmingCharacters(in: .whitespaces)
        for portrait in portraits {
            portrait.name = name
            portrait.role = role
            portrait.touch()
        }
        dismiss()
    }
}
