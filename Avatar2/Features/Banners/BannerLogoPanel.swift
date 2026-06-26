// E37.5 — Logo/Brand-paneel van de Banner Studio. Plaatst een logo/merkbeeld
// (upload PNG met alpha → schalen + positioneren + verwijderen) en beheert het
// brand-kleurenpalet (`BrandColorKit`, gedeeld met Background/Text). Mutaties via
// `BannerDoc.layers.logo`/`logoImageData` → `touch()` → live canvas-her-render.

import AppKit
import AvatarUI
import SwiftUI

struct BannerLogoPanel: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: BannerCanvasSelection?
    var subtitle: String?

    @State private var brand = BrandColorKit.shared
    @State private var showBrandColorPicker = false
    @State private var pickerColor: Color = .white

    private let swatch: CGFloat = 28

    var body: some View {
        DSEditPanel(title: "Logo & brand", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: DSSpacing.gap4) {
                logoSection
                brandSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Logo

    @ViewBuilder private var logoSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text("Logo").dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
            if let data = doc.logoImageData, let img = NSImage(data: data), doc.layers.logo != nil {
                HStack(spacing: DSSpacing.gap3) {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                        .frame(width: 56, height: 40)
                        .background(RoundedRectangle(cornerRadius: DSRadius.md).fill(DSColor.Background.inset))
                    VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                        HStack(spacing: DSSpacing.gap1) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11)).foregroundStyle(DSColor.Foreground.muted)
                            Slider(value: scaleBinding, in: 0.08...0.6).frame(width: 120)
                        }
                        positionGrid
                    }
                    Spacer(minLength: 0)
                    Button { removeLogo() } label: {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(DSColor.Foreground.muted)
                    }
                    .buttonStyle(.plain).help("Remove logo")
                }
            } else {
                DSNeutralButton("Add logo") { addLogo() }
            }
        }
    }

    /// 3×3 plaatsings-grid (hoeken/midden) voor het logo.
    private var positionGrid: some View {
        let xs: [Double] = [0.12, 0.5, 0.88]
        let ys: [Double] = [0.16, 0.5, 0.84]
        return VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { col in
                        let x = xs[col], y = ys[row]
                        let selected = isLogoAt(x: x, y: y)
                        Button { setLogo { $0.x = x; $0.y = y } } label: {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(selected ? DSColor.Action.primary : DSColor.Foreground.divider)
                                .frame(width: 14, height: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Brand colors

    @ViewBuilder private var brandSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap2) {
            Text("Brand colors").dsTextStyle(.labelSmall).foregroundStyle(DSColor.Foreground.muted)
            HStack(spacing: DSSpacing.gap2) {
                Button { showBrandColorPicker = true } label: {
                    Circle()
                        .fill(DSColor.Background.neutral)
                        .frame(width: swatch, height: swatch)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DSColor.Foreground.subtle)
                        }
                }
                .buttonStyle(.plain)
                .dsHoverScale()
                .help("Add brand colour")
                .popover(isPresented: $showBrandColorPicker, arrowEdge: .bottom) {
                    DSColorPicker(color: $pickerColor, supportsAlpha: false)
                        .appliedAppearancePreference()
                }

                ForEach(brand.hexColors, id: \.self) { hex in
                    if let color = Color(hexRGB: hex) {
                        Circle()
                            .fill(color)
                            .frame(width: swatch, height: swatch)
                            .overlay(Circle().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
                            .help("\(hex) — manage in Settings › Manage backgrounds")
                    }
                }
                if brand.hexColors.isEmpty {
                    Text("Add brand colors with the picker.")
                        .dsTextStyle(.bodySmall).foregroundStyle(DSColor.Foreground.muted)
                }
            }
            .onChange(of: pickerColor) { _, c in
                guard showBrandColorPicker, let hex = c.hexRGB else { return }
                brand.add(hex)
            }
        }
    }

    // MARK: State + mutaties

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { doc.layers.logo?.scale ?? 0.25 },
            set: { v in setLogo { $0.scale = v } }
        )
    }

    private func isLogoAt(x: Double, y: Double) -> Bool {
        guard let logo = doc.layers.logo else { return false }
        return abs(logo.x - x) < 0.02 && abs(logo.y - y) < 0.02
    }

    private func setLogo(_ mutate: (inout BannerLogoLayer) -> Void) {
        var layers = doc.layers
        var logo = layers.logo ?? BannerLogoLayer()
        mutate(&logo)
        layers.logo = logo
        doc.layers = layers
    }

    private func addLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else { return }
        let png = BackgroundKit.downscaledPNG(raw, maxSide: 1024) ?? raw
        doc.logoImageData = png
        var layers = doc.layers
        layers.logo = BannerLogoLayer(x: 0.5, y: 0.5, scale: 0.25)
        doc.layers = layers
        selection = .logo
    }

    private func removeLogo() {
        doc.logoImageData = nil
        var layers = doc.layers
        layers.logo = nil
        doc.layers = layers
        if selection == .logo { selection = nil }
    }
}
