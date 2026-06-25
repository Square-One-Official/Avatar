// Social-preview-surface (E34.5). Volledige overlay over de editor (crossfade,
// shell-niveau): toont de profielfoto-in-context in een minimalistisch skeleton-
// wireframe per platform. Bovenaan een segmented-control (LinkedIn default · X ·
// Instagram · All) + een sluit-knop; rechts de banner-bediening + export.
//
// De ronde profielfoto hergebruikt de bestaande export-pijplijn
// (PortraitExporter, shape .circle); de banner-laag komt uit BannerResolver
// (match-portret / kleur / afbeelding) en wordt voor de preview direct in SwiftUI
// getekend (geen volle composite per frame — dat is alleen de export, E34.7).

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

struct SocialPreviewView: View {
    let portrait: Portrait2
    var isPro: Bool = false
    var onClose: () -> Void = {}
    /// E35.4: navigeer naar de Banners-bibliotheek (sluit de preview).
    var onManageBanners: () -> Void = {}

    @Environment(\.undoManager) private var undoManager
    @State private var tab: PreviewTab = .linkedIn
    @State private var avatarImage: NSImage?
    @State private var bannerFill: BannerCompositor.Fill?

    private var cardWidth: CGFloat { tab == .all ? 380 : 540 }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                previewArea
                controlColumn
                    .padding(.trailing, DSSpacing.gap3)
                    .padding(.bottom, DSSpacing.gap3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.Background.app)
        .task(id: portrait.updatedAt) { refresh() }
    }

    // MARK: Header — segmented switcher + close

    private var header: some View {
        ZStack {
            Picker("", selection: $tab) {
                ForEach(PreviewTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 380)

            HStack {
                Spacer()
                DSIconButton(Image(systemName: "xmark"), size: .small) { onClose() }
                    .accessibilityLabel("Close preview")
            }
        }
        .padding(.horizontal, DSSpacing.gap5)
        .padding(.vertical, DSSpacing.gap4)
    }

    // MARK: Preview — skeleton chrome per platform

    private var previewArea: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap8) {
                ForEach(tab.platforms) { platform in
                    PlatformChrome(platform: platform, width: cardWidth) {
                        bannerLayer
                    } avatar: {
                        avatarView
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.gap8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var bannerLayer: some View {
        switch bannerFill {
        case let .color(r, g, b):
            Color(.sRGB, red: r, green: g, blue: b)
        case let .image(cg):
            Image(decorative: cg, scale: 1).resizable().scaledToFill()
        case nil:
            DSColor.Background.inset
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImage {
            Image(nsImage: avatarImage).resizable().scaledToFill()
        } else {
            DSColor.Background.neutral
        }
    }

    // MARK: Controls — banner picker + export

    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap5) {
            Text("Banner")
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)

            ScrollView {
                BannerChooser(portrait: portrait, onApply: applyBanner, onManage: onManageBanners)
            }
            .frame(maxHeight: .infinity)

            Spacer(minLength: 0)

            VStack(spacing: DSSpacing.gap2) {
                DSNeutralButton("Save profile picture", fullWidth: true) { saveProfilePicture() }
                ForEach(tab.platforms.filter(\.hasCover)) { platform in
                    DSPrimaryButton("Save \(platform.displayName) banner", fullWidth: true) {
                        saveBanner(platform)
                    }
                }
            }

            if !isPro {
                Text("Free exports include a small “Made with Aaavatar” mark.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DSSpacing.gap5)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        // Zwevende, afgeronde kaart met lucht rondom (zoals de left-nav) i.p.v.
        // een edge-to-edge paneel met scheidingslijn.
        .background(
            DSColor.Background.card,
            in: RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
        )
    }

    // MARK: Actions

    @MainActor
    private func refresh() {
        avatarImage = PortraitExporter
            .makePNG(for: portrait, watermark: false, side: 512, shape: .circle)
            .flatMap(NSImage.init(data:))
        bannerFill = BannerResolver.fill(for: portrait)
    }

    private func applyBanner(_ banner: BannerBackground) {
        let before = portrait.bannerBackground
        guard before != banner else { return }
        portrait.setBannerBackground(banner)
        ReversibleChange.register(
            undoManager, target: portrait, from: before, to: banner, actionName: "Banner"
        ) { p, b in p.setBannerBackground(b) }
    }

    private func saveProfilePicture() {
        let data = PortraitExporter.makePNG(for: portrait, watermark: !isPro, side: 512, shape: .circle)
        save(data, defaultName: "Aaavatar-profile.png")
    }

    private func saveBanner(_ platform: SocialPlatform) {
        let data = PortraitExporter.makeBannerPNG(for: portrait, platform: platform, watermark: !isPro)
        save(data, defaultName: "Aaavatar-\(platform.rawValue)-cover.png")
    }

    private func save(_ data: Data?, defaultName: String) {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
