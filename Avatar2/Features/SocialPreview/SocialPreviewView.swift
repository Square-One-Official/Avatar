// Social-preview-surface (E34.5). Eigen modus in de editor-sectie: toont de
// profielfoto-in-context in een minimalistisch skeleton-wireframe per platform.
// Klik op de avatar of banner in de mockup opent een kiezer-paneel; profiel-
// export via de shell-topbar (Share). Terug naar Edit via Edit · Preview.

import AppKit
import AvatarKit
import AvatarUI
import SwiftUI

struct SocialPreviewView: View {
    let model: ShellModel
    var isPro: Bool = false

    @Environment(\.undoManager) private var undoManager
    @State private var tab: PreviewTab = .linkedIn
    @State private var avatarImage: NSImage?
    @State private var bannerFill: BannerCompositor.Fill?
    @State private var activePicker: PreviewPicker?

    private static let pickerSpace = "socialPreviewPicker"

    private var portrait: Portrait2? { model.selectedPortrait }
    private var cardWidth: CGFloat { tab == .all ? 380 : 540 }

    var body: some View {
        ZStack(alignment: .top) {
            DSColor.Background.app
                .ignoresSafeArea(edges: [.horizontal, .bottom])
                .padding(.top, ShellMetrics.topBarBandHeight)

            VStack(spacing: 0) {
                header
                previewArea
            }
            .padding(.top, ShellMetrics.topBarBandHeight)

            pickerOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: portrait?.updatedAt) { await refresh() }
    }

    // MARK: Header — platform segmented switcher

    private var header: some View {
        DSSegmentedControl(
            selection: $tab,
            segments: PreviewTab.allCases.map { .init(tag: $0, label: $0.label) },
            equalWidth: true
        )
        .frame(width: 420)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSSpacing.gap5)
        .padding(.vertical, DSSpacing.gap3)
    }

    // MARK: Preview — skeleton chrome per platform

    private var previewArea: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap8) {
                ForEach(tab.platforms) { platform in
                    PlatformChrome(
                        platform: platform,
                        width: cardWidth,
                        coordinateSpace: .named(Self.pickerSpace),
                        onAvatarTap: { activePicker = .portrait(anchor: $0) },
                        onBannerTap: platform.hasCover
                            ? { activePicker = .banner(anchor: $0, platform: platform) }
                            : nil
                    ) {
                        bannerLayer
                    } avatar: {
                        avatarView
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DSSpacing.gap8)
        }
        .coordinateSpace(name: Self.pickerSpace)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var pickerOverlay: some View {
        if let activePicker, let portrait {
            switch activePicker {
            case .portrait(let anchor):
                PreviewPickerPanel(anchor: anchor, onDismiss: { self.activePicker = nil }) {
                    PortraitPickerPanel(current: portrait) { selected in
                        model.selectPortraitInPreview(selected)
                        self.activePicker = nil
                    }
                }
            case .banner(let anchor, let platform):
                PreviewPickerPanel(anchor: anchor, onDismiss: { self.activePicker = nil }) {
                    BannerPickerPanel(
                        portrait: portrait,
                        platform: platform,
                        isPro: isPro,
                        onApply: applyBanner,
                        onSave: saveBanner
                    )
                }
            }
        }
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

    // MARK: Actions

    @MainActor
    private func refresh() async {
        guard let portrait else {
            avatarImage = nil
            bannerFill = nil
            return
        }
        avatarImage = PortraitExporter
            .makePNG(for: portrait, watermark: false, side: 512, shape: .circle)
            .flatMap(NSImage.init(data:))
        bannerFill = BannerResolver.fill(for: portrait)
    }

    private func applyBanner(_ banner: BannerBackground) {
        guard let portrait else { return }
        let before = portrait.bannerBackground
        guard before != banner else { return }
        portrait.setBannerBackground(banner)
        ReversibleChange.register(
            undoManager, target: portrait, from: before, to: banner, actionName: "Banner"
        ) { p, b in p.setBannerBackground(b) }
        Task { await refresh() }
    }

    private func saveBanner(_ platform: SocialPlatform) {
        guard let portrait else { return }
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
