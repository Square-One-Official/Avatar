// Main shell — first-use-empty-state (E05.1, Figma: App / First use).
// Copy is de gefixte review-versie. De memoji-cirkel is hier een
// gedocumenteerde placeholder (cirkel + glimlach-glyph): het echte
// memoji-beeld is een Figma-asset die geëxporteerd moet worden zodra het
// "Aaavatar"-bestand in de desktop-app open staat — zelfde visuele plek,
// asset er later in. Quota staat bewust níét in dit scherm (en de
// status-strip verbergt hem tot na de eerste cutout): geen quota-druk
// vóór waarde.

import AvatarUI
import SwiftUI

struct FirstUseEmptyState: View {
    /// E05.2 (Import) hangt hier de bestandskiezer aan.
    let onChooseFile: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.gap6) {
            Spacer()

            // Placeholder voor de memoji-cirkel uit Figma.
            ZStack {
                Circle()
                    .fill(DSColor.Background.card)
                Circle()
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
                Image(systemName: "face.smiling")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(DSColor.Foreground.muted)
            }
            .frame(width: 128, height: 128)

            VStack(spacing: DSSpacing.gap2) {
                Text("Drop a portrait — yours or a colleague's — or choose a file")
                    .dsTextStyle(.h6)
                    .foregroundStyle(DSColor.Foreground.primary)
                    .multilineTextAlignment(.center)
                Text("Everything happens on your Mac.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.subtle)
            }

            DSNeutralButton("Choose file…") {
                onChooseFile()
            }

            Spacer()
        }
        .padding(DSSpacing.gap8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.Background.app)
        .preferredColorScheme(.dark)
    }
}
