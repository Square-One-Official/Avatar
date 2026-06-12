import AvatarKit
import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Concurrency model (audit HIGH #9)
//
// `ImportFlow` reaches off the main actor for the slow stuff (file I/O,
// CGImage decode, Subject Lift V2 inference, BiRefNet / Flux model
// calls) while keeping SwiftData mutations on `@MainActor`. The discipline
// is enforced by a single rule with three concrete sub-rules.
//
// Rule: never let a non-Sendable type cross a `Task.detached` boundary.
//
//   1. **`ModelContext` stays on the main actor.** It is *not* Sendable.
//      Capture the `ModelContainer` (which is) before the detached
//      block, then re-derive `container.mainContext` inside an
//      `await MainActor.run { … }` whenever we need to write.
//   2. **`Portrait` (SwiftData @Model) stays on the main actor too.**
//      Cross the boundary with the portrait's `UUID` only; fetch by
//      `#Predicate { $0.id == portraitID }` on the main actor at the
//      mutation site.
//   3. **`AppState` is `@MainActor`-bound and Sendable by isolation.**
//      Reads / writes from inside a detached block MUST go through
//      `await MainActor.run { appState.foo = … }`. The compiler
//      enforces this under `SWIFT_STRICT_CONCURRENCY=targeted`
//      (set in `project.yml`), so a future refactor that forgets the
//      `MainActor.run` wrap will fail to build instead of crashing at
//      runtime.
//
// The cancellation contract (audit MEDIUM #28) is layered on top: each
// detached task handle is registered with `appState.trackImportTask(_:)`
// so a backgrounded window / sheet dismissal can call
// `appState.cancelInFlightImports()` and the next `await` boundary
// inside each task throws CancellationError cleanly.

/// Centralised drop-handler used by every view that should accept a portrait
/// drag-and-drop (the empty-state import zone AND the editor surface, so users
/// can drop a fresh photo at any time without going back to an empty state).
@MainActor
enum PortraitDropHandler {
    /// Handles a drag-and-drop of one or more image providers. Single-image
    /// drops run immediately. Pro users dropping more than
    /// `BatchConfirmRequest.threshold` images at once get a confirm dialog
    /// (each Magic Cutout call costs 1 credit), so a stray drop of a 500-
    /// photo folder doesn't burn a month of credits in one go. Free users
    /// drop into a partial-allowance gate: any overflow past
    /// `freeImportsRemaining` is dropped from the batch and a single
    /// upsell toast is surfaced — the rest still process.
    static func handle(providers: [NSItemProvider],
                       context: ModelContext,
                       appState: AppState) -> Bool {
        guard !providers.isEmpty else { return false }

        // Clamp the batch to what the user is actually allowed to import.
        // Surfaces the appropriate toast/paywall as a side effect. We always
        // return `true` so the drop is consumed (not bounced back by the
        // system) even when the upsell short-circuits the entire import.
        let allowed = FreeTierGate.allowedImportCount(requested: providers.count,
                                                      appState: appState)
        guard allowed > 0 else { return true }
        // Shuffle before clipping: when a free user drops more images than
        // their remaining allowance, take a random subset instead of always
        // the leading N. Pro users always have `allowed == providers.count`
        // so the shuffle is observable only when the gate trims the batch.
        let clipped = Array(providers.shuffled().prefix(allowed))

        // Decide whether to confirm before processing the batch. Cloud
        // mode requires Magic Cutout entitlement, the per-feature toggle,
        // **and** the global privacy posture being `cloudAllowed`. In
        // localOnly mode this is always false, so the entire batch routes
        // to local Subject Lift and no signed PUT URL is ever requested.
        let useCloud = ImportFlow.shouldUseMagicCutout(appState: appState)
        if useCloud && clipped.count > BatchConfirmRequest.threshold {
            appState.batchConfirm = BatchConfirmRequest(
                count: clipped.count,
                credits: clipped.count, // 1 credit per image
                onConfirm: {
                    appState.batchConfirm = nil
                    processAll(providers: clipped, context: context,
                               appState: appState)
                },
                onCancel: {
                    appState.batchConfirm = nil
                }
            )
            return true
        }

        processAll(providers: clipped, context: context,
                   appState: appState)
        return true
    }

    /// Iterates the dropped providers and dispatches each to ImportFlow.
    /// Items run serially behind the scenes (each `importFile`/`importData`
    /// kicks its own `Task.detached`); on the cloud path the backend is
    /// expected to rate-limit if needed. Errors on individual items surface
    /// in `appState.lastError` and don't halt the batch.
    private static func processAll(providers: [NSItemProvider],
                                   context: ModelContext,
                                   appState: AppState) {
        appState.isProcessing = true
        let fileURLType = UTType.fileURL.identifier
        let imageType = UTType.image.identifier
        // ModelContainer is Sendable; ModelContext is not. Capture the container
        // across the @Sendable loadDataRepresentation boundary, then re-derive
        // the main context inside the @MainActor task.
        let container = context.container

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(fileURLType) {
                provider.loadDataRepresentation(forTypeIdentifier: fileURLType) { data, _ in
                    guard let data,
                          let urlString = String(data: data, encoding: .utf8),
                          let url = URL(string: urlString) ?? URL(dataRepresentation: data, relativeTo: nil)
                    else {
                        Task { @MainActor in
                            appState.warn(Loc.dropPhotoNotFound)
                            dlog("[Drop] failed to decode file URL")
                        }
                        return
                    }
                    Task { @MainActor in
                        ImportFlow.importFile(url: url, context: container.mainContext, appState: appState)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(imageType) {
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                    guard let data else {
                        Task { @MainActor in
                            appState.warn(Loc.dropImageUnreadable)
                        }
                        return
                    }
                    Task { @MainActor in
                        ImportFlow.importData(data, suggestedName: Loc.imported,
                                              context: container.mainContext, appState: appState)
                    }
                }
            } else {
                appState.warn(Loc.unknownFileType)
            }
        }
    }
}

/// Free-tier import gating used by all import entry points (drop, file
/// picker, raw `importFile` from MainWindow). Returns the number of
/// incoming items the caller should actually process. A return of 0
/// means the caller should skip the import entirely; the gate has
/// already surfaced the relevant paywall/toast.
@MainActor
enum FreeTierGate {
    /// Decide how many of the `requested` portraits the caller may
    /// process right now. Pro users are clamped to the technical batch
    /// cap. Free users are clamped to `freeImportsRemaining` so a drop
    /// of N images with M slots left processes M and surfaces a single
    /// upsell toast for the dropped overflow — instead of refusing the
    /// entire batch.
    ///
    /// The library size is intentionally ignored — the cap is "lifetime
    /// imports", not "portraits visible in the library". Real authority
    /// lives server-side (`users.free_imports_used` /
    /// `device_imports.free_imports_used`); this client check is just a
    /// fast pre-flight on `proEntitlement.freeImportsRemaining`.
    /// `ImportFlow.claimImportSlot` is the actual gate per image.
    static func allowedImportCount(requested: Int,
                                   appState: AppState) -> Int {
        if appState.proEntitlement.isPro {
            if requested > ProLimits.maxBatchImport {
                appState.showProInfo(Loc.proBatchCapExceeded(ProLimits.maxBatchImport))
                return 0
            }
            return requested
        }

        let remaining = appState.proEntitlement.freeImportsRemaining
        if remaining <= 0 {
            appState.showProUpgradeSheet = true
            return 0
        }
        if requested > remaining {
            // Process what's left and nudge the user — this is the
            // moment the free tier ran out, so a soft upsell toast
            // beats blocking the whole drop.
            appState.showProUpsell(Loc.proUpsellPartialBatch(processed: remaining,
                                                              requested: requested))
            return remaining
        }
        return requested
    }
}

@MainActor
enum ImportFlow {
    /// Reserves one server-side import slot before the pipeline runs.
    /// Pro users return immediately with `allowed=true`. Free users hit
    /// the per-account + per-device counters; either at the cap → paywall.
    /// On transport failure we **fail open** (allow the import) so an
    /// offline user isn't held hostage by their flaky Wi-Fi; the next
    /// online claim will reconcile against the server. Returns true when
    /// the caller should proceed with the pipeline.
    @MainActor
    private static func claimImportSlot(appState: AppState) async -> Bool {
        if appState.proEntitlement.isPro { return true }
        do {
            let resp = try await appState.backend.claimImport()
            appState.proEntitlement.freeImportsUsed = resp.importsUsed
            appState.proEntitlement.freeImportsRemaining = resp.importsRemaining
            return true
        } catch BackendError.noCredits {
            // Server says the cap is hit. Keep state consistent with that.
            appState.proEntitlement.freeImportsRemaining = 0
            appState.showProUpgradeSheet = true
            appState.isProcessing = false
            return false
        } catch BackendError.unauthorized, BackendError.notSignedIn {
            // Token went bad mid-session — drop to the device-only path on
            // the next claim. Don't gate the import on this; surfacing a
            // sign-in prompt mid-import is worse than a forgiving allow.
            return true
        } catch {
            // Transport / server error — fail open. The Magic Cutout call
            // (if any) has its own credit gate and will surface the
            // offline toast there.
            dlog("[Import] claim failed, allowing import: \(error)")
            return true
        }
    }

    /// Reads a portrait file from disk, runs subject-lift + face detection,
    /// computes auto-alignment, and inserts a new Portrait into SwiftData.
    /// File I/O and image decode happen on a background task so the main
    /// thread stays responsive during large HEIC/PNG reads.
    static func importFile(url: URL, context: ModelContext, appState: AppState) {
        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[Import] start url=\(url.path)")

        let useCloud = shouldUseMagicCutout(appState: appState)
        let suggestedName = url.deletingPathExtension().lastPathComponent
        // Capture Sendable container; runPipeline derives the main context.
        let container = context.container

        let task = Task.detached(priority: .userInitiated) {
            // Reserve the server-side slot first so the cheat path
            // (delete-then-reimport) is closed before we even decode.
            let allowed = await claimImportSlot(appState: appState)
            guard allowed else { return }

            // Re-anchor the security-scoped access on the background thread
            // that will actually read the file.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                await MainActor.run {
                    appState.warn(Loc.cannotReadFile(error.localizedDescription))
                    appState.isProcessing = false
                    dlog("[Import] FAILED Data(contentsOf:) error=\(error)")
                }
                return
            }
            dlog("[Import] read bytes=\(data.count)")

            guard let cg = ImageProcessor.cgImage(from: data) else {
                await MainActor.run {
                    appState.warn(Loc.cannotDecodeImage)
                    appState.isProcessing = false
                    dlog("[Import] FAILED CGImage decode (data was \(data.count) bytes)")
                }
                return
            }
            dlog("[Import] loaded CGImage \(cg.width)x\(cg.height)")

            await runPipeline(cg: cg, originalData: data, suggestedName: suggestedName,
                              container: container, appState: appState,
                              useCloud: useCloud)
        }
        // Audit MEDIUM #28: register so a window-background or sheet-
        // dismissal cancels the in-flight pipeline cleanly.
        appState.trackImportTask(task)
    }

    /// Variant for when raw image bytes are already in memory (e.g. dragged from
    /// another app, no file URL).
    static func importData(_ data: Data, suggestedName: String,
                           context: ModelContext, appState: AppState) {
        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[Import] start data bytes=\(data.count)")

        let useCloud = shouldUseMagicCutout(appState: appState)
        let container = context.container

        let task = Task.detached(priority: .userInitiated) {
            // Same anti-cheat gate as importFile — see claimImportSlot.
            let allowed = await claimImportSlot(appState: appState)
            guard allowed else { return }

            guard let cg = ImageProcessor.cgImage(from: data) else {
                await MainActor.run {
                    appState.warn(Loc.cannotDecodeImage)
                    appState.isProcessing = false
                    dlog("[Import] FAILED CGImage decode from raw data")
                }
                return
            }
            await runPipeline(cg: cg, originalData: data, suggestedName: suggestedName,
                              container: container, appState: appState,
                              useCloud: useCloud)
        }
        appState.trackImportTask(task)
    }

    /// Re-runs the cutout pipeline on an existing portrait via cloud Magic
    /// Cutout, overwriting the cached PNG + face rect but preserving the
    /// user's manual transform (offset/scale) and other editor state.
    ///
    /// One-shot — bypasses the persistent `magicCutoutPrefs.enabled` toggle.
    /// The toggle controls *import* defaults; redo is an explicit per-portrait
    /// opt-in. Gated on entitlement (`canUseProCutout`): non-entitled users
    /// see the paywall instead of running the call.
    static func reprocess(portrait: Portrait, context: ModelContext, appState: AppState) {
        // Local-only short-circuit: redo IS a cloud call by definition
        // (it's the upgrade-from-Subject-Lift path). Surface a soft note
        // instead of silently falling through to a no-op or — worse — a
        // signed PUT URL request that the privacy mode is supposed to
        // block. The CTA points at the only place to flip the switch.
        guard appState.privacyPrefs.cloudAllowed else {
            appState.note(Loc.reprocessRequiresCloudAI)
            return
        }
        guard appState.proEntitlement.canUseProCutout else {
            appState.showProUpgradeSheet = true
            return
        }
        guard let data = portrait.originalImageData else {
            appState.warn(Loc.noOriginalForRecutout)
            return
        }
        guard let cg = ImageProcessor.cgImage(from: data) else {
            appState.warn(Loc.cannotDecodeOriginal)
            return
        }

        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[Reprocess] start id=\(portrait.id) \(cg.width)x\(cg.height)")

        let portraitID = portrait.id
        let task = Task.detached(priority: .userInitiated) {
            do {
                let result = try await runCloudWithFallback(cg: cg, appState: appState)
                let processed = result.subject
                let usedMagic = result.usedMagic
                let pngData = ImageProcessor.pngData(from: processed.cutout) ?? Data()
                dlog("[Reprocess] done bytes=\(pngData.count) face=\(processed.faceRect ?? .zero) usedMagic=\(usedMagic)")

                await MainActor.run {
                    // Re-fetch the portrait on the main actor to avoid
                    // crossing isolation boundaries with the @Model object.
                    let descriptor = FetchDescriptor<Portrait>(
                        predicate: #Predicate { $0.id == portraitID }
                    )
                    guard let fresh = try? context.fetch(descriptor).first else {
                        appState.isProcessing = false
                        appState.warn(Loc.portraitNotFound)
                        return
                    }
                    fresh.cutoutPNG = pngData
                    fresh.faceRect = processed.faceRect ?? .zero
                    fresh.eyeCenter = processed.eyeCenter
                    fresh.interEyeDistance = Double(processed.interEyeDistance ?? 0)
                    fresh.bodyBottomY = Double(processed.bodyBottomY)
                    fresh.isMagicRetouched = false
                    fresh.preRetouchPNG = nil
                    fresh.cutoutUsedMagic = usedMagic
                    fresh.updatedAt = Date()
                    try? context.save()
                    // Purge any cached decoded cutout so the editor shows the
                    // refreshed PNG on next access.
                    appState.invalidateCutout(for: fresh)
                    appState.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    appState.warn(Loc.recutoutFailed(error.localizedDescription))
                    appState.isProcessing = false
                    dlog("[Reprocess] ERROR \(error)")
                }
            }
        }
        appState.trackImportTask(task)
    }

    // MARK: - Magic Retouch

    /// Applies a one-click studio-quality enhancement (Apple auto-adjust +
    /// vibrance + shadow lift + warmth + sharpen) to the portrait's cutout.
    /// The enhanced version replaces `cutoutPNG`; manual adjustment sliders
    /// still layer on top at render time. "Opnieuw uitknippen" serves as undo.
    static func magicRetouch(portrait: Portrait, context: ModelContext, appState: AppState) {
        guard !portrait.isMagicRetouched else {
            appState.note(Loc.magicRetouchAlready)
            return
        }
        guard let cutoutData = portrait.cutoutPNG,
              let cutoutCG = ImageProcessor.cgImage(from: cutoutData) else {
            appState.note(Loc.noCutoutAvailable)
            return
        }

        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[MagicRetouch] start id=\(portrait.id) \(cutoutCG.width)×\(cutoutCG.height)")

        let portraitID = portrait.id
        let task = Task.detached(priority: .userInitiated) {
            guard let enhanced = ImageProcessor.magicRetouch(image: cutoutCG) else {
                await MainActor.run {
                    appState.warn(Loc.magicRetouchFailed)
                    appState.isProcessing = false
                }
                return
            }
            let pngData = ImageProcessor.pngData(from: enhanced) ?? Data()
            dlog("[MagicRetouch] done bytes=\(pngData.count)")

            await MainActor.run {
                let descriptor = FetchDescriptor<Portrait>(
                    predicate: #Predicate { $0.id == portraitID }
                )
                guard let fresh = try? context.fetch(descriptor).first else {
                    appState.isProcessing = false
                    appState.warn(Loc.portraitNotFound)
                    return
                }
                fresh.preRetouchPNG = fresh.cutoutPNG
                fresh.cutoutPNG = pngData
                fresh.isMagicRetouched = true
                fresh.updatedAt = Date()
                try? context.save()
                appState.invalidateCutout(for: fresh)
                appState.isProcessing = false
                dlog("[MagicRetouch] DONE id=\(fresh.id)")
            }
        }
        appState.trackImportTask(task)
    }

    /// Reverts Magic Retouch by restoring the pre-retouch cutout.
    static func undoMagicRetouch(portrait: Portrait, context: ModelContext, appState: AppState) {
        guard portrait.isMagicRetouched, let original = portrait.preRetouchPNG else { return }
        portrait.cutoutPNG = original
        portrait.preRetouchPNG = nil
        portrait.isMagicRetouched = false
        portrait.updatedAt = Date()
        try? context.save()
        appState.invalidateCutout(for: portrait)
    }

    // MARK: - Fill in Body (Pro identity-preserving reframe)

    /// Calls `/v1/fill-body`. The server runs Gemini 2.5 Flash to analyse
    /// the portrait, decides whether anything is actually clipped, and
    /// (only if so) calls Flux Kontext Pro with a prompt naming the
    /// SPECIFIC missing parts before re-extracting alpha via BiRefNet.
    /// On the no-op branch (portrait already complete) no credit is
    /// charged and the cutout is left untouched — we just show a toast.
    /// On the updated branch, we re-detect face/body and re-align the
    /// new cutout via `AutoAligner.computeTransform` (the same auto-align
    /// used at import) so the result frames consistently with every other
    /// portrait in the user's library. Undo restores the user's pre-fill
    /// transform exactly if they prefer it. Costs 1 credit on success;
    /// failures and no-ops don't deduct.
    static func fillBody(
        portrait: Portrait,
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager? = nil
    ) {
        // Pro-only feature — non-entitled users get the paywall instead of
        // running the call. Distinct from Magic Cutout's `canUseProCutout`
        // because Fill in Body has no free-trial allowance.
        // Re-entry guard: if a previous Fill in Body (or any other
        // processing) is still in flight, swallow the call rather than
        // firing a parallel backend request. The dropdown button is also
        // disabled while processing, but a stale closure could still reach
        // here — belt and suspenders against the 429s users were seeing
        // from rapid double-clicks.
        guard !appState.isProcessing else { return }
        guard appState.proEntitlement.isPro else {
            appState.showProUpgradeSheet = true
            return
        }
        guard !portrait.isFillBodyApplied else {
            appState.note(Loc.fillBodyAlready)
            return
        }
        guard let cutoutData = portrait.cutoutPNG else {
            appState.note(Loc.noCutoutAvailable)
            return
        }

        // Set kind before isProcessing so the loader picks up the
        // body-reframing copy from the very first frame. Auto-resets to
        // `.cutout` when isProcessing flips back to false.
        appState.processingKind = .fillBody
        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[FillBody] start id=\(portrait.id) bytes=\(cutoutData.count)")

        // Snapshot every field we're about to mutate so undo is lossless.
        let snap = FillBodySnapshot(from: portrait)
        let undoBefore = PortraitUndoManager.snapshot(of: portrait)
        let portraitID = portrait.id
        let backend = appState.backend

        let task = Task.detached(priority: .userInitiated) {
            do {
                // Detect the face on the pre-fill cutout so the backend can
                // lock that region as never-paint in the outpaint mask. The
                // strict rule is: Fill in Body must never modify the face,
                // even when alpha gaps suggest missing parts. Vision is
                // reliable for the head-and-shoulders framing the app uses;
                // on the rare miss the backend falls back to a top-of-bbox
                // heuristic so we still get partial protection.
                let faceBox: BackendClient.FaceBox? = {
                    guard let cg = ImageProcessor.cgImage(from: cutoutData),
                          let rect = ImageProcessor.detectFace(in: cg) else {
                        return nil
                    }
                    let w = CGFloat(cg.width), h = CGFloat(cg.height)
                    guard w > 0, h > 0 else { return nil }
                    return BackendClient.FaceBox(
                        x: Double(rect.minX / w),
                        y: Double(rect.minY / h),
                        width: Double(rect.width / w),
                        height: Double(rect.height / h)
                    )
                }()

                let (newCutoutPNG, creditsRemaining) = try await backend.fillBody(
                    imagePNG: cutoutData, faceBox: faceBox
                )

                guard let newCutoutCG = ImageProcessor.cgImage(from: newCutoutPNG) else {
                    throw BackendError.decode
                }
                // Re-detect on an already-cut-out image: no hair-edge
                // work needed (the matte is the original cutout's), so
                // skip the downloaded engine even when the user has it
                // selected — saves an MLModel round-trip we'd just throw
                // away.
                let detected = try ImageProcessor.process(image: newCutoutCG, downloadedModelURL: nil)
                let newCutoutSize = CGSize(width: newCutoutCG.width, height: newCutoutCG.height)
                dlog("[FillBody] new cutout \(newCutoutCG.width)×\(newCutoutCG.height) " +
                     "eye=\(detected.eyeCenter.map { "\($0.x),\($0.y)" } ?? "nil") " +
                     "bodyBottom=\(detected.bodyBottomY)")

                await MainActor.run {
                    let descriptor = FetchDescriptor<Portrait>(
                        predicate: #Predicate { $0.id == portraitID }
                    )
                    guard let fresh = try? context.fetch(descriptor).first else {
                        appState.isProcessing = false
                        appState.warn(Loc.portraitNotFound)
                        return
                    }
                    snap.write(into: fresh)
                    fresh.cutoutPNG = newCutoutPNG
                    if let face = detected.faceRect { fresh.faceRect = face }
                    fresh.eyeCenter = detected.eyeCenter
                    fresh.interEyeDistance = Double(detected.interEyeDistance ?? 0)
                    fresh.bodyBottomY = Double(detected.bodyBottomY)

                    // Use the same auto-align logic that runs at import time
                    // so a Fill in Body result frames consistently with every
                    // other portrait in the library. Undo restores the
                    // user's pre-fill transform if they prefer it.
                    let transform = AutoAligner.computeTransform(
                        faceRect: detected.faceRect ?? .zero,
                        eyeCenter: detected.eyeCenter,
                        interEyeDistance: detected.interEyeDistance,
                        cutoutSize: newCutoutSize,
                        bodyBottomY: detected.bodyBottomY
                    )
                    fresh.scale = Double(transform.scale)
                    fresh.offsetX = Double(transform.offset.width)
                    fresh.offsetY = Double(transform.offset.height)
                    fresh.isFillBodyApplied = true
                    fresh.updatedAt = Date()
                    try? context.save()

                    PortraitUndoManager.registerFromSnapshots(
                        before: undoBefore,
                        after: PortraitUndoManager.snapshot(of: fresh),
                        context: context,
                        undoManager: undoManager,
                        appState: appState,
                        actionName: Loc.fillBody
                    )

                    // Sync local credit counter so the sidebar updates without
                    // waiting for the next /v1/account refresh.
                    appState.proEntitlement.credits = creditsRemaining
                    appState.invalidateCutout(for: fresh)
                    appState.isProcessing = false
                    dlog("[FillBody] DONE id=\(fresh.id) credits=\(creditsRemaining) " +
                         "scale=\(fresh.scale) offset=(\(fresh.offsetX),\(fresh.offsetY))")
                }
            } catch let err as BackendError {
                await MainActor.run {
                    appState.isProcessing = false
                    switch err {
                    case .noCredits:
                        appState.showProUpgradeSheet = true
                    case .server, .decode:
                        // Don't leak raw backend error codes to the user
                        // ("fill_body_failed" landed in a toast verbatim).
                        // The localized Loc.fillBodyFailed reads cleanly.
                        appState.warn(Loc.fillBodyFailed)
                    default:
                        if !appState.report(err) {
                            appState.warn(Loc.fillBodyFailed)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    appState.isProcessing = false
                    appState.warn(Loc.fillBodyFailed)
                }
            }
        }
        appState.trackImportTask(task)
    }

    /// Reverts Fill in Body by restoring the snapshotted cutout and geometry.
    /// One-shot: credits are not refunded (the Replicate call already happened).
    static func undoFillBody(
        portrait: Portrait,
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager? = nil
    ) {
        guard portrait.isFillBodyApplied, let original = portrait.preFillBodyPNG else { return }
        let undoBefore = PortraitUndoManager.snapshot(of: portrait)
        portrait.cutoutPNG = original
        portrait.faceRectX = portrait.preFillFaceRectX
        portrait.faceRectY = portrait.preFillFaceRectY
        portrait.faceRectW = portrait.preFillFaceRectW
        portrait.faceRectH = portrait.preFillFaceRectH
        portrait.eyeCenterX = portrait.preFillEyeCenterX
        portrait.eyeCenterY = portrait.preFillEyeCenterY
        portrait.interEyeDistance = portrait.preFillInterEyeDistance
        portrait.bodyBottomY = portrait.preFillBodyBottomY
        portrait.offsetX = portrait.preFillOffsetX
        portrait.offsetY = portrait.preFillOffsetY
        portrait.scale = portrait.preFillScale
        portrait.preFillBodyPNG = nil
        portrait.isFillBodyApplied = false
        portrait.updatedAt = Date()
        try? context.save()
        appState.invalidateCutout(for: portrait)
        PortraitUndoManager.registerFromSnapshots(
            before: undoBefore,
            after: PortraitUndoManager.snapshot(of: portrait),
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: Loc.fillBodyUndo
        )
    }

    // MARK: - Colorise (Pro B&W → colour)

    /// Calls `/v1/colorize`. The server flattens the cutout over neutral
    /// grey, runs DeOldify on the RGB, and re-attaches the original alpha
    /// so the silhouette round-trips identically. No face/body redetect or
    /// re-align is needed (dimensions and geometry are preserved). Costs
    /// 1 credit on success; failures don't deduct.
    static func colorize(
        portrait: Portrait,
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager? = nil
    ) {
        guard !appState.isProcessing else { return }
        guard appState.proEntitlement.isPro else {
            appState.showProUpgradeSheet = true
            return
        }
        guard !portrait.isColorized else {
            appState.note(Loc.colorizeAlready)
            return
        }
        guard let cutoutData = portrait.cutoutPNG else {
            appState.note(Loc.noCutoutAvailable)
            return
        }

        appState.processingKind = .colorize
        appState.isProcessing = true
        appState.dismissBanner()
        dlog("[Colorize] start id=\(portrait.id) bytes=\(cutoutData.count)")

        let undoBefore = PortraitUndoManager.snapshot(of: portrait)
        let portraitID = portrait.id
        let backend = appState.backend

        let task = Task.detached(priority: .userInitiated) {
            do {
                let (newCutoutPNG, creditsRemaining) = try await backend.colorize(
                    imagePNG: cutoutData
                )

                await MainActor.run {
                    let descriptor = FetchDescriptor<Portrait>(
                        predicate: #Predicate { $0.id == portraitID }
                    )
                    guard let fresh = try? context.fetch(descriptor).first else {
                        appState.isProcessing = false
                        appState.warn(Loc.portraitNotFound)
                        return
                    }
                    fresh.preColorizePNG = fresh.cutoutPNG
                    fresh.cutoutPNG = newCutoutPNG
                    fresh.isColorized = true
                    fresh.updatedAt = Date()
                    try? context.save()

                    PortraitUndoManager.registerFromSnapshots(
                        before: undoBefore,
                        after: PortraitUndoManager.snapshot(of: fresh),
                        context: context,
                        undoManager: undoManager,
                        appState: appState,
                        actionName: Loc.colorize
                    )

                    appState.proEntitlement.credits = creditsRemaining
                    appState.invalidateCutout(for: fresh)
                    appState.isProcessing = false
                    dlog("[Colorize] DONE id=\(fresh.id) credits=\(creditsRemaining)")
                }
            } catch let err as BackendError {
                await MainActor.run {
                    appState.isProcessing = false
                    switch err {
                    case .noCredits:
                        appState.showProUpgradeSheet = true
                    case .server, .decode:
                        appState.warn(Loc.colorizeFailed)
                    default:
                        if !appState.report(err) {
                            appState.warn(Loc.colorizeFailed)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    appState.isProcessing = false
                    appState.warn(Loc.colorizeFailed)
                }
            }
        }
        appState.trackImportTask(task)
    }

    /// Reverts Colorise by restoring the snapshotted B&W cutout. One-shot:
    /// credits are not refunded (the Replicate call already happened).
    static func undoColorize(
        portrait: Portrait,
        context: ModelContext,
        appState: AppState,
        undoManager: UndoManager? = nil
    ) {
        guard portrait.isColorized, let original = portrait.preColorizePNG else { return }
        let undoBefore = PortraitUndoManager.snapshot(of: portrait)
        portrait.cutoutPNG = original
        portrait.preColorizePNG = nil
        portrait.isColorized = false
        portrait.updatedAt = Date()
        try? context.save()
        appState.invalidateCutout(for: portrait)
        PortraitUndoManager.registerFromSnapshots(
            before: undoBefore,
            after: PortraitUndoManager.snapshot(of: portrait),
            context: context,
            undoManager: undoManager,
            appState: appState,
            actionName: Loc.colorizeUndo
        )
    }

    // MARK: - Import Pipeline

    /// Returns true when the user is allowed to run Magic Cutout *and* has
    /// the toggle on. "Allowed" means either Pro, or a free user with
    /// trial cutouts remaining (`canUseProCutout`). Drives the pipeline
    /// branch: cloud Magic Cutout (Replicate) versus Apple Subject Lift.
    /// Cloud errors fall back to Subject Lift via `runCloudWithFallback`;
    /// failed calls never spend a credit nor a free-trial slot.
    ///
    /// Local-first gate: even with entitlement and the per-feature toggle
    /// on, returns false when the global privacy posture is `localOnly`.
    /// That keeps the cloud branch unreachable — no signed PUT URL is ever
    /// requested, no photo bytes leave the Mac. Settings → Privacy & AI is
    /// the single switch that controls this; the per-feature Magic Cutout
    /// toggle keeps its existing semantics within `cloudAllowed`.
    @MainActor
    static func shouldUseMagicCutout(appState: AppState) -> Bool {
        appState.privacyPrefs.cloudAllowed
            && appState.proEntitlement.canUseProCutout
            && appState.magicCutoutPrefs.enabled
    }

    /// Resolves the URL of the on-disk downloaded matting model — but only
    /// when the user has actually picked the downloaded engine. Returns
    /// nil when the engine is `.appleVision`, when the model isn't
    /// downloaded yet, or when the user is on the cloud path (where the
    /// engine choice is moot).
    ///
    /// Hopping to MainActor reads the live `privacyPrefs.engine` and
    /// `modelManager.state` — both `@Observable` and main-actor-bound —
    /// so the import pipeline (which runs on a detached task) gets a
    /// consistent snapshot.
    @MainActor
    static func resolveDownloadedModelURL(appState: AppState) -> URL? {
        guard appState.privacyPrefs.engine == .downloadedModel else { return nil }
        return appState.modelManager.cachedModelURL()
    }

    /// Runs Magic Cutout against the backend, hopping to MainActor for
    /// state mutations. On `noCredits` opens the paywall; on
    /// `unauthorized` opens the sign-in prompt; on any other error sets
    /// the offline toast on `appState.lastError`. In every error case
    /// falls back to the synchronous Apple Subject Lift so the user
    /// still gets a result and never spends a credit on a failed call.
    /// Result of a (possibly cloud-backed) cutout. `usedMagic` is only true
    /// when the cloud call actually succeeded — fallback to Apple Subject
    /// Lift returns false so the editor can offer a "redo with Magic"
    /// affordance later.
    struct CutoutResult {
        let subject: ProcessedSubject
        let usedMagic: Bool
    }

    nonisolated private static func runCloudWithFallback(
        cg: CGImage, appState: AppState
    ) async throws -> CutoutResult {
        let backend = await MainActor.run { appState.backend }
        do {
            let result = try await ImageProcessor.processCloud(image: cg, backend: backend)
            await MainActor.run {
                appState.proEntitlement.credits = result.creditsRemaining
                // The unified `freeImportsRemaining` is the single source of
                // truth and is updated by `claimImportSlot` before this call
                // runs; the import-exhaustion paywall fires from there.
            }
            return CutoutResult(subject: result.subject, usedMagic: true)
        } catch let err as BackendError {
            // Cloud-cutout context needs its own copy ("using basic cutout,
            // no credits charged") that the generic `appState.report(_:)`
            // doesn't carry. So we route here directly. For account-level
            // errors (noCredits, auth) we still defer to the dedicated
            // surfaces — paywall sheet and sign-in alert — and skip the
            // banner entirely so the user isn't told the same thing twice.
            await MainActor.run {
                switch err {
                case .noCredits:
                    appState.showProUpgradeSheet = true
                case .unauthorized, .notSignedIn:
                    // Don't pop a global alert mid-import — the basic
                    // cutout already ran, so the user got their result.
                    // A chip nudges them toward Settings without blocking.
                    appState.warn(Loc.magicCutoutSignedOut)
                case .transport, .rateLimited:
                    // Recoverable: Wi-Fi blip or rate limit. Try again.
                    appState.warn(Loc.magicCutoutOfflineToast)
                case .server(let code, let message):
                    // Log the raw status/detail for devs; show friendly copy.
                    dlog("[Magic Cutout] server error \(code) \(message ?? "")")
                    appState.fail(Loc.magicCutoutServerError(code, message))
                case .payloadTooLarge(let bytes, let limit):
                    // Pre-flight reject — known transport ceiling, not a
                    // server fault. `.warn` keeps the toast amber, not red.
                    dlog("[Magic Cutout] image too large bytes=\(bytes) limit=\(limit)")
                    appState.warn(Loc.magicCutoutImageTooLarge(limit / (1024 * 1024)))
                case .decode:
                    appState.fail(Loc.magicCutoutDecodeError)
                case .proRequired:
                    // Should be caught by the entitlement gate before we
                    // ever reach the cloud call. If we still get here
                    // something is out of sync, so escalate.
                    appState.fail(err.errorDescription ?? Loc.somethingWentWrong)
                }
            }
            // Fallback runs sync off main. Apple Subject Lift / downloaded
            // BiRefNet never charges. Resolve the engine choice on the
            // MainActor so the snapshot is consistent with what Settings
            // shows; the URL is nil when the user is on Apple Vision or
            // hasn't downloaded yet.
            let modelURL = await resolveDownloadedModelURL(appState: appState)
            let subject = try ImageProcessor.process(image: cg, downloadedModelURL: modelURL)
            return CutoutResult(subject: subject, usedMagic: false)
        } catch {
            await MainActor.run { appState.warn(Loc.magicCutoutOfflineToast) }
            let modelURL = await resolveDownloadedModelURL(appState: appState)
            let subject = try ImageProcessor.process(image: cg, downloadedModelURL: modelURL)
            return CutoutResult(subject: subject, usedMagic: false)
        }
    }

    nonisolated private static func runPipeline(
        cg: CGImage, originalData data: Data,
        suggestedName: String,
        container: ModelContainer, appState: AppState,
        useCloud: Bool = false
    ) async {
        do {
            let processed: ProcessedSubject
            let usedMagic: Bool
            if useCloud {
                let result = try await runCloudWithFallback(cg: cg, appState: appState)
                processed = result.subject
                usedMagic = result.usedMagic
            } else {
                // Local path. Engine is picked up here — when the user
                // is on Apple Vision (or hasn't downloaded the enhanced
                // model yet) `modelURL` is nil and `process` runs V2
                // exactly as before.
                let modelURL = await resolveDownloadedModelURL(appState: appState)
                processed = try ImageProcessor.process(image: cg, downloadedModelURL: modelURL)
                usedMagic = false
            }
            let cutoutSize = CGSize(width: processed.cutout.width, height: processed.cutout.height)
            let face = processed.faceRect ?? .zero
            dlog("[Import] subject lift OK cutout=\(processed.cutout.width)x\(processed.cutout.height) face=\(face)")

            let bodyBottom = processed.bodyBottomY
            let transform = (processed.faceRect != nil)
                ? AutoAligner.computeTransform(
                    faceRect: face,
                    eyeCenter: processed.eyeCenter,
                    interEyeDistance: processed.interEyeDistance,
                    cutoutSize: cutoutSize,
                    bodyBottomY: bodyBottom)
                : AutoAligner.fitTransform(cutoutSize: cutoutSize)
            dlog("[Import] transform scale=\(transform.scale) offset=\(transform.offset) bodyBottom=\(bodyBottom) eyes=\(processed.eyeCenter as Any) IPD=\(processed.interEyeDistance as Any)")

            let pngData = ImageProcessor.pngData(from: processed.cutout) ?? Data()
            dlog("[Import] PNG encoded bytes=\(pngData.count)")
            if pngData.isEmpty {
                dlog("[Import] WARNING pngData is empty — cutout will be invisible!")
            }

            await MainActor.run {
                let context = container.mainContext
                // Bind the new portrait to the user's current default so a corrupted
                // multi-default data state can't make the picker / canvas disagree.
                var defaultDescriptor = FetchDescriptor<BackgroundPreset>(
                    predicate: #Predicate { $0.isDefault == true },
                    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
                )
                defaultDescriptor.fetchLimit = 1
                let defaultBgID = (try? context.fetch(defaultDescriptor))?.first?.id

                let portrait = Portrait(
                    name: suggestedName,
                    cutoutPNG: pngData,
                    originalImageData: data,
                    faceRect: face,
                    eyeCenter: processed.eyeCenter,
                    interEyeDistance: Double(processed.interEyeDistance ?? 0),
                    bodyBottomY: Double(bodyBottom),
                    offsetX: Double(transform.offset.width),
                    offsetY: Double(transform.offset.height),
                    scale: Double(transform.scale),
                    backgroundPresetID: defaultBgID
                )
                portrait.cutoutUsedMagic = usedMagic
                context.insert(portrait)
                try? context.save()
                appState.selectedPortraitID = portrait.id
                appState.isProcessing = false
                dlog("[Import] DONE id=\(portrait.id)")
            }
        } catch {
            await MainActor.run {
                appState.warn(Loc.processingFailed(error.localizedDescription))
                appState.isProcessing = false
                dlog("[Import] ERROR \(error)")
            }
        }
    }
}

// MARK: - Fill in Body helpers

/// Snapshot of every Portrait field Fill in Body mutates. Captured before the
/// async backend call so the result-handler can write it into `preFill*`
/// fields atomically and undo can restore exact prior state.
private struct FillBodySnapshot {
    let cutoutPNG: Data?
    let faceRectX: Double, faceRectY: Double, faceRectW: Double, faceRectH: Double
    let eyeCenterX: Double, eyeCenterY: Double
    let interEyeDistance: Double
    let bodyBottomY: Double
    let offsetX: Double, offsetY: Double
    let scale: Double

    @MainActor
    init(from p: Portrait) {
        cutoutPNG = p.cutoutPNG
        faceRectX = p.faceRectX; faceRectY = p.faceRectY
        faceRectW = p.faceRectW; faceRectH = p.faceRectH
        eyeCenterX = p.eyeCenterX; eyeCenterY = p.eyeCenterY
        interEyeDistance = p.interEyeDistance
        bodyBottomY = p.bodyBottomY
        offsetX = p.offsetX; offsetY = p.offsetY
        scale = p.scale
    }

    @MainActor
    func write(into p: Portrait) {
        p.preFillBodyPNG = cutoutPNG
        p.preFillFaceRectX = faceRectX; p.preFillFaceRectY = faceRectY
        p.preFillFaceRectW = faceRectW; p.preFillFaceRectH = faceRectH
        p.preFillEyeCenterX = eyeCenterX; p.preFillEyeCenterY = eyeCenterY
        p.preFillInterEyeDistance = interEyeDistance
        p.preFillBodyBottomY = bodyBottomY
        p.preFillOffsetX = offsetX; p.preFillOffsetY = offsetY
        p.preFillScale = scale
    }
}

