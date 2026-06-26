// Banner-kiezer in de social-preview (E35.4). Kies "Match avatar" (default) of
// één van je opgeslagen banners (Banners-bibliotheek). Maken/uploaden gebeurt in
// de Banners-sectie — hier kies je alleen. Een keuze kopieert de banner-bytes
// naar het portret (`.image`), undo'baar via de caller.

import AvatarUI
import SwiftData
import SwiftUI

struct BannerChooser: View {
    let portrait: Portrait2
    var onApply: (BannerBackground) -> Void
    var onManage: () -> Void

    // E37.6: de social-preview kiest nu uit `BannerDoc`-previews (de Studio-store).
    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var banners: [BannerDoc]
    private var savedBanners: [BannerDoc] { banners.filter { $0.previewImageData != nil } }

    private var isMatchSelected: Bool { portrait.bannerMatchesBackground }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            // Match avatar (default).
            matchRow

            // Opgeslagen banners.
            VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                Text("Your banners")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)

                if savedBanners.isEmpty {
                    Text("No banners yet. Create some in the Banners section.")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(savedBanners) { banner in
                    bannerTile(banner)
                }

                newBannerTile
            }
        }
    }

    private var matchRow: some View {
        Button { onApply(.matchPortrait) } label: {
            HStack(spacing: DSSpacing.gap2) {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(DSColor.Background.neutral)
                    .frame(width: 40, height: 28)
                    .overlay {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DSColor.Foreground.subtle)
                    }
                Text("Match avatar").dsTextStyle(.labelBase).foregroundStyle(DSColor.Foreground.primary)
                Spacer(minLength: 0)
            }
            .padding(DSSpacing.gap1)
            .background(
                isMatchSelected ? DSColor.Background.neutralStronger : .clear,
                in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func bannerTile(_ banner: BannerDoc) -> some View {
        if let data = banner.previewImageData {
            let selected = !portrait.bannerMatchesBackground && portrait.bannerImageData == data
            Button { onApply(.image(data)) } label: {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(DSColor.Background.inset)
                    .aspectRatio(1500.0 / 500.0, contentMode: .fit)
                    .overlay {
                        if let img = NSImage(data: data) {
                            Image(nsImage: img).resizable().scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                            .strokeBorder(DSColor.Foreground.primary, lineWidth: selected ? 2 : 0)
                    }
            }
            .buttonStyle(.plain)
            .help(banner.name.isEmpty ? "Untitled banner" : banner.name)
        }
    }

    private var newBannerTile: some View {
        Button(action: onManage) {
            RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                .strokeBorder(DSColor.Foreground.divider, style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(height: 40)
                .overlay {
                    HStack(spacing: DSSpacing.gap1_5) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text("New banner").dsTextStyle(.labelSmall)
                    }
                    .foregroundStyle(DSColor.Foreground.muted)
                }
        }
        .buttonStyle(.plain)
        .help("Create banners in the Banners section")
    }
}
