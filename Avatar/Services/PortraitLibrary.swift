import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

/// Library-level import/delete used by the menu bar, Delete key, and
/// context menus so every path shares the same panel, free-tier gate,
/// and undo registration.
@MainActor
enum PortraitLibrary {

    // MARK: - Import

    static func importFromOpenPanel(context: ModelContext, appState: AppState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let allowed = FreeTierGate.allowedImportCount(
            requested: panel.urls.count,
            appState: appState
        )
        guard allowed > 0 else { return }
        for url in panel.urls.shuffled().prefix(allowed) {
            ImportFlow.importFile(url: url, context: context, appState: appState)
        }
    }

    // MARK: - Delete + undo

    static func delete(
        _ portraits: [Portrait],
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager?
    ) {
        guard !portraits.isEmpty else { return }
        let records = portraits.map(Record.init)
        let previousSelection = appState.selectedPortraitIDs
        applyDelete(portraits, context: context, appState: appState)

        guard let um = undoManager else { return }
        um.registerUndo(withTarget: context) { ctx in
            restore(
                records,
                previousSelection: previousSelection,
                context: ctx,
                appState: appState,
                undoManager: um
            )
        }
        um.setActionName(actionName(count: records.count))
    }

    private static func applyDelete(
        _ portraits: [Portrait],
        context: ModelContext,
        appState: AppState
    ) {
        let ids = Set(portraits.map(\.id))
        PortraitSpotlight.remove(ids: Array(ids))
        for p in portraits {
            appState.invalidateCutout(for: p)
            context.delete(p)
        }
        appState.selectedPortraitIDs.subtract(ids)
        try? context.save()
    }

    private static func restore(
        _ records: [Record],
        previousSelection: Set<UUID>,
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager
    ) {
        var restored: [Portrait] = []
        restored.reserveCapacity(records.count)
        for record in records {
            let portrait = record.makePortrait()
            context.insert(portrait)
            PortraitSpotlight.index(portrait)
            restored.append(portrait)
        }
        appState.selectedPortraitIDs = previousSelection
        try? context.save()

        undoManager.registerUndo(withTarget: context) { ctx in
            delete(restored, context: ctx, appState: appState, undoManager: undoManager)
        }
        undoManager.setActionName(actionName(count: records.count))
    }

    private static func actionName(count: Int) -> String {
        count > 1
            ? "\(Loc.delete) \(count) \(Loc.portraitsPlural)"
            : Loc.delete
    }

    // MARK: - Snapshot

    /// Full field copy so Cmd+Z can re-insert a deleted portrait, including
    /// externally stored PNG blobs.
    struct Record {
        let id: UUID
        let name: String
        let tags: String
        let createdAt: Date
        let updatedAt: Date
        let originalImageData: Data?
        let cutoutPNG: Data?
        let faceRectX: Double
        let faceRectY: Double
        let faceRectW: Double
        let faceRectH: Double
        let eyeCenterX: Double
        let eyeCenterY: Double
        let interEyeDistance: Double
        let bodyBottomY: Double
        let offsetX: Double
        let offsetY: Double
        let scale: Double
        let backgroundPresetID: UUID?
        let adjExposure: Double
        let adjContrast: Double
        let adjBrightness: Double
        let adjSaturation: Double
        let adjHue: Double
        let adjTemperature: Double
        let adjTint: Double
        let adjHighlights: Double
        let adjShadows: Double
        let adjWhites: Double
        let adjBlacks: Double
        let isMagicRetouched: Bool
        let preRetouchPNG: Data?
        let cutoutUsedMagic: Bool
        let isFillBodyApplied: Bool
        let preFillBodyPNG: Data?
        let preFillFaceRectX: Double
        let preFillFaceRectY: Double
        let preFillFaceRectW: Double
        let preFillFaceRectH: Double
        let preFillEyeCenterX: Double
        let preFillEyeCenterY: Double
        let preFillInterEyeDistance: Double
        let preFillBodyBottomY: Double
        let preFillOffsetX: Double
        let preFillOffsetY: Double
        let preFillScale: Double
        let isColorized: Bool
        let preColorizePNG: Data?

        init(_ p: Portrait) {
            id = p.id
            name = p.name
            tags = p.tags
            createdAt = p.createdAt
            updatedAt = p.updatedAt
            originalImageData = p.originalImageData
            cutoutPNG = p.cutoutPNG
            faceRectX = p.faceRectX
            faceRectY = p.faceRectY
            faceRectW = p.faceRectW
            faceRectH = p.faceRectH
            eyeCenterX = p.eyeCenterX
            eyeCenterY = p.eyeCenterY
            interEyeDistance = p.interEyeDistance
            bodyBottomY = p.bodyBottomY
            offsetX = p.offsetX
            offsetY = p.offsetY
            scale = p.scale
            backgroundPresetID = p.backgroundPresetID
            adjExposure = p.adjExposure
            adjContrast = p.adjContrast
            adjBrightness = p.adjBrightness
            adjSaturation = p.adjSaturation
            adjHue = p.adjHue
            adjTemperature = p.adjTemperature
            adjTint = p.adjTint
            adjHighlights = p.adjHighlights
            adjShadows = p.adjShadows
            adjWhites = p.adjWhites
            adjBlacks = p.adjBlacks
            isMagicRetouched = p.isMagicRetouched
            preRetouchPNG = p.preRetouchPNG
            cutoutUsedMagic = p.cutoutUsedMagic
            isFillBodyApplied = p.isFillBodyApplied
            preFillBodyPNG = p.preFillBodyPNG
            preFillFaceRectX = p.preFillFaceRectX
            preFillFaceRectY = p.preFillFaceRectY
            preFillFaceRectW = p.preFillFaceRectW
            preFillFaceRectH = p.preFillFaceRectH
            preFillEyeCenterX = p.preFillEyeCenterX
            preFillEyeCenterY = p.preFillEyeCenterY
            preFillInterEyeDistance = p.preFillInterEyeDistance
            preFillBodyBottomY = p.preFillBodyBottomY
            preFillOffsetX = p.preFillOffsetX
            preFillOffsetY = p.preFillOffsetY
            preFillScale = p.preFillScale
            isColorized = p.isColorized
            preColorizePNG = p.preColorizePNG
        }

        func makePortrait() -> Portrait {
            let p = Portrait(
                id: id,
                name: name,
                tags: tags,
                cutoutPNG: cutoutPNG,
                originalImageData: originalImageData,
                faceRect: CGRect(x: faceRectX, y: faceRectY, width: faceRectW, height: faceRectH),
                eyeCenter: interEyeDistance > 0 ? CGPoint(x: eyeCenterX, y: eyeCenterY) : nil,
                interEyeDistance: interEyeDistance,
                bodyBottomY: bodyBottomY,
                offsetX: offsetX,
                offsetY: offsetY,
                scale: scale,
                backgroundPresetID: backgroundPresetID
            )
            p.createdAt = createdAt
            p.updatedAt = updatedAt
            p.adjExposure = adjExposure
            p.adjContrast = adjContrast
            p.adjBrightness = adjBrightness
            p.adjSaturation = adjSaturation
            p.adjHue = adjHue
            p.adjTemperature = adjTemperature
            p.adjTint = adjTint
            p.adjHighlights = adjHighlights
            p.adjShadows = adjShadows
            p.adjWhites = adjWhites
            p.adjBlacks = adjBlacks
            p.isMagicRetouched = isMagicRetouched
            p.preRetouchPNG = preRetouchPNG
            p.cutoutUsedMagic = cutoutUsedMagic
            p.isFillBodyApplied = isFillBodyApplied
            p.preFillBodyPNG = preFillBodyPNG
            p.preFillFaceRectX = preFillFaceRectX
            p.preFillFaceRectY = preFillFaceRectY
            p.preFillFaceRectW = preFillFaceRectW
            p.preFillFaceRectH = preFillFaceRectH
            p.preFillEyeCenterX = preFillEyeCenterX
            p.preFillEyeCenterY = preFillEyeCenterY
            p.preFillInterEyeDistance = preFillInterEyeDistance
            p.preFillBodyBottomY = preFillBodyBottomY
            p.preFillOffsetX = preFillOffsetX
            p.preFillOffsetY = preFillOffsetY
            p.preFillScale = preFillScale
            p.isColorized = isColorized
            p.preColorizePNG = preColorizePNG
            return p
        }
    }
}
