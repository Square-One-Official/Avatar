// Name/Role-header (E05.5 → herzien E24.21). Eén knop (geen inline-inputs meer)
// die de gedeelde rename-modal opent (Name + Role). Rust = pure tekst
// (gecentreerd boven de canvas-kaart), hover = subtiele affordance. Naam =
// Body/Medium primary, rol = Body/Small subtle. De modal schrijft door naar
// het geselecteerde Portrait2; deze view leest het portret direct zodat de
// wijziging meteen zichtbaar is.

import AvatarUI
import SwiftUI

struct PortraitHeader: View {
    @Bindable var model: ShellModel

    private var name: String {
        let n = model.selectedPortrait?.name ?? ""
        return n.isEmpty ? "Name" : n
    }
    private var role: String {
        let r = model.selectedPortrait?.role ?? ""
        return r.isEmpty ? "Role" : r
    }
    private var hasName: Bool { !(model.selectedPortrait?.name ?? "").isEmpty }
    private var hasRole: Bool { !(model.selectedPortrait?.role ?? "").isEmpty }

    var body: some View {
        Button {
            model.isShowingRename = true
        } label: {
            VStack(spacing: 0) {
                Text(name)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(hasName ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                    .lineLimit(1)
                Text(role)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(hasRole ? DSColor.Foreground.subtle : DSColor.Foreground.muted)
                    .lineLimit(1)
            }
            // E03.17 criterium 3: vaste gereserveerde hoogte (28 + 24).
            .frame(height: 52, alignment: .top)
            .padding(.horizontal, DSSpacing.gap3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help("Rename")
    }
}
