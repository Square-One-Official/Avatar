// Board-view (E27.4 — SPIKE, read-only proof). Toont de hele set portretten als
// een scene-graph van kaart-nodes op één board, met de canvas-camera uit E27.1
// (scale + offset) eroverheen: pan (scroll/spatie-drag), zoom (pinch/⌘-scroll/
// ⌘±) over de héle set. Klik een portret → openen in de editor (selecteren).
//
// Dit is de SPIKE die de architectuur valideert (nodes + camera + klik-naar-
// edit). De volledige feature — sleepbare/persistente node-posities, multi-edit,
// inline bewerken zonder de board te verlaten — is fase 2 (zie de Result in
// plan/E27-canvas-viewport.md). De productie-editor-flow blijft ongemoeid; de
// board is enkel bereikbaar via de DEBUG-haak `--board`.

import AppKit
import AvatarUI
import SwiftData
import SwiftUI

struct BoardView: View {
    /// Dezelfde bron als de sidebar (E05.4): alle portretten, jongste eerst.
    @Query(sort: \Portrait2.updatedAt, order: .reverse) private var portraits: [Portrait2]
    /// Klik op een node → openen (selecteren) in de editor.
    let onOpen: (Portrait2) -> Void

    @State private var camera = CanvasCamera()
    @State private var lastMagnification: CGFloat = 1

    // Node-maat (board-space) — vaste kaart + labelstrook eronder.
    private let nodeSide: CGFloat = 220
    private let labelHeight: CGFloat = 40
    private let gap: CGFloat = 56

    private var columns: Int {
        max(1, Int(ceil(Double(portraits.count).squareRoot())))
    }

    var body: some View {
        ZStack {
            DSColor.Background.app.ignoresSafeArea()

            if portraits.isEmpty {
                Text("No portraits yet")
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(DSColor.Foreground.muted)
            } else {
                board
                    .scaleEffect(camera.scale, anchor: .center)
                    .offset(camera.offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background {
                        CanvasInteractionCatcher(camera: $camera)
                        boardShortcutButtons
                    }
                    .simultaneousGesture(pinch)
            }

            // Hint + fit-knop, screen-space (net als de zoom-HUD in 27.2).
            VStack {
                Spacer()
                HStack {
                    Text("Board (spike) · \(portraits.count) portraits — click to edit")
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                    Spacer()
                    Button("Fit") { withAnimation(.spring(duration: 0.3)) { camera.reset() } }
                        .buttonStyle(.plain)
                        .dsTextStyle(.labelSmall)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .padding(.horizontal, DSSpacing.gap3)
                        .frame(height: 30)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
                }
                .padding(DSSpacing.gap4)
            }
        }
    }

    private var board: some View {
        let cols = Array(repeating: GridItem(.fixed(nodeSide), spacing: gap), count: columns)
        return LazyVGrid(columns: cols, spacing: gap) {
            ForEach(portraits) { portrait in
                node(portrait)
            }
        }
        .padding(gap)
    }

    private func node(_ portrait: Portrait2) -> some View {
        Button { onOpen(portrait) } label: {
            VStack(spacing: DSSpacing.gap2) {
                cardSurface(portrait)
                    .frame(width: nodeSide, height: nodeSide)
                VStack(spacing: 2) {
                    Text(portrait.name.isEmpty ? "Untitled" : portrait.name)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .lineLimit(1)
                    if !portrait.role.isEmpty {
                        Text(portrait.role)
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                            .lineLimit(1)
                    }
                }
                .frame(height: labelHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsHoverHighlight(cornerRadius: DSRadius.xl4)
    }

    /// Kaart-surface met het cutout-beeld, geclipt tot de frame-vorm — een mini-
    /// versie van DSCanvasCard (zonder de transform-machinerie).
    @ViewBuilder
    private func cardSurface(_ portrait: Portrait2) -> some View {
        let clip: AnyShape = portrait.frameShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: DSRadius.xl4))
        ZStack {
            DSColor.Background.card
            if let image = NSImage(data: portrait.cutoutData) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(nodeSide * 0.08)
            }
        }
        .clipShape(clip)
        .overlay(clip.stroke(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin))
    }

    // E27.1-camera: pinch om het midden (zelfde patroon als EditorView).
    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / max(0.0001, lastMagnification)
                lastMagnification = value
                camera.zoomCentered(by: delta)
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    @ViewBuilder
    private var boardShortcutButtons: some View {
        Group {
            Button("") { zoom(1.25) }.keyboardShortcut("+", modifiers: .command)
            Button("") { zoom(1.25) }.keyboardShortcut("=", modifiers: .command)
            Button("") { zoom(0.8) }.keyboardShortcut("-", modifiers: .command)
            Button("") { withAnimation(.spring(duration: 0.3)) { camera.reset() } }
                .keyboardShortcut("0", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func zoom(_ factor: CGFloat) {
        withAnimation(.spring(duration: 0.25)) { camera.zoomCentered(by: factor) }
    }
}
