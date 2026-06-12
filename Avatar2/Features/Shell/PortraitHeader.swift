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

    var body: some View {
        VStack(spacing: 0) {
            DSInlineEditLabel("Name", text: $model.portraitName, variant: .heading)
            DSInlineEditLabel("Role", text: $model.portraitRole, variant: .subtitle)
        }
        .frame(maxWidth: 280)
    }
}
