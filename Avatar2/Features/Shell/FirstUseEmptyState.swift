// Main shell — first-use-empty-state (E05.1 + E04.5-pass, Figma: App /
// First use, 4008:7050). Memoji-cirkel: 6 avatars 112×112 op de Figma-
// posities (ring 469×524), elk een geregistreerde asset-placeholder
// (plan/ASSETS.md #2) — projects-paletcirkel + persoonsglyph + dashed rand
// als markering. Center: lime plus (Icon-Only Button fillBrand 40) met
// daaronder "Drop a portrait" (Labels/Base primary) en "or choose a file"
// (subtle + lime link, opent de bestandskiezer net als de plus).

import AvatarKit
import AvatarUI
import SwiftUI

struct FirstUseEmptyState: View {
    /// E05.2 (Import) hangt hier de bestandskiezer aan.
    let onChooseFile: () -> Void
    /// CMS-avatars (E33+); optioneel zodat de view ook zonder backend werkt.
    var entitlement: EntitlementModel? = nil

    @State private var avatarUrls: [URL] = FirstUseEmptyState.cachedAvatarUrls

    private static var cachedAvatarUrls: [URL] = []

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
        // Punt 18b: de ring schaalt met de beschikbare ruimte — bij een
        // kleiner venster komen de cirkels dichter bij elkaar en worden ze
        // kleiner i.p.v. buiten beeld te vallen. Geen vaste offsets: alle
        // Figma-maten vermenigvuldigen met één schaalfactor; de center-
        // content (plus + copy) blijft op ware grootte.
        GeometryReader { geometry in
            let scale = Self.ringScale(for: geometry.size)
            ZStack {
                ForEach(Array(Self.memojiOffsets.enumerated()), id: \.offset) { index, position in
                    MemojiPlaceholder(
                        color: Self.memojiColors[index % Self.memojiColors.count],
                        imageUrl: index < avatarUrls.count ? avatarUrls[index] : nil,
                        diameter: Self.avatarSize * scale
                    )
                    .offset(
                        x: (position.width - (Self.ringSize.width - Self.avatarSize) / 2) * scale,
                        y: (position.height - (Self.ringSize.height - Self.avatarSize) / 2) * scale
                    )
                }

                centerContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DSColor.Background.app)
        // E23: volgt de AppearancePreference (geen forced .dark meer).
        .task { await loadAvatarUrls() }
    }

    private func loadAvatarUrls() async {
        guard let backend = entitlement?.backend else { return }
        guard let urls = try? await backend.appConfig(), !urls.emptyStateAvatarUrls.isEmpty else { return }
        FirstUseEmptyState.cachedAvatarUrls = urls.emptyStateAvatarUrls
        avatarUrls = urls.emptyStateAvatarUrls
    }

    /// Schaal t.o.v. de Figma-ring (469×524) binnen de beschikbare ruimte,
    /// met ademruimte voor de topbar; nooit groter dan ontwerpformaat.
    private static func ringScale(for size: CGSize) -> CGFloat {
        let reserveWidth: CGFloat = 48
        let reserveHeight: CGFloat = 120
        let fit = min(
            (size.width - reserveWidth) / ringSize.width,
            (size.height - reserveHeight) / ringSize.height
        )
        return min(1, max(0.35, fit))
    }

    private var centerContent: some View {
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
                        .foregroundStyle(DSColor.Action.primaryForeground)
                    }
                }
            }
    }
}

/// Eén avatar-cirkel in de lege-canvas-ring. Als `imageUrl` aanwezig is,
/// wordt het CMS-portret getoond (met cirkel-clip); anders de gekleurde
/// placeholder met `person.fill`-glyph (ASSET-PLACEHOLDER, plan/ASSETS.md #2).
private struct MemojiPlaceholder: View {
    let color: Color
    let imageUrl: URL?
    let diameter: CGFloat

    var body: some View {
        Group {
            if let url = imageUrl {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        placeholderCircle
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            } else {
                placeholderCircle
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholderCircle: some View {
        ZStack {
            Circle().fill(color)
            Image(systemName: "person.fill")
                .font(.system(size: diameter * (48.0 / 112.0), weight: .regular))
                .foregroundStyle(DSColor.Foreground.primaryStaticBlack.opacity(DSOpacity.subtle))
            Circle()
                .strokeBorder(
                    DSColor.Foreground.primaryStaticBlack.opacity(DSOpacity.disabled),
                    style: StrokeStyle(lineWidth: DSBorderWidth.thin, dash: [4, 4])
                )
        }
        .frame(width: diameter, height: diameter)
    }
}
