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
    @State private var avatarImage: NSImage?
    @State private var bannerFill: BannerCompositor.Fill?

    private var activePicker: Binding<PreviewPicker?> {
        Binding(
            get: { model.presentation.previewPicker },
            set: { model.presentation.previewPicker = $0 }
        )
    }

    private static let pickerSpace = "socialPreviewPicker"

    private var portrait: Portrait2? { model.selectedPortrait }
    private let cardWidth: CGFloat = 600

    var body: some View {
        ZStack(alignment: .top) {
            DSColor.Background.app
                .ignoresSafeArea(edges: [.horizontal, .bottom])

            previewArea

            pickerOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // E50.3: revision (niet updatedAt) + id — twee portretten kunnen dezelfde
        // revision delen, dus de id hoort in de sleutel.
        .task(id: portrait.map { "\($0.persistentModelID)-\($0.revision)" }) { await refresh() }
    }

    // MARK: Preview — skeleton chrome per platform

    private var previewArea: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap8) {
                ForEach(SocialPlatform.allCases) { platform in
                    PlatformChrome(
                        platform: platform,
                        width: cardWidth,
                        coordinateSpace: .named(Self.pickerSpace),
                        onAvatarTap: { activePicker.wrappedValue = .portrait(anchor: $0) },
                        onBannerTap: platform.hasCover
                            ? { activePicker.wrappedValue = .banner(anchor: $0, platform: platform) }
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
        if let activePicker = activePicker.wrappedValue, let portrait {
            switch activePicker {
            case .portrait(let anchor):
                PreviewPickerPanel(anchor: anchor, onDismiss: { self.activePicker.wrappedValue = nil }) {
                    PortraitPickerPanel(current: portrait) { selected in
                        model.selectPortraitInPreview(selected)
                        self.activePicker.wrappedValue = nil
                    }
                }
            case .banner(let anchor, let platform):
                PreviewPickerPanel(anchor: anchor, onDismiss: { self.activePicker.wrappedValue = nil }) {
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
        avatarImage = await PortraitExporter
            .makePNGAsync(for: portrait, watermark: false, side: 512, shape: .circle)
            .flatMap(NSImage.init(data:))
        // Zonder de Banners-suite matcht de banner altijd de portret-achtergrond
        // (geen eigen banner-keuze meer); anders volgt 'ie de keuze van het portret.
        bannerFill = AppFeatureFlags.bannersEnabled
            ? BannerResolver.fill(for: portrait)
            : BannerResolver.fill(for: portrait, banner: .matchPortrait)
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
        // Bij uitgeschakelde Banners-suite exporteert "Save banner" altijd de
        // portret-achtergrond (match), ongeacht een eventueel opgeslagen keuze.
        let data = PortraitExporter.makeBannerPNG(
            for: portrait,
            platform: platform,
            watermark: !isPro,
            banner: AppFeatureFlags.bannersEnabled ? nil : .matchPortrait
        )
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
