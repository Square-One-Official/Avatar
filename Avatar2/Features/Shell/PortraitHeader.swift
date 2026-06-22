// Name/Role-header (E05.5 → herzien E24.21). Eén knop (geen inline-inputs meer)
// die de gedeelde rename-modal opent (Name + Role). Rust = pure tekst
// (naam·rol op één regel, gecentreerd — zweeft over het canvas), hover =
// subtiele affordance. Naam = Body/Medium primary, rol = Body/Small subtle.
// De modal schrijft door naar
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
            HStack(spacing: DSSpacing.gap2) {
                Text(name)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(hasName ? DSColor.Foreground.primary : DSColor.Foreground.muted)
                    .lineLimit(1)
                Text("·")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                Text(role)
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(hasRole ? DSColor.Foreground.subtle : DSColor.Foreground.muted)
                    .lineLimit(1)
            }
            // E31.x (besluit Thierry): naam·rol op één regel — de kop zweeft nu
            // over het canvas i.p.v. een 2-regelige strook in de flow. Vaste
            // gereserveerde hoogte van één tekstregel.
            .frame(height: 28)
            .padding(.horizontal, DSSpacing.gap3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help("Rename")
    }
}
