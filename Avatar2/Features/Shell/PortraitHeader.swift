// Name/Role-header met inline edit (E05.5 + E04.5-pass, Figma: App / Edit
// Frame 2, 4010:1940 — gecentreerd boven het canvas). Naam in Content/
// Body/Medium primary, rol in Content/Body/Small subtle, beide gecentreerd.
// Inline edit = de tekst ís het tekstveld: plain TextFields in DS-
// typografie, prompt in muted. State leeft op ShellModel tot het
// SwiftData-model Portrait2 (E05.4) landt.

import AvatarUI
import SwiftUI

struct PortraitHeader: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                "",
                text: $model.portraitName,
                prompt: Text("Name").foregroundStyle(DSColor.Foreground.muted)
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.bodyMedium)
            .foregroundStyle(DSColor.Foreground.primary)
            .multilineTextAlignment(.center)

            TextField(
                "",
                text: $model.portraitRole,
                prompt: Text("Role").foregroundStyle(DSColor.Foreground.muted)
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.subtle)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
    }
}
