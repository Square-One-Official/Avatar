// Main shell — first-use-empty-state (E05.1 + E04.5-pass, Figma: App /
// First use, 4008:7050). Memoji-cirkel: 6 avatars 112×112 op de Figma-
// posities (ring 469×524), elk een geregistreerde asset-placeholder
// (plan/ASSETS.md #2) — projects-paletcirkel + persoonsglyph + dashed rand
// als markering. Center: lime plus (Icon-Only Button fillBrand 40) met
// daaronder "Drop a portrait" (Labels/Base primary) en "or choose a file"
// (subtle + lime link, opent de bestandskiezer net als de plus).

import AvatarUI
import SwiftUI

struct FirstUseEmptyState: View {
    /// E05.2 (Import) hangt hier de bestandskiezer aan.
    let onChooseFile: () -> Void

    /// Figma Frame 28 (469×524): posities linksboven per avatar.
    private static let memojiOffsets: [CGSize] = [
        CGSize(width: 178.4, height: 0),
        CGSize(width: 0.3, height: 103), CGSize(width: 356.8, height: 103),
        CGSize(width: 0, height: 309), CGSize(width: 357.1, height: 309),
        CGSize(width: 178.4, height: 412)
    ]
    private static let ringSize = CGSize(width: 469, height: 524)
    private static let avatarSize: CGFloat = 112

    private static let memojiColors: [Color] = [
        DSColor.Projects.project1, DSColor.Projects.project8,
        DSColor.Projects.project15, DSColor.Projects.project18,
        DSColor.Projects.project4, DSColor.Projects.project12
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.memojiOffsets.enumerated()), id: \.offset) { index, position in
                MemojiPlaceholder(color: Self.memojiColors[index % Self.memojiColors.count])
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .offset(
                        x: position.width - (Self.ringSize.width - Self.avatarSize) / 2,
                        y: position.height - (Self.ringSize.height - Self.avatarSize) / 2
                    )
            }

            VStack(spacing: DSSpacing.gap4) {
                DSIconButton(Image(systemName: "plus"), style: .fillBrand) {
                    onChooseFile()
                }
                VStack(spacing: 0) {
                    Text("Drop a portrait")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                    HStack(spacing: 0) {
                        Text("or ")
                            .dsTextStyle(.labelBase)
                            .foregroundStyle(DSColor.Foreground.subtle)
                        Button("choose a file") {
                            onChooseFile()
                        }
                        .buttonStyle(.plain)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Action.primary)
                    }
                }
            }
        }
        .frame(width: Self.ringSize.width, height: Self.ringSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.Background.app)
        .preferredColorScheme(.dark)
    }
}

/// ASSET-PLACEHOLDER (plan/ASSETS.md #2): memoji-figuur uit App / First
/// use. Cirkel in projects-paletkleur (zoals het frame) met persoonsglyph
/// en dashed markeringsrand; de echte memoji-beelden komen in de
/// assetbatch van Thierry.
private struct MemojiPlaceholder: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: "person.fill")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(DSColor.Foreground.primaryStaticBlack.opacity(DSOpacity.subtle))
            Circle()
                .strokeBorder(
                    DSColor.Foreground.primaryStaticBlack.opacity(DSOpacity.disabled),
                    style: StrokeStyle(lineWidth: DSBorderWidth.thin, dash: [4, 4])
                )
        }
        .accessibilityHidden(true)
    }
}
