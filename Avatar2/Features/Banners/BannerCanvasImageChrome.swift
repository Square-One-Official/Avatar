// E37.14 — Freeform-stijl logo-chrome: blauwe rand, hoek-handles, floating toolbar.

import AppKit
import AvatarUI
import SwiftUI

struct BannerCanvasImageChrome: View {
    @Bindable var doc: BannerDoc
    @Binding var selection: Set<BannerElementRef>
    let activeTool: BannerTool?
    var presentation: UIPresentationStore
    let canvasSize: CGSize
    let layout: BannerCanvasChromeMetrics.Layout
    let undoManager: UndoManager?
    let filename: String
    var onReplace: () -> Void

    @State private var scaleDragStart: Double?
    @State private var scaleDragStartDistance: CGFloat?
    @State private var layersBeforeScale: BannerLayers?
    @State private var toolbarMenuOpen = false
    @State private var toolbarMenuDismissNonce = 0

    var body: some View {
        if selection.contains(.logo),
           let logo = doc.layers.logo,
           let data = doc.logoImageData,
           let cg = BannerDocRenderer.cgImage(from: data) {
            let rect = BannerCanvasChromeMetrics.screenRect(
                canvasRect: BannerLayoutMetrics.logoRect(layer: logo, logoImage: cg, canvas: canvasSize),
                layout: layout
            )
            ZStack {
                if toolbarMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toolbarMenuDismissNonce += 1 }
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)

                cornerHandle(at: CGPoint(x: rect.minX, y: rect.minY), rect: rect)
                cornerHandle(at: CGPoint(x: rect.maxX, y: rect.minY), rect: rect)
                cornerHandle(at: CGPoint(x: rect.minX, y: rect.maxY), rect: rect)
                cornerHandle(at: CGPoint(x: rect.maxX, y: rect.maxY), rect: rect)

                BannerImageFloatingToolbar(
                    kind: .logo,
                    presentation: presentation,
                    filename: filename,
                    byteCount: data.count,
                    imageData: data,
                    onReplace: onReplace,
                    onRemove: removeLogo,
                    menuDismissNonce: toolbarMenuDismissNonce,
                    onMenusOpenChange: { toolbarMenuOpen = $0 }
                )
                .fixedSize()
                .position(x: rect.midX, y: rect.maxY + 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cornerHandle(at point: CGPoint, rect: CGRect) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .position(x: point.x, y: point.y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if scaleDragStart == nil {
                            scaleDragStart = doc.layers.logo?.scale ?? 0.25
                            scaleDragStartDistance = distanceFromCenter(
                                point: value.startLocation,
                                rect: rect
                            )
                            layersBeforeScale = doc.layers
                        }
                        guard let startScale = scaleDragStart,
                              let startDist = scaleDragStartDistance,
                              startDist > 4 else { return }
                        let dist = distanceFromCenter(point: value.location, rect: rect)
                        let factor = max(0.08, min(0.85, startScale * Double(dist / startDist)))
                        setLogoScale(factor)
                    }
                    .onEnded { _ in
                        if let before = layersBeforeScale, before != doc.layers {
                            BannerDocUndo.registerLayers(
                                undoManager, doc: doc, from: before, to: doc.layers, actionName: "Scale logo"
                            )
                        }
                        scaleDragStart = nil
                        scaleDragStartDistance = nil
                        layersBeforeScale = nil
                    }
            )
    }

    private func distanceFromCenter(point: CGPoint, rect: CGRect) -> CGFloat {
        hypot(point.x - rect.midX, point.y - rect.midY)
    }

    private func setLogoScale(_ scale: Double) {
        var layers = doc.layers
        guard layers.logo != nil else { return }
        layers.logo?.scale = scale
        doc.layers = layers
    }

    private func removeLogo() {
        let before = BannerDocUndo.snapshot(of: doc)
        doc.logoImageData = nil
        var layers = doc.layers
        layers.logo = nil
        doc.layers = layers
        let after = BannerDocUndo.snapshot(of: doc)
        BannerDocUndo.registerDocument(undoManager, doc: doc, from: before, to: after, actionName: "Remove logo")
        selection.remove(.logo)
    }
}
