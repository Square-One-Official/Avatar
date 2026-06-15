// Zwevende zoom-HUD (E27.2) — de viewport-zoomregelaar voor de canvas-camera
// (E27.1). Eén capsule in DS-stijl (ultraThinMaterial + divider-rand, gelijk
// aan de CanvasActionToolbar): − / slider / + en een fit-knop die het huidige
// zoom-% toont. De slider loopt LOGARITMISCH tussen min en max, zodat 100%
// (de fit-schaal) precies in het midden valt.
//
// De HUD is puur presentational: schaal in, callbacks uit. De camera-math
// (clamp, zoom-rond-midden) leeft in CanvasCamera/EditorView (FEAT).

import Foundation
import SwiftUI

public struct DSZoomHUD: View {
    private let scale: CGFloat
    private let minScale: CGFloat
    private let maxScale: CGFloat
    private let onSetScale: (CGFloat) -> Void
    private let onZoomIn: () -> Void
    private let onZoomOut: () -> Void
    private let onFit: () -> Void

    public init(
        scale: CGFloat,
        minScale: CGFloat,
        maxScale: CGFloat,
        onSetScale: @escaping (CGFloat) -> Void,
        onZoomIn: @escaping () -> Void,
        onZoomOut: @escaping () -> Void,
        onFit: @escaping () -> Void
    ) {
        self.scale = scale
        self.minScale = minScale
        self.maxScale = maxScale
        self.onSetScale = onSetScale
        self.onZoomIn = onZoomIn
        self.onZoomOut = onZoomOut
        self.onFit = onFit
    }

    private var percent: Int { Int((scale * 100).rounded()) }
    private var atMin: Bool { scale <= minScale + 0.0001 }
    private var atMax: Bool { scale >= maxScale - 0.0001 }

    /// Logaritmische slider-positie (0…1): t = log(s/min) / log(max/min), zodat
    /// gelijke slider-stappen gelijke zoom-verhoudingen geven en 100% (=√(min·max)
    /// bij min·max = 1) in het midden ligt.
    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                let lo = Double(minScale), hi = Double(maxScale)
                let t = log(Double(scale) / lo) / log(hi / lo)
                return min(1, max(0, t))
            },
            set: { t in
                let lo = Double(minScale), hi = Double(maxScale)
                onSetScale(CGFloat(lo * pow(hi / lo, min(1, max(0, t)))))
            }
        )
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap1) {
            stepButton("minus", help: "Zoom out (⌘−)", action: onZoomOut)
                .disabled(atMin)
                .opacity(atMin ? 0.4 : 1)

            Slider(value: sliderBinding, in: 0...1)
                .controlSize(.small)
                .tint(DSColor.Action.primary)
                .frame(width: 116)

            stepButton("plus", help: "Zoom in (⌘+)", action: onZoomIn)
                .disabled(atMax)
                .opacity(atMax ? 0.4 : 1)

            Divider().frame(height: 16).overlay(DSColor.Foreground.divider)

            // Fit-knop die tegelijk het huidige zoom-% toont (⌘0). Vaste breedte
            // + monospaced cijfers zodat de capsule niet verspringt bij 50/400%.
            Button(action: onFit) {
                Text("\(percent)%")
                    .dsTextStyle(.labelSmall)
                    .monospacedDigit()
                    .foregroundStyle(DSColor.Foreground.primary)
                    .frame(width: 44)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .dsHoverHighlight(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .help("Fit (⌘0)")
        }
        .padding(.horizontal, DSSpacing.gap1)
        .padding(.vertical, DSSpacing.gap1)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
        .animation(.easeOut(duration: 0.14), value: scale)
    }

    private func stepButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DSColor.Foreground.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .dsHoverHighlight(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
