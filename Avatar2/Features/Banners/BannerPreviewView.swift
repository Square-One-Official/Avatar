// Banner-preview-modus (E37) — zelfde opzet als SocialPreviewView: platform-
// skeleton-wireframes met de live BannerDoc-render in de cover-band. Terug naar
// Edit via de shell-topbar (Edit · Preview).

import AppKit
import AvatarUI
import SwiftUI

struct BannerPreviewView: View {
    let doc: BannerDoc
    var isPro: Bool = false

    @State private var bannerImage: NSImage?

    private let cardWidth: CGFloat = 600

    var body: some View {
        ZStack(alignment: .top) {
            DSColor.Background.app
                .ignoresSafeArea(edges: [.horizontal, .bottom])

            previewArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: previewRefreshKey) { await refresh() }
    }

    /// Observeert laag-wijzigingen (niet alleen `updatedAt`) zodat een switch
    /// Edit → Preview altijd de actuele stack toont.
    private var previewRefreshKey: String {
        let fillTag: String
        switch doc.layers.fill {
        case .image: fillTag = "image"
        case .solid: fillTag = "solid"
        case .meshGradient: fillTag = "gradient"
        }
        return "\(doc.updatedAt.timeIntervalSinceReferenceDate)-\(fillTag)-\(doc.layers.shaders.count)-\(doc.layers.texts.count)-\(doc.fillImageData?.count ?? 0)"
    }

    private var previewArea: some View {
        ScrollView {
            VStack(spacing: DSSpacing.gap8) {
                ForEach(SocialPlatform.allCases) { platform in
                    PlatformChrome(
                        platform: platform,
                        width: cardWidth
                    ) {
                        bannerLayer
                    } avatar: {
                        placeholderAvatar
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
        if let bannerImage {
            Image(nsImage: bannerImage)
                .resizable()
                .scaledToFill()
        } else {
            DSColor.Background.inset
        }
    }

    private var placeholderAvatar: some View {
        DSColor.Background.neutral
    }

    @MainActor
    private func refresh() async {
        guard let cg = await BannerDocRenderer.composedImageAsync(doc) else {
            bannerImage = nil
            return
        }
        bannerImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
