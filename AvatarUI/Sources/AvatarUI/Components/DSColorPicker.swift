// DSColorPicker (E25.1) — herbruikbare kleurkiezer in de dark/lime-huisstijl.
// HSV-veld + hue-slider + alpha-slider (dambord) + eyedropper (NSColorSampler)
// + hex/opacity-velden + format-dropdown (Hex default). Zichtbare thumbs (les
// uit 24.11). Kleur live terug via de `color`-binding.
//
// API:
//   DSColorPicker(color: $color)                  // met alpha
//   DSColorPicker(color: $color, supportsAlpha: false)
//
// Figma-TODO: definitieve maatvoering/tints + RGB/HSL-formats (nu Hex actief,
// RGB/HSL staan als placeholder in de dropdown).

import AppKit
import SwiftUI

public struct DSColorPicker: View {
    @Binding private var color: Color
    private let supportsAlpha: Bool

    @State private var hue: Double = 0
    @State private var sat: Double = 1
    @State private var val: Double = 1
    @State private var alpha: Double = 1
    @State private var hexText: String = ""
    @State private var format: Format = .hex
    @State private var formatMenuOpen = false
    @State private var seeded = false

    public init(color: Binding<Color>, supportsAlpha: Bool = true) {
        self._color = color
        self.supportsAlpha = supportsAlpha
    }

    enum Format: String, CaseIterable, Identifiable { case hex = "Hex", rgb = "RGB", hsl = "HSL"; var id: String { rawValue } }

    private var current: Color { Color(hue: hue, saturation: sat, brightness: val, opacity: alpha) }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            svField
            hueSlider
            if supportsAlpha { alphaSlider }
            HStack(spacing: DSSpacing.gap2) {
                eyedropper
                formatMenu
                hexField
                if supportsAlpha { opacityField }
            }
        }
        .padding(DSSpacing.gap5)
        .frame(width: 300)
        .dsPanelSurface(cornerRadius: DSRadius.xl)
        .dsDropdownDismissOverlay(isPresented: $formatMenuOpen)
        .onAppear {
            guard !seeded else { return }
            seedFromColor(); seeded = true
        }
        .onChange(of: hue) { _, _ in push() }
        .onChange(of: sat) { _, _ in push() }
        .onChange(of: val) { _, _ in push() }
        .onChange(of: alpha) { _, _ in push() }
    }

    // MARK: - HSV-veld (saturation × value)

    private var svField: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Rectangle().fill(Color(hue: hue, saturation: 1, brightness: 1))
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.md).strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
            .overlay(thumb.position(x: sat * w, y: (1 - val) * h))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    sat = (v.location.x / max(1, w)).clamped01
                    val = (1 - v.location.y / max(1, h)).clamped01
                }
            )
        }
        .frame(height: 150)
    }

    // MARK: - Hue + alpha sliders

    private var hueSlider: some View {
        sliderTrack(
            background: LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map { Color(hue: $0, saturation: 1, brightness: 1) },
                startPoint: .leading, endPoint: .trailing
            ),
            position: hue,
            set: { hue = $0.clamped01 }
        )
    }

    private var alphaSlider: some View {
        sliderTrack(
            background: ZStack {
                Checkerboard()
                LinearGradient(colors: [current.opacity(0), current.opacity(1)], startPoint: .leading, endPoint: .trailing)
            },
            position: alpha,
            set: { alpha = $0.clamped01 }
        )
    }

    private func sliderTrack<BG: View>(background: BG, position: Double, set: @escaping (Double) -> Void) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            background
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
                .overlay(thumb.position(x: position * w, y: geo.size.height / 2))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in set(v.location.x / max(1, w)) })
        }
        .frame(height: 16)
    }

    /// Zichtbare thumb: witte ring met schaduw (24.11-les).
    private var thumb: some View {
        Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .allowsHitTesting(false)
    }

    // MARK: - Eyedropper / format / hex / opacity

    private var eyedropper: some View {
        Button {
            NSColorSampler().show { picked in
                guard let picked else { return }
                applyNSColor(picked)
            }
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: 30, height: 30)
                .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.md))
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DSRadius.md)
        .help("Pick a colour from the screen")
    }

    private var formatMenu: some View {
        DSDropdownButton(isPresented: $formatMenuOpen, anchorHeight: 30, minWidth: 100) {
            HStack(spacing: DSSpacing.gap1) {
                Text(format.rawValue).dsTextStyle(.labelSmall)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 30)
            .background(DSColor.Background.neutral, in: RoundedRectangle(cornerRadius: DSRadius.md))
        } menu: {
            ForEach(Format.allCases) { f in
                DSMenuRow(
                    f.rawValue,
                    icon: "number",
                    shortcut: f == format ? "✓" : nil
                ) {
                    format = f
                    formatMenuOpen = false
                }
            }
        }
        .fixedSize()
    }

    private var hexField: some View {
        DSTextField(label: nil, placeholder: "RRGGBB", text: $hexText)
            .frame(width: 86)
            .onSubmit { applyHex(hexText) }
    }

    private var opacityField: some View {
        Text("\(Int((alpha * 100).rounded()))%")
            .dsTextStyle(.labelSmall)
            .foregroundStyle(DSColor.Foreground.subtle)
            .frame(minWidth: 34)
    }

    // MARK: - Sync

    private func seedFromColor() {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h; sat = s; val = b; alpha = a
        hexText = hexString
    }

    private func push() {
        color = current
        hexText = hexString
    }

    private func applyNSColor(_ ns: NSColor) {
        guard let srgb = ns.usingColorSpace(.sRGB) else { return }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h; sat = s; val = b
        if supportsAlpha { alpha = a }
    }

    private func applyHex(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return }
        let ns = NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                         green: CGFloat((v >> 8) & 0xFF) / 255,
                         blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        applyNSColor(ns)
    }

    private var hexString: String {
        let ns = NSColor(current).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()),
                      Int((ns.blueComponent * 255).rounded()))
    }
}

/// Dambord-achtergrond voor de alpha-slider (transparantie zichtbaar maken).
private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 6
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = 0, col = 0
                while x < size.width {
                    if (row + col) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.45)))
                    }
                    x += s; col += 1
                }
                y += s; row += 1
            }
        }
    }
}
