// Hifi-haar-nudge (E05.6) — subtiele, niet-modale banner die ná een
// rafelig Vision-haarresultaat eenmalig aanbiedt het high-fidelity model
// te downloaden. Wegklikbaar (×); "Download" start de achtergrond-download
// (gedeelde OrmbgModelStore-state). Geen modal, geen blokkade.

import AvatarUI
import SwiftUI

struct HairNudgeBanner: View {
    let onDownload: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: DSIconSize.base, weight: .semibold))
                .foregroundStyle(DSColor.Action.primaryForeground)

            VStack(alignment: .leading, spacing: DSSpacing.gap0_5) {
                Text("Rough hair edges?")
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.primary)
                Text("Download the high-fidelity model for sharper detail — on-device.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
            }

            Button("Download", action: onDownload)
                .buttonStyle(.plain)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Action.onAction)
                .padding(.horizontal, DSSpacing.gap3)
                .padding(.vertical, DSSpacing.gap2)
                .background(DSColor.Action.primary)
                .clipShape(Capsule())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: DSIconSize.sm, weight: .semibold))
                    .foregroundStyle(DSColor.Foreground.subtle)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, DSSpacing.gap4)
        .padding(.trailing, DSSpacing.gap2)
        .padding(.vertical, DSSpacing.gap2)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xl2)
                .strokeBorder(DSColor.Foreground.divider, lineWidth: 1)
        )
        .dsShadow(.overlay)
        .frame(maxWidth: 460)
    }
}
