// Name/Role-header (E05.5 + E04.5-fix, Figma: App / Edit Frame 2,
// 4010:1940 — gecentreerd boven de canvas-kaart). Bevinding 9: inline
// edit via DSInlineEditLabel (E03.13) — rust = pure tekst, hover =
// badge-affordance, klik = echt veld op dezelfde plek; Enter/blur
// bevestigt, Esc annuleert. Naam = heading-variant (Body/Medium primary),
// rol = subtitle (Body/Small subtle). Waarden schrijven via ShellModel
// door naar het geselecteerde Portrait2 (E05.4).

import AvatarUI
import SwiftUI

struct PortraitHeader: View {
    @Bindable var model: ShellModel

    /// E24.7-revisie: vaste veldbreedte → het veld blijft op z'n gecentreerde
    /// plek staan; alleen de tekst lijnt links uit tijdens typen en centreert
    /// bij commit.
    private static let fieldWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            DSInlineEditLabel("Name", text: $model.portraitName, variant: .heading, fixedWidth: Self.fieldWidth)
            DSInlineEditLabel("Role", text: $model.portraitRole, variant: .subtitle, fixedWidth: Self.fieldWidth)
        }
        // E03.17 criterium 3: vaste gereserveerde hoogte (28 + 24 = de twee
        // regelhoogtes incl. badge-padding). E18.5: top-alignment.
        .frame(height: 52, alignment: .top)
    }
}
