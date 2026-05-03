import Foundation
import SwiftData

/// Captures a full snapshot of all undoable portrait properties so that
/// any single edit (drag, scale, adjustment slider, background change, etc.)
/// can be reverted with ⌘Z and re-applied with ⌘⇧Z.
///
/// Usage:
///   1. Call `beginChange(for:undoManager:actionName:)` **before** mutating.
///   2. Mutate the portrait properties + call `context.save()`.
///   The undo step is registered automatically.
@MainActor
enum PortraitUndoManager {

    // MARK: - Snapshot

    struct Snapshot {
        let id: UUID
        // Transform
        let offsetX: Double
        let offsetY: Double
        let scale: Double
        // Background
        let backgroundPresetID: UUID?
        // Adjustments
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
        // Cutout + landmarks (mutated by Magic Retouch / Fill in Body)
        let cutoutPNG: Data?
        let faceRectX: Double
        let faceRectY: Double
        let faceRectW: Double
        let faceRectH: Double
        let eyeCenterX: Double
        let eyeCenterY: Double
        let interEyeDistance: Double
        let bodyBottomY: Double
        // Magic Retouch
        let isMagicRetouched: Bool
        let preRetouchPNG: Data?
        // Fill in Body
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
        // Colorise
        let isColorized: Bool
        let preColorizePNG: Data?
        // Metadata
        let name: String
        let tags: String
        let updatedAt: Date
    }

    static func snapshot(of p: Portrait) -> Snapshot {
        Snapshot(
            id: p.id,
            offsetX: p.offsetX,
            offsetY: p.offsetY,
            scale: p.scale,
            backgroundPresetID: p.backgroundPresetID,
            adjExposure: p.adjExposure,
            adjContrast: p.adjContrast,
            adjBrightness: p.adjBrightness,
            adjSaturation: p.adjSaturation,
            adjHue: p.adjHue,
            adjTemperature: p.adjTemperature,
            adjTint: p.adjTint,
            adjHighlights: p.adjHighlights,
            adjShadows: p.adjShadows,
            adjWhites: p.adjWhites,
            adjBlacks: p.adjBlacks,
            cutoutPNG: p.cutoutPNG,
            faceRectX: p.faceRectX,
            faceRectY: p.faceRectY,
            faceRectW: p.faceRectW,
            faceRectH: p.faceRectH,
            eyeCenterX: p.eyeCenterX,
            eyeCenterY: p.eyeCenterY,
            interEyeDistance: p.interEyeDistance,
            bodyBottomY: p.bodyBottomY,
            isMagicRetouched: p.isMagicRetouched,
            preRetouchPNG: p.preRetouchPNG,
            isFillBodyApplied: p.isFillBodyApplied,
            preFillBodyPNG: p.preFillBodyPNG,
            preFillFaceRectX: p.preFillFaceRectX,
            preFillFaceRectY: p.preFillFaceRectY,
            preFillFaceRectW: p.preFillFaceRectW,
            preFillFaceRectH: p.preFillFaceRectH,
            preFillEyeCenterX: p.preFillEyeCenterX,
            preFillEyeCenterY: p.preFillEyeCenterY,
            preFillInterEyeDistance: p.preFillInterEyeDistance,
            preFillBodyBottomY: p.preFillBodyBottomY,
            preFillOffsetX: p.preFillOffsetX,
            preFillOffsetY: p.preFillOffsetY,
            preFillScale: p.preFillScale,
            isColorized: p.isColorized,
            preColorizePNG: p.preColorizePNG,
            name: p.name,
            tags: p.tags,
            updatedAt: p.updatedAt
        )
    }

    // MARK: - Public API

    /// Take a snapshot of the current state. Call this **before** you change
    /// anything. After you mutate the portrait and save, the undo step is
    /// registered automatically from the captured "before" state.
    static func beginChange(
        for portrait: Portrait,
        context: ModelContext,
        undoManager: UndoManager?,
        appState: AppState? = nil,
        actionName: String
    ) {
        let before = snapshot(of: portrait)
        // Defer registration to the next run-loop tick so the caller can
        // finish mutating the portrait first. The "after" snapshot is taken
        // at that point.
        DispatchQueue.main.async {
            let after = snapshot(of: portrait)
            registerUndo(
                before: before,
                after: after,
                context: context,
                undoManager: undoManager,
                appState: appState,
                actionName: actionName
            )
        }
    }

    /// Register an undo step from explicit before/after snapshots.
    /// Use this when you manage the snapshot lifecycle yourself (e.g. drag
    /// gestures where the mutation spans many frames).
    static func registerFromSnapshots(
        before: Snapshot,
        after: Snapshot,
        context: ModelContext,
        undoManager: UndoManager?,
        appState: AppState? = nil,
        actionName: String
    ) {
        registerUndo(
            before: before,
            after: after,
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: actionName
        )
    }

    // MARK: - Undo / Redo

    private static func registerUndo(
        before: Snapshot,
        after: Snapshot,
        context: ModelContext,
        undoManager: UndoManager?,
        appState: AppState?,
        actionName: String
    ) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: context) { ctx in
            apply(before, in: ctx, appState: appState)
            try? ctx.save()
            // The reverse registration creates the redo action.
            registerUndo(
                before: after,
                after: before,
                context: ctx,
                undoManager: um,
                appState: appState,
                actionName: actionName
            )
        }
        um.setActionName(actionName)
    }

    private static func apply(_ snap: Snapshot, in context: ModelContext, appState: AppState?) {
        let id = snap.id
        let descriptor = FetchDescriptor<Portrait>(predicate: #Predicate { $0.id == id })
        guard let portrait = try? context.fetch(descriptor).first else { return }
        portrait.offsetX = snap.offsetX
        portrait.offsetY = snap.offsetY
        portrait.scale = snap.scale
        portrait.backgroundPresetID = snap.backgroundPresetID
        portrait.adjExposure = snap.adjExposure
        portrait.adjContrast = snap.adjContrast
        portrait.adjBrightness = snap.adjBrightness
        portrait.adjSaturation = snap.adjSaturation
        portrait.adjHue = snap.adjHue
        portrait.adjTemperature = snap.adjTemperature
        portrait.adjTint = snap.adjTint
        portrait.adjHighlights = snap.adjHighlights
        portrait.adjShadows = snap.adjShadows
        portrait.adjWhites = snap.adjWhites
        portrait.adjBlacks = snap.adjBlacks
        let cutoutChanged = portrait.cutoutPNG != snap.cutoutPNG
        portrait.cutoutPNG = snap.cutoutPNG
        portrait.faceRectX = snap.faceRectX
        portrait.faceRectY = snap.faceRectY
        portrait.faceRectW = snap.faceRectW
        portrait.faceRectH = snap.faceRectH
        portrait.eyeCenterX = snap.eyeCenterX
        portrait.eyeCenterY = snap.eyeCenterY
        portrait.interEyeDistance = snap.interEyeDistance
        portrait.bodyBottomY = snap.bodyBottomY
        portrait.isMagicRetouched = snap.isMagicRetouched
        portrait.preRetouchPNG = snap.preRetouchPNG
        portrait.isFillBodyApplied = snap.isFillBodyApplied
        portrait.preFillBodyPNG = snap.preFillBodyPNG
        portrait.preFillFaceRectX = snap.preFillFaceRectX
        portrait.preFillFaceRectY = snap.preFillFaceRectY
        portrait.preFillFaceRectW = snap.preFillFaceRectW
        portrait.preFillFaceRectH = snap.preFillFaceRectH
        portrait.preFillEyeCenterX = snap.preFillEyeCenterX
        portrait.preFillEyeCenterY = snap.preFillEyeCenterY
        portrait.preFillInterEyeDistance = snap.preFillInterEyeDistance
        portrait.preFillBodyBottomY = snap.preFillBodyBottomY
        portrait.preFillOffsetX = snap.preFillOffsetX
        portrait.preFillOffsetY = snap.preFillOffsetY
        portrait.preFillScale = snap.preFillScale
        portrait.isColorized = snap.isColorized
        portrait.preColorizePNG = snap.preColorizePNG
        portrait.name = snap.name
        portrait.tags = snap.tags
        portrait.updatedAt = snap.updatedAt
        if cutoutChanged { appState?.invalidateCutout(for: portrait) }
        appState?.invalidateAdjusted(for: portrait)
    }
}
