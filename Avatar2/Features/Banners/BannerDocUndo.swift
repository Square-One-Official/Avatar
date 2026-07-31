// E37.10 — Undo voor Banner Studio via de gedeelde ReversibleChange-motor.

import Foundation

enum BannerDocUndo {
    struct LayersSnapshot: Equatable {
        var layers: BannerLayers
    }

    /// Volledige document-snapshot incl. image-bytes (logo/background replace).
    struct DocumentSnapshot: Equatable {
        var layers: BannerLayers
        var fillImageFocalX: Double
        var fillImageFocalY: Double
        var fillImageZoom: Double
        var fillImageData: Data?
        var logoImageData: Data?
    }

    @MainActor
    static func registerLayers(
        _ undoManager: UndoManager?,
        doc: BannerDoc,
        from before: BannerLayers,
        to after: BannerLayers,
        actionName: String = "Move"
    ) {
        guard before != after else { return }
        ReversibleChange.register(undoManager, target: doc, from: before, to: after, actionName: actionName) { doc, layers in
            doc.layers = layers
        }
    }

    @MainActor
    static func registerDocument(
        _ undoManager: UndoManager?,
        doc: BannerDoc,
        from before: DocumentSnapshot,
        to after: DocumentSnapshot,
        actionName: String = "Edit banner"
    ) {
        guard before != after else { return }
        ReversibleChange.register(undoManager, target: doc, from: before, to: after, actionName: actionName) { doc, snap in
            apply(snap, to: doc)
        }
    }

    static func snapshot(of doc: BannerDoc) -> DocumentSnapshot {
        DocumentSnapshot(
            layers: doc.layers,
            fillImageFocalX: doc.fillImageFocalX,
            fillImageFocalY: doc.fillImageFocalY,
            fillImageZoom: doc.fillImageZoom,
            fillImageData: doc.fillImageData,
            logoImageData: doc.logoImageData
        )
    }

    static func apply(_ snap: DocumentSnapshot, to doc: BannerDoc) {
        doc.layers = snap.layers
        doc.fillImageFocalX = snap.fillImageFocalX
        doc.fillImageFocalY = snap.fillImageFocalY
        doc.fillImageZoom = snap.fillImageZoom
        doc.fillImageData = snap.fillImageData
        doc.logoImageData = snap.logoImageData
    }
}
