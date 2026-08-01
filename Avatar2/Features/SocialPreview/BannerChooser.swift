// Banner-kiezer in de social-preview (E35.4). Kies "Match avatar" (default) of
// één van je opgeslagen banners (Banners-bibliotheek). Maken gebeurt in de
// Banners-sectie — hier kies je alleen. Een keuze kopieert de banner-bytes
// naar het portret (`.image`), undo'baar via de caller.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct BannerPickerContent: View {
    let portrait: Portrait2
    var onApply: (BannerBackground) -> Void

    @Query(sort: \BannerDoc.updatedAt, order: .reverse) private var banners: [BannerDoc]
    private var savedBanners: [BannerDoc] { banners.filter { $0.previewImageData != nil } }

    private var isMatchSelected: Bool { portrait.bannerMatchesBackground }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            matchRow

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
                            .font(.system(size: DSIconSize.sm, weight: .semibold))
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
}

struct BannerPickerPanel: View {
    let portrait: Portrait2
    let platform: SocialPlatform
    var isPro: Bool
    var onApply: (BannerBackground) -> Void
    var onSave: (SocialPlatform) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap3) {
            Text("Banner")
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.primary)

            if AppFeatureFlags.bannersEnabled {
                // Volledige kiezer: match-avatar of een opgeslagen banner.
                BannerPickerContent(portrait: portrait, onApply: onApply)
            } else {
                // Release zonder Banners-suite: geen maken/kiezen meer — de banner
                // matcht de portret-achtergrond en kan alleen geëxporteerd worden.
                Text("This banner matches your portrait background.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if platform.hasCover {
                DSPrimaryButton("Save \(platform.displayName) banner", fullWidth: true) {
                    onSave(platform)
                }
            }

            if !isPro {
                Text("Free exports include a small “Made with Aaavatar” mark.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
