// E37.10 — Undo voor Banner Studio via de gedeelde ReversibleChange-motor.

import Foundation

enum BannerDocUndo {
    struct LayersSnapshot: Equatable {
        var layers: BannerLayers
    }

    struct DocumentSnapshot: Equatable {
        var layers: BannerLayers
        var fillImageFocalX: Double
        var fillImageFocalY: Double
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
            doc.layers = snap.layers
            doc.fillImageFocalX = snap.fillImageFocalX
            doc.fillImageFocalY = snap.fillImageFocalY
        }
    }

    static func snapshot(of doc: BannerDoc) -> DocumentSnapshot {
        DocumentSnapshot(
            layers: doc.layers,
            fillImageFocalX: doc.fillImageFocalX,
            fillImageFocalY: doc.fillImageFocalY
        )
    }
}
