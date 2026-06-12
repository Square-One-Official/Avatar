// Name/Role-header met inline edit (E05.5, Figma: App / Sidebar images —
// naam/rol boven het canvas). Inline edit = de tekst ís het tekstveld:
// plain TextFields in DS-typografie, prompt in muted. State leeft op
// ShellModel tot het SwiftData-model Portrait2 (E05.4) landt.

import AvatarUI
import SwiftUI

struct PortraitHeader: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
            TextField(
                "",
                text: $model.portraitName,
                prompt: Text("Name").foregroundStyle(DSColor.Foreground.muted)
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.h6)
            .foregroundStyle(DSColor.Foreground.primary)

            TextField(
                "",
                text: $model.portraitRole,
                prompt: Text("Role").foregroundStyle(DSColor.Foreground.muted)
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.bodySmall)
            .foregroundStyle(DSColor.Foreground.subtle)
        }
        .frame(maxWidth: 280, alignment: .leading)
    }
}
