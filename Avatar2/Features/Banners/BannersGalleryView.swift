// Banners-bibliotheek (E35.3). Beheer van herbruikbare, WIJDE banners: upload een
// beeld of maak er één uit een gradient-preset; hernoem/verwijder via het
// rechtsklikmenu. De preview (social) kiest hieruit. Geen design-canvas — een
// banner is gewoon één wijd beeld (besluit Thierry 2026-06-25).

import AppKit
import AvatarKit
import AvatarUI
import SwiftData
import SwiftUI

struct BannersGalleryView: View {
    let model: ShellModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Banner2.updatedAt, order: .reverse) private var banners: [Banner2]

    /// Canonieke render-maat voor preset-banners (wijd; per platform aspect-fill'd).
    private static let presetSize = CGSize(width: 1600, height: 500)

    @State private var renaming: Banner2?
    @State private var draftName = ""

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: DSSpacing.gap4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.gap6) {
                header
                presetsRow
                if banners.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.gap4) {
                        ForEach(banners) { banner in
                            tile(banner)
                        }
                    }
                }
            }
            .padding(DSSpacing.gap8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Rename banner", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Banner name", text: $draftName)
            Button("Save") {
                if let b = renaming, !draftName.trimmingCharacters(in: .whitespaces).isEmpty {
                    b.name = draftName; b.touch()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Header + create

    private var header: some View {
        HStack {
            Text("Banners").dsTextStyle(.h3).foregroundStyle(DSColor.Foreground.primary)
            Spacer()
            DSPrimaryButton("Upload banner") { uploadBanner() }
        }
    }

    /// Snel-maken uit gradient-presets (instant content; klik = nieuwe banner).
    private var presetsRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text("Start from a gradient")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.gap2) {
                    ForEach(Array(BackgroundKit.gradientPresets.enumerated()), id: \.offset) { _, colors in
                        Button { addGradient(colors) } label: {
                            RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous)
                                .fill(BackgroundKit.gradient(colors))
                                .frame(width: 120, height: 40)
                        }
                        .buttonStyle(.plain)
                        .dsHoverScale()
                    }
                }
                .padding(.vertical, DSSpacing.gap1)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text("No banners yet")
                .dsTextStyle(.h3)
                .foregroundStyle(DSColor.Foreground.primary)
            Text("Upload a wide image or start from a gradient. Your banners show up in the social preview, behind the profile picture.")
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DSSpacing.gap8)
    }

    // MARK: Tile

    private func tile(_ banner: Banner2) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous)
                .fill(DSColor.Background.inset)
                .aspectRatio(1500.0 / 500.0, contentMode: .fit)
                .overlay {
                    if let img = NSImage(data: banner.imageData) {
                        Image(nsImage: img).resizable().scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl, style: .continuous))
            Text(banner.name.isEmpty ? "Untitled banner" : banner.name)
                .dsTextStyle(.labelBase)
                .foregroundStyle(DSColor.Foreground.subtle)
                .lineLimit(1)
        }
        .contextMenu {
            Button("Rename") { draftName = banner.name; renaming = banner }
            Button("Delete", role: .destructive) { modelContext.delete(banner) }
        }
    }

    // MARK: Acties

    private func uploadBanner() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        insert(imageData: data, name: url.deletingPathExtension().lastPathComponent)
    }

    private func addGradient(_ colors: [Color]) {
        guard let gpng = BackgroundKit.renderGradientPNG(colors),
              let cg = NSImage(data: gpng)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let wide = try? BannerCompositor.composite(fill: .image(cg), size: Self.presetSize),
              let data = NSBitmapImageRep(cgImage: wide).representation(using: .png, properties: [:])
        else { return }
        insert(imageData: data, name: "Gradient banner")
    }

    private func insert(imageData: Data, name: String) {
        let banner = Banner2(name: name, imageData: imageData)
        modelContext.insert(banner)
    }
}
