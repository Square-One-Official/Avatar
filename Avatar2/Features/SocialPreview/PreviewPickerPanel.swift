// Zwevende kiezer-panelen in de social-preview — gedeelde chrome (scrim +
// dsPanelSurface-kaart) voor portret- en banner-kiezers. Geankerd aan een
// CGRect in de preview-coordinate-space (zelfde patroon als DSContextMenuOverlay).

import AvatarUI
import SwiftUI

enum PreviewPicker: Equatable {
    case portrait(anchor: CGRect)
    case banner(anchor: CGRect, platform: SocialPlatform)
}

struct PreviewPickerPanel<Content: View, Footer: View>: View {
    let anchor: CGRect
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    private let panelWidth: CGFloat = 320
    private let maxPanelHeight: CGFloat = 360

    init(
        anchor: CGRect,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.anchor = anchor
        self.onDismiss = onDismiss
        self.content = content
        self.footer = footer
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        content()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: maxPanelHeight - footerHeightEstimate)

                    footer()
                }
                .padding(DSSpacing.gap3)
                .frame(width: panelWidth, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .dsPanelSurface(cornerRadius: DSRadius.xl4)
                .offset(x: clampedX(in: geo.size), y: clampedY(in: geo.size))
            }
        }
    }

    private var footerHeightEstimate: CGFloat { 72 }

    private func clampedX(in size: CGSize) -> CGFloat {
        let pad = DSSpacing.gap2
        return min(max(anchor.midX - panelWidth / 2, pad), max(pad, size.width - panelWidth - pad))
    }

    private func clampedY(in size: CGSize) -> CGFloat {
        let pad = DSSpacing.gap2
        let baseY = anchor.height > 0 ? anchor.maxY : anchor.minY
        return min(max(baseY + pad, pad), max(pad, size.height - maxPanelHeight - pad))
    }
}

// MARK: - Tap target (mockup avatar / banner)

enum PreviewTapHoverShape {
    case circle
    case rectangle
}

struct PreviewTapTarget: ViewModifier {
    let coordinateSpace: CoordinateSpace
    let enabled: Bool
    var hoverShape: PreviewTapHoverShape = .circle
    let onTap: (CGRect) -> Void

    @State private var bounds: CGRect = .zero
    @State private var hovering = false

    func body(content: Content) -> some View {
        Button {
            guard enabled else { return }
            onTap(bounds)
        } label: {
            content
                .overlay {
                    if enabled && hovering {
                        hoverOverlay
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = enabled && $0 }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: coordinateSpace), initial: true) { _, frame in
                        bounds = frame
                    }
            }
        }
    }

    @ViewBuilder
    private var hoverOverlay: some View {
        switch hoverShape {
        case .circle:
            Circle()
                .strokeBorder(DSColor.Action.primary.opacity(0.55), lineWidth: 2)
        case .rectangle:
            ZStack {
                Rectangle()
                    .fill(DSColor.Action.primary.opacity(0.08))
                Rectangle()
                    .strokeBorder(DSColor.Action.primary.opacity(0.55), lineWidth: 2)
            }
        }
    }
}

extension View {
    func previewTapTarget(
        in coordinateSpace: CoordinateSpace,
        enabled: Bool = true,
        hoverShape: PreviewTapHoverShape = .circle,
        onTap: @escaping (CGRect) -> Void
    ) -> some View {
        modifier(
            PreviewTapTarget(
                coordinateSpace: coordinateSpace,
                enabled: enabled,
                hoverShape: hoverShape,
                onTap: onTap
            )
        )
    }
}
