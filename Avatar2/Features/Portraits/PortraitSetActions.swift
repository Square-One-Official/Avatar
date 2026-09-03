// Set-brede acties (Match framing, Match lighting, Reset adjustments, bulk-
// export, Set background) — via de gedeelde selectie + rechtermuis op Home én
// Portraits (Finder-stijl), het Edit-menu, het map-menu in de left-nav en de
// board-toolbar. Ze werken op de huidige multi-selectie i.p.v. de hele set; elke
// actie is één undo-groep en meldt zich via `SetActionReporter` (busy → bon met
// Undo in de toast).
//
// E50.3: geen `touch()` meer — set-brede acties en hun undo/redo bumpen alléén
// `Portrait2.revision`, zodat het raster (gesorteerd op `updatedAt`) niet
// herschudt. Match lighting is niet-destructief: het schrijft de Adjust-laag
// (sliders tonen het resultaat, Reset draait 'm terug) i.p.v. de cutout-pixels,
// en kiest zelf het doel (patroon van de set of het best belichte portret).

import AppKit
import AvatarKit
import AvatarUI
import ImageIO
import SwiftData
import SwiftUI

@MainActor
enum PortraitSetActions {
    // MARK: - Match framing

    /// Zelfde ooglijn + camera-afstand over de selectie, zonder lege onderkant.
    /// Eén undo-stap. Editor Auto-frame blijft per-portret (`AutoFramer.apply`).
    static func matchFraming(_ targets: [Portrait2], undoManager: UndoManager?, reporter: SetActionReporter) {
        guard !targets.isEmpty else { return }
        reporter.busy("Matching framing…")
        let datas = targets.map(\.cutoutData)
        Task {
            defer { reporter.busy(nil) }
            // Vol-res PNG-decode off-main; alleen Sendable waarden de Task in.
            let decoded: [SendableCGImage?] = await Task.detached(priority: .userInitiated) {
                datas.map { data in
                    NSImage(data: data)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil)
                        .map(SendableCGImage.init)
                }
            }.value
            var portraits: [Portrait2] = []
            var images: [CGImage] = []
            for (index, portrait) in targets.enumerated() {
                guard let boxed = decoded[index] else { continue }
                portraits.append(portrait)
                images.append(boxed.cgImage)
            }
            let transforms = await AutoFramer.sharedTransforms(for: images)
            let n = applyMatchedFraming(portraits, transforms: transforms, undoManager: undoManager, reporter: reporter)
            reporter.done(SetActionReceipt(
                title: n > 0 ? "Matched framing on \(plural(n))" : "Framing already matches",
                actionName: n > 0 ? "Match Framing" : nil,
                undoManager: undoManager
            ))
        }
    }

    /// Synchrone toepassing (testbaar): één undo-groep, `bumpRevision()` i.p.v.
    /// `touch()`. Geeft het aantal gewijzigde portretten terug.
    @discardableResult
    static func applyMatchedFraming(
        _ portraits: [Portrait2],
        transforms: [AutoFramer.Transform],
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) -> Int {
        guard !portraits.isEmpty, portraits.count == transforms.count else { return 0 }
        var changed = 0
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Match Framing")
        DSMotion.animate(DSMotion.springTransform) {
            for (index, portrait) in portraits.enumerated() {
                let before = TransformUndo.snapshot(of: portrait)
                let transform = transforms[index]
                portrait.offsetX = transform.offset.width
                portrait.offsetY = transform.offset.height
                portrait.scale = transform.scale
                let after = TransformUndo.snapshot(of: portrait)
                guard before != after else { continue }
                changed += 1
                portrait.bumpRevision()
                reporter.portraitDidChange(portrait)
                TransformUndo.register(
                    undoManager, portrait: portrait,
                    undoTo: before, redoTo: after, actionName: "Match Framing"
                )
            }
        }
        undoManager?.endUndoGrouping()
        return changed
    }

    // MARK: - Match lighting

    /// Momentopname voor het off-main rekenwerk (alleen Sendable waarden).
    private struct LightingInput: Sendable {
        let name: String
        let cutoutData: Data
        let adjust: PortraitAdjust
    }

    private struct LightingResult: Sendable {
        /// (index in `targets`, nieuwe Adjust-stand).
        let adjusted: [(index: Int, adjust: PortraitAdjust)]
        /// Naam van het referentieportret; nil = het gedeelde patroon van de set.
        let targetName: String?
        /// Aantal portretten waarvan de belichting meetbaar was.
        let measured: Int
    }

    /// Trekt de belichting van de selectie naar één doel, uitgedrukt in de
    /// Adjust-laag (niet-destructief). `reference` = expliciete referentie (de
    /// aangeklikte tegel: "Match lighting to this one"); nil = automatische
    /// doelkeuze via `SetLightingNormalizer.chooseTarget` (het patroon van de
    /// set, anders het best belichte portret; jongst-bewerkt als tie-break).
    /// Portretten die al binnen tolerantie zitten blijven ongemoeid.
    static func matchLighting(
        _ targets: [Portrait2],
        reference: Portrait2? = nil,
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) {
        guard targets.count >= 2 else { return }
        reporter.busy("Matching lighting…")
        let inputs = targets.map {
            LightingInput(name: $0.name, cutoutData: $0.cutoutData, adjust: $0.adjust)
        }
        let referenceIndex = reference.flatMap { ref in
            targets.firstIndex { $0.persistentModelID == ref.persistentModelID }
        }
        let preferredIndex = FolderSetScope.matchLightingReference(targets).flatMap { p in
            targets.firstIndex { $0 === p }
        }
        Task {
            defer { reporter.busy(nil) }
            let result = await Task.detached(priority: .userInitiated) {
                computeLighting(inputs, reference: referenceIndex, preferred: preferredIndex)
            }.value
            // Her-valideer: een tussentijds bewerkt portret slaan we over.
            var items: [(Portrait2, PortraitAdjust)] = []
            for (index, adjust) in result.adjusted {
                let portrait = targets[index]
                let input = inputs[index]
                guard portrait.cutoutData == input.cutoutData, portrait.adjust == input.adjust else { continue }
                items.append((portrait, adjust))
            }
            let n = applyMatchedLighting(items, undoManager: undoManager, reporter: reporter)
            let title: String
            if result.measured < 2 {
                title = "Couldn't read the lighting of these portraits"
            } else if n == 0 {
                title = "All \(plural(targets.count)) already match"
            } else if let name = result.targetName {
                title = "Matched \(plural(n)) to \(name)"
            } else {
                title = "Matched \(plural(n)) to the set's lighting"
            }
            reporter.done(SetActionReceipt(
                title: title,
                detail: n > 0 ? "Adjust shows the result on each portrait." : nil,
                actionName: n > 0 ? "Match Lighting" : nil,
                undoManager: undoManager
            ))
        }
    }

    /// Off-main: meet elk portret (rauw én zoals gerenderd met z'n huidige
    /// Adjust), kiest het doel en berekent per buitenstaander de Adjust-stand.
    /// Het DOEL meet je zoals de gebruiker 'm ziet (gerenderd); de BRON rauw,
    /// omdat de nieuwe Adjust de oude vervangt (herhaald matchen stapelt niet).
    private nonisolated static func computeLighting(
        _ inputs: [LightingInput], reference: Int?, preferred: Int?
    ) -> LightingResult {
        typealias Stats = SetLightingNormalizer.Stats
        struct Measured {
            let index: Int
            let image: CGImage
            let region: CGRect?
            let rawStats: Stats
            let renderedStats: Stats
        }
        var measured: [Measured] = []
        for (index, input) in inputs.enumerated() {
            guard let full = NSImage(data: input.cutoutData)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let scaled = SetLightingNormalizer.downscaled(full, maxSide: 256) else { continue }
            // Gezicht op vol-res detecteren (Vision), meten op werkformaat.
            let region = SetLightingNormalizer.faceRegion(in: full).map {
                $0.applying(CGAffineTransform(scaleX: scaled.scale, y: scaled.scale))
            }
            guard let rawStats = SetLightingNormalizer.referenceStats(of: scaled.image, in: region) else { continue }
            var renderedStats = rawStats
            if !input.adjust.isNeutral,
               let rendered = PortraitEnhancer.colorAdjust(
                   scaled.image, brightness: input.adjust.brightness, contrast: input.adjust.contrast,
                   saturation: input.adjust.saturation, temperatureShift: input.adjust.temperature
               ),
               let stats = SetLightingNormalizer.referenceStats(of: rendered, in: region) {
                renderedStats = stats
            }
            measured.append(Measured(
                index: index, image: scaled.image, region: region,
                rawStats: rawStats, renderedStats: renderedStats
            ))
        }
        guard measured.count >= 2 else {
            return LightingResult(adjusted: [], targetName: nil, measured: measured.count)
        }

        let stats = measured.map(\.renderedStats)
        let target: SetLightingNormalizer.Target
        let positions: [Int]
        if let reference, let refPos = measured.firstIndex(where: { $0.index == reference }) {
            target = .portrait(refPos)
            positions = measured.indices.filter { $0 != refPos }
        } else {
            let preferredPos = preferred.flatMap { p in measured.firstIndex { $0.index == p } }
            guard let choice = SetLightingNormalizer.chooseTarget(stats, preferred: preferredPos) else {
                return LightingResult(adjusted: [], targetName: nil, measured: measured.count)
            }
            target = choice.target
            positions = choice.adjust
        }

        let targetStats: Stats
        let targetName: String?
        switch target {
        case .portrait(let pos):
            targetStats = stats[pos]
            targetName = displayName(inputs[measured[pos].index].name)
        case .centroid(let centroid):
            targetStats = centroid
            targetName = nil
        }

        var adjusted: [(index: Int, adjust: PortraitAdjust)] = []
        for pos in positions {
            let m = measured[pos]
            // Ziet 'ie er al zo uit (mét z'n huidige Adjust)? Dan niets aanraken.
            guard !SetLightingNormalizer.isWithinTolerance(m.renderedStats, targetStats) else { continue }
            let suggestion = SetLightingNormalizer.adjustSuggestion(from: m.rawStats, to: targetStats)
            guard !suggestion.isNeutral else { continue }
            let input = inputs[m.index]
            let refined = SetLightingNormalizer.refine(
                suggestion, raw: m.image, region: m.region, to: targetStats,
                saturation: input.adjust.saturation
            )
            let next = PortraitAdjust(applying: refined, keepingSaturationOf: input.adjust)
            guard next != input.adjust else { continue }
            adjusted.append((m.index, next))
        }
        return LightingResult(adjusted: adjusted, targetName: targetName, measured: measured.count)
    }

    /// Synchrone toepassing (testbaar): Adjust-laag zetten in één undo-groep,
    /// zonder `touch()`. Geeft het aantal gewijzigde portretten terug.
    @discardableResult
    static func applyMatchedLighting(
        _ items: [(Portrait2, PortraitAdjust)],
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) -> Int {
        let changes = items.filter { $0.0.adjust != $0.1 }
        guard !changes.isEmpty else { return 0 }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Match Lighting")
        for (portrait, adjust) in changes {
            let before = portrait.adjust
            setAdjust(adjust, on: portrait, reporter: reporter)
            AdjustUndo.register(
                undoManager, target: portrait,
                apply: { [portrait] value in setAdjust(value, on: portrait, reporter: reporter) },
                undoTo: before, redoTo: adjust, actionName: "Match Lighting"
            )
        }
        undoManager?.endUndoGrouping()
        return changes.count
    }

    // MARK: - Reset adjustments

    /// Adjust-laag van de selectie neutraal — de terugweg voor Match lighting (en
    /// handmatige Adjust) vanuit het raster. Eén undo-groep; portretten die al
    /// neutraal zijn blijven ongemoeid.
    static func resetAdjust(_ targets: [Portrait2], undoManager: UndoManager?, reporter: SetActionReporter) {
        let items = targets.filter { !$0.adjust.isNeutral }
        guard !items.isEmpty else { return }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Reset Adjustments")
        for portrait in items {
            let before = portrait.adjust
            setAdjust(.neutral, on: portrait, reporter: reporter)
            AdjustUndo.register(
                undoManager, target: portrait,
                apply: { [portrait] value in setAdjust(value, on: portrait, reporter: reporter) },
                undoTo: before, redoTo: .neutral, actionName: "Reset Adjustments"
            )
        }
        undoManager?.endUndoGrouping()
        reporter.done(SetActionReceipt(
            title: "Reset adjustments on \(plural(items.count))",
            actionName: "Reset Adjustments",
            undoManager: undoManager
        ))
    }

    /// Adjust-laag zetten zónder `touch()`: revision bumpen (thumbs/canvas
    /// verversen) + canvas-hook. Gedeeld door de actie én z'n undo/redo.
    private static func setAdjust(_ adjust: PortraitAdjust, on portrait: Portrait2, reporter: SetActionReporter) {
        portrait.adjust = adjust
        portrait.bumpRevision()
        reporter.portraitDidChange(portrait)
    }

    // MARK: - Set background

    /// Zelfde achtergrond op alle targets, één undo-groep. `recordsEdit: false`
    /// zodat de rasterorde niet herschudt (ook niet bij undo).
    static func setBackground(
        _ targets: [Portrait2],
        _ background: PortraitBackground,
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) {
        guard !targets.isEmpty else { return }
        let changed = applyBackgrounds(targets.map { ($0, background) }, undoManager: undoManager, reporter: reporter)
        reporter.done(SetActionReceipt(
            title: changed > 0 ? "Set background on \(plural(changed))" : "Background already set",
            actionName: changed > 0 ? "Background" : nil,
            compact: true,
            undoManager: undoManager
        ))
    }

    /// Of "Use folder background" iets zou doen: het portret zit in een map mét
    /// standaardachtergrond, en heeft die nog niet.
    static func canUseFolderBackground(_ portrait: Portrait2) -> Bool {
        guard let background = portrait.folder?.defaultBackground else { return false }
        return portrait.background != background
    }

    /// Zet per portret de standaardachtergrond van z'n eigen map — voor
    /// portretten die vóór de map-default zijn geïmporteerd of later een andere
    /// achtergrond kregen. Zonder map-default, of al gelijk: ongemoeid.
    static func useFolderBackground(_ targets: [Portrait2], undoManager: UndoManager?, reporter: SetActionReporter) {
        let items: [(Portrait2, PortraitBackground)] = targets.compactMap { portrait in
            guard canUseFolderBackground(portrait), let background = portrait.folder?.defaultBackground else { return nil }
            return (portrait, background)
        }
        let changed = applyBackgrounds(items, undoManager: undoManager, reporter: reporter)
        reporter.done(SetActionReceipt(
            title: changed > 0 ? "Set folder background on \(plural(changed))" : "Folder background already set",
            actionName: changed > 0 ? "Background" : nil,
            compact: true,
            undoManager: undoManager
        ))
    }

    /// Synchrone toepassing (testbaar): per portret een eigen achtergrond, één
    /// undo-groep "Background", zonder `touch()`. Geeft het aantal wijzigingen.
    @discardableResult
    static func applyBackgrounds(
        _ items: [(Portrait2, PortraitBackground)],
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) -> Int {
        let changes = items.filter { $0.0.background != $0.1 }
        guard !changes.isEmpty else { return 0 }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Background")
        for (portrait, background) in changes {
            let before = portrait.background
            portrait.setBackground(background, recordsEdit: false)
            reporter.portraitDidChange(portrait)
            ReversibleChange.register(
                undoManager, target: portrait,
                from: before, to: background, actionName: "Background"
            ) { p, bg in
                p.setBackground(bg, recordsEdit: false)
                reporter.portraitDidChange(p)
            }
        }
        undoManager?.endUndoGrouping()
        return changes.count
    }

    // MARK: - Fill in body (E57.3)

    /// Wat Fill in body aan een portret verandert: pixels én transform in één
    /// snapshot (alleen de PNG terugzetten zou de kadrering-sprong terughalen
    /// die E56 juist voorkomt), plus de "schone isolatie"-vlag.
    struct FillBodySnapshot: Equatable {
        let cutoutData: Data
        let transform: TransformUndo.Snapshot
        let derivesFromOriginal: Bool

        init(cutoutData: Data, transform: TransformUndo.Snapshot, derivesFromOriginal: Bool) {
            self.cutoutData = cutoutData
            self.transform = transform
            self.derivesFromOriginal = derivesFromOriginal
        }

        init(of portrait: Portrait2) {
            self.init(
                cutoutData: portrait.cutoutData,
                transform: TransformUndo.snapshot(of: portrait),
                derivesFromOriginal: portrait.cutoutDerivesFromOriginal
            )
        }
    }

    /// Pure stap (testbaar): backend-resultaat + mapping → before/after voor
    /// dit portret, of nil als de cutout ondertussen wijzigde of de mapping
    /// niet op het resultaat past (dan liever niets dan een verschoven kader).
    /// Zelfde geometrie als de editor (`ShellModel.compensatedFillBodyTransform`):
    /// elke bestaande pixel blijft op dezelfde plek, de nieuwe rand komt erbij.
    static func fillBodySnapshots(
        applying image: NSImage,
        mapping: BackendClient.FillBodyResult.Mapping,
        to portrait: Portrait2,
        expectedCutoutSignature: Int
    ) -> (before: FillBodySnapshot, after: FillBodySnapshot)? {
        guard Portrait2.cutoutSignature(portrait.cutoutData) == expectedCutoutSignature,
              let oldCG = NSImage(data: portrait.cutoutData)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil),
              let newCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let transform = ShellModel.compensatedFillBodyTransform(
                oldSize: CGSize(width: oldCG.width, height: oldCG.height),
                newSize: CGSize(width: newCG.width, height: newCG.height),
                mapping: mapping,
                current: TransformUndo.snapshot(of: portrait)
              ),
              let png = image.pngData()
        else { return nil }
        let before = FillBodySnapshot(of: portrait)
        let after = FillBodySnapshot(cutoutData: png, transform: transform, derivesFromOriginal: false)
        return (before, after)
    }

    private struct FillBodyOutcome {
        var results: [(Portrait2, FillBodySnapshot, FillBodySnapshot)] = []
        var nothingToFill = 0
        var failed = 0
        var outOfCredits = false
        var proRequired = false
    }

    /// "Fill in body" op de selectie (E57.3, Edit ▸ in het tegelmenu). Zelfde
    /// contract als de editor-tegel (E56): alleen echt afgesneden randen worden
    /// aangevuld, de gezichtsbox gaat mee als never-paint, zonder afgesneden
    /// rand is de call een gratis server-no-op — vandaar de gate mét gratis
    /// preflight. Sequentieel (geheugen + rate limits), daarna één undo-groep
    /// zodat ⌘Z de hele batch terugdraait. Op is op (402) stopt de batch; wat
    /// al klaar was blijft.
    static func fillBody(
        _ targets: [Portrait2],
        entitlement: EntitlementModel,
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) {
        guard !targets.isEmpty else { return }
        guard entitlement.allowAIFeatureWithFreeServerPreflight(.restoreBody, retry: {
            fillBody(targets, entitlement: entitlement, undoManager: undoManager, reporter: reporter)
        }) else { return }
        let total = targets.count
        reporter.busy("Filling in body…")
        Task {
            defer { reporter.busy(nil) }
            var outcome = FillBodyOutcome()
            for (index, portrait) in targets.enumerated() {
                if total > 1 { reporter.busy("Filling in body \(index + 1) of \(total)…") }
                let source = portrait.cutoutData
                let signature = Portrait2.cutoutSignature(source)
                do {
                    let faceBox = await fillBodyFaceBox(pngData: source)
                    let result = try await entitlement.backend.fillBodyDetailed(imagePNG: source, faceBox: faceBox)
                    guard result.didFill else {
                        outcome.nothingToFill += 1
                        continue
                    }
                    // Onleesbare bytes of een mapping die niet past (of een
                    // tussentijds bewerkt portret): overslaan, niet gokken.
                    guard let image = NSImage(data: result.data),
                          let snapshots = fillBodySnapshots(
                            applying: image, mapping: result.mapping,
                            to: portrait, expectedCutoutSignature: signature
                          )
                    else {
                        outcome.failed += 1
                        continue
                    }
                    outcome.results.append((portrait, snapshots.before, snapshots.after))
                } catch BackendError.noCredits {
                    outcome.outOfCredits = true
                    break
                } catch BackendError.proRequired {
                    outcome.proRequired = true
                    break
                } catch {
                    outcome.failed += 1
                }
            }
            let n = applyFilledBodies(outcome.results, undoManager: undoManager, reporter: reporter)
            // Ook bij no-ops verversen: de server kan credits hebben afgeschreven.
            await entitlement.refresh()
            if outcome.outOfCredits { entitlement.handleOutOfCredits() }
            if outcome.proRequired { entitlement.requestUpgrade() }
            reporter.done(fillBodyReceipt(
                applied: n, total: total, nothingToFill: outcome.nothingToFill,
                failed: outcome.failed, outOfCredits: outcome.outOfCredits, undoManager: undoManager
            ))
        }
    }

    /// Vision-gezichtsbox (genormaliseerd) zoals de editor 'm meestuurt: het
    /// gezicht is never-paint in het outpaint-masker. Decode + Vision off-main.
    private static func fillBodyFaceBox(pngData: Data) async -> BackendClient.FaceBox? {
        await Task.detached(priority: .userInitiated) { () -> BackendClient.FaceBox? in
            guard let cg = NSImage(data: pngData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let rect = AutoFramer.metrics(for: cg).faceRect
            return EditorView.normalizedFillBodyFaceBox(
                faceRect: rect, imageSize: CGSize(width: cg.width, height: cg.height)
            )
        }.value
    }

    /// Bon voor de Fill in body-batch (testbaar). Eén portret krijgt dezelfde
    /// copy als de editor ("Body completed" / "Nothing to fill").
    static func fillBodyReceipt(
        applied: Int, total: Int, nothingToFill: Int, failed: Int, outOfCredits: Bool, undoManager: UndoManager?
    ) -> SetActionReceipt {
        let title: String
        var detail: String?
        if applied == 0 {
            if outOfCredits {
                title = "Out of credits — nothing filled in"
            } else if nothingToFill == total {
                title = total == 1 ? "Nothing to fill" : "Nothing to fill on \(plural(total))"
                detail = total == 1
                    ? "No cropped body edge was found. Try Auto-frame & center instead."
                    : "No cropped body edges were found."
            } else {
                title = "Couldn't fill in the body"
                detail = "Please try again."
            }
        } else if applied == total {
            title = total == 1 ? "Body completed" : "Filled in body on \(plural(total))"
            if total == 1 { detail = "Only the cropped edge was filled." }
        } else {
            title = "Filled in body on \(applied) of \(plural(total))"
            var parts: [String] = []
            if nothingToFill > 0 {
                parts.append(nothingToFill == 1 ? "1 had nothing to fill." : "\(nothingToFill) had nothing to fill.")
            }
            if failed > 0 {
                parts.append(failed == 1 ? "1 couldn't be filled." : "\(failed) couldn't be filled.")
            }
            if outOfCredits { parts.append("Ran out of credits for the rest.") }
            detail = parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        return SetActionReceipt(
            title: title, detail: detail,
            actionName: applied > 0 ? "Fill in body" : nil,
            undoManager: undoManager
        )
    }

    /// Synchrone toepassing (testbaar): pixels + transform per portret, één
    /// undo-groep "Fill in body", `bumpRevision()` i.p.v. `touch()` (E50.3:
    /// het raster herschudt niet). Geeft het aantal gewijzigde portretten terug.
    @discardableResult
    static func applyFilledBodies(
        _ items: [(Portrait2, FillBodySnapshot, FillBodySnapshot)],
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) -> Int {
        let changes = items.filter { $0.1 != $0.2 }
        guard !changes.isEmpty else { return 0 }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Fill in body")
        for (portrait, before, after) in changes {
            applyFillBody(after, on: portrait, reporter: reporter)
            ReversibleChange.register(
                undoManager, target: portrait, from: before, to: after, actionName: "Fill in body"
            ) { p, snapshot in
                applyFillBody(snapshot, on: p, reporter: reporter)
            }
        }
        undoManager?.endUndoGrouping()
        return changes.count
    }

    private static func applyFillBody(_ snapshot: FillBodySnapshot, on portrait: Portrait2, reporter: SetActionReporter) {
        portrait.cutoutData = snapshot.cutoutData
        portrait.offsetX = snapshot.transform.offsetX
        portrait.offsetY = snapshot.transform.offsetY
        portrait.scale = snapshot.transform.scale
        portrait.cutoutDerivesFromOriginal = snapshot.derivesFromOriginal
        portrait.bumpRevision()
        reporter.portraitDidChange(portrait)
    }

    // MARK: - Boost resolution

    /// Wat een Boost aan een portret verandert — één undo-waarde per portret.
    /// `scale` gaat mee omdat een hogere-res cutout met dezelfde ratio de
    /// canvas-schaal bijstelt (positie + crop blijven staan, zoals in de editor).
    struct BoostSnapshot: Equatable {
        let cutoutData: Data
        let scale: Double
        let derivesFromOriginal: Bool

        init(cutoutData: Data, scale: Double, derivesFromOriginal: Bool) {
            self.cutoutData = cutoutData
            self.scale = scale
            self.derivesFromOriginal = derivesFromOriginal
        }

        init(of portrait: Portrait2) {
            self.init(
                cutoutData: portrait.cutoutData, scale: portrait.scale,
                derivesFromOriginal: portrait.cutoutDerivesFromOriginal
            )
        }
    }

    /// Uitkomst van het rekenwerk vóór de synchrone toepassing.
    private struct BoostOutcome {
        var results: [(Portrait2, Data)] = []
        var failed = 0
        var outOfCredits = false
    }

    /// "Boost resolution" op de selectie (aanvulling Thierry 2026-09-02: ook via
    /// het bulk-tegelmenu). Zelfde twee modi als de editor-chip: `.local` =
    /// gratis on-device Lanczos (`LocalUpscale`), `.online` = Topaz via de
    /// backend (3 credits per portret, privacy-/sign-in-/credits-gate vooraf).
    /// Sequentieel (één beeld tegelijk: geheugen + rate limits), off-main; de
    /// toepassing gebeurt daarna in één undo-groep zodat ⌘Z de hele batch
    /// terugdraait. Op is op (402) stopt de batch; wat al klaar was blijft.
    static func boostResolution(
        _ targets: [Portrait2],
        mode: BoostMode,
        entitlement: EntitlementModel,
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) {
        guard !targets.isEmpty else { return }
        if mode == .online {
            guard entitlement.allowAIFeature(.boostOnline, retry: {
                boostResolution(
                    targets, mode: mode, entitlement: entitlement,
                    undoManager: undoManager, reporter: reporter
                )
            }) else { return }
        }
        let total = targets.count
        reporter.busy("Boosting resolution…")
        Task {
            defer { reporter.busy(nil) }
            var outcome = BoostOutcome()
            for (index, portrait) in targets.enumerated() {
                if total > 1 { reporter.busy("Boosting \(index + 1) of \(total)…") }
                let source = portrait.cutoutData
                var output: Data?
                switch mode {
                case .local:
                    output = await Task.detached(priority: .userInitiated) {
                        LocalUpscale.boost(pngData: source)
                    }.value
                case .online:
                    do {
                        let (data, _) = try await entitlement.backend.upscale(imagePNG: source, quality: .high)
                        // Zoals de editor: decoderen + op pixelmaat normaliseren
                        // (cloud-bytes komen vaak als 72-DPI) en als PNG bewaren.
                        output = await Task.detached(priority: .userInitiated) {
                            NSImage(data: data)?.normalizedToPixelSize().pngData()
                        }.value
                    } catch BackendError.noCredits {
                        outcome.outOfCredits = true
                    } catch {
                        output = nil
                    }
                }
                if outcome.outOfCredits { break }
                // Her-valideer: een tussentijds bewerkt portret slaan we over.
                guard let output, portrait.cutoutData == source else {
                    outcome.failed += 1
                    continue
                }
                outcome.results.append((portrait, output))
            }
            let n = applyBoosted(outcome.results, undoManager: undoManager, reporter: reporter)
            if mode == .online { await entitlement.refresh() }
            if outcome.outOfCredits { entitlement.handleOutOfCredits() }
            reporter.done(boostReceipt(
                applied: n, total: total, failed: outcome.failed,
                outOfCredits: outcome.outOfCredits, undoManager: undoManager
            ))
        }
    }

    /// Bon voor de Boost-batch (testbaar): wat is gelukt, wat niet, en waarom.
    static func boostReceipt(
        applied: Int, total: Int, failed: Int, outOfCredits: Bool, undoManager: UndoManager?
    ) -> SetActionReceipt {
        let title: String
        var detail: String?
        if applied == 0 {
            title = outOfCredits ? "Out of credits — nothing boosted" : "Couldn't boost the resolution"
            if !outOfCredits { detail = "Please try again." }
        } else if applied == total {
            title = "Boosted resolution on \(plural(applied))"
        } else {
            title = "Boosted resolution on \(applied) of \(plural(total))"
            if outOfCredits {
                detail = "Ran out of credits for the rest."
            } else if failed > 0 {
                detail = failed == 1 ? "1 portrait couldn't be boosted." : "\(failed) portraits couldn't be boosted."
            }
        }
        return SetActionReceipt(
            title: title, detail: detail,
            actionName: applied > 0 ? "Boost Resolution" : nil,
            undoManager: undoManager
        )
    }

    /// Synchrone toepassing (testbaar): nieuwe cutout-bytes per portret, schaal
    /// bijgesteld op de breedte-verhouding (alleen als er een handmatige schaal
    /// staat), één undo-groep "Boost Resolution", zonder `touch()`. Geeft het
    /// aantal gewijzigde portretten terug.
    @discardableResult
    static func applyBoosted(
        _ items: [(Portrait2, Data)],
        undoManager: UndoManager?,
        reporter: SetActionReporter
    ) -> Int {
        let changes = items.filter { $0.0.cutoutData != $0.1 }
        guard !changes.isEmpty else { return 0 }
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Boost Resolution")
        for (portrait, data) in changes {
            let before = BoostSnapshot(of: portrait)
            var scale = portrait.scale
            if scale > 0, let oldWidth = pngPixelWidth(before.cutoutData), let newWidth = pngPixelWidth(data) {
                scale = ShellModel.adjustedScaleForResolutionChange(
                    oldWidth: oldWidth, newWidth: newWidth, currentScale: scale
                )
            }
            // Een upscale is geen schone isolatie van de originele foto meer
            // (zelfde regel als de editor-Boost via `storeEffectResult`).
            let after = BoostSnapshot(cutoutData: data, scale: scale, derivesFromOriginal: false)
            applyBoost(after, on: portrait, reporter: reporter)
            ReversibleChange.register(
                undoManager, target: portrait, from: before, to: after, actionName: "Boost Resolution"
            ) { p, snapshot in
                applyBoost(snapshot, on: p, reporter: reporter)
            }
        }
        undoManager?.endUndoGrouping()
        return changes.count
    }

    private static func applyBoost(_ snapshot: BoostSnapshot, on portrait: Portrait2, reporter: SetActionReporter) {
        portrait.cutoutData = snapshot.cutoutData
        portrait.scale = snapshot.scale
        portrait.cutoutDerivesFromOriginal = snapshot.derivesFromOriginal
        portrait.bumpRevision()
        reporter.portraitDidChange(portrait)
    }

    /// Pixelbreedte uit de PNG-header (ImageIO leest geen pixels) — goedkoop
    /// genoeg voor de main-actor. nil bij onleesbare bytes.
    nonisolated static func pngPixelWidth(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, width > 0 else { return nil }
        return width
    }

    // MARK: - Export

    /// Exporteer de selectie naar een gekozen map (free = watermerk).
    static func export(_ targets: [Portrait2], isPro: Bool, reporter: SetActionReporter) {
        guard !targets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"
        panel.message = "Choose a folder to export the selected portraits"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        reporter.busy("Exporting \(plural(targets.count))…")
        Task {
            defer { reporter.busy(nil) }
            // Dedupliceer binnen de batch: twee portretten met dezelfde naam
            // worden "Naam.png", "Naam-2.png", "Naam-3.png" i.p.v. elkaar stil
            // te overschrijven.
            var usedNames: Set<String> = []
            var written = 0
            for (i, p) in targets.enumerated() {
                // Off-main render (makePNGAsync) — de compositing blokkeert de UI niet.
                guard let data = await PortraitExporter.makePNGAsync(for: p, watermark: !isPro, shape: p.frameShape) else { continue }
                let trimmed = p.name.trimmingCharacters(in: .whitespaces)
                let base = trimmed.isEmpty ? "portrait-\(i + 1)" : trimmed.replacingOccurrences(of: "/", with: "-")
                var name = base
                var counter = 2
                while usedNames.contains(name.lowercased()) {
                    name = "\(base)-\(counter)"
                    counter += 1
                }
                usedNames.insert(name.lowercased())
                if (try? data.write(to: dir.appendingPathComponent(name + ".png"))) != nil { written += 1 }
            }
            reporter.done(SetActionReceipt(
                title: "Exported \(plural(written)) to \(dir.lastPathComponent)",
                actionName: nil,
                undoManager: nil
            ))
        }
    }

    // MARK: - Copy

    /// "1 portrait" / "3 portraits".
    static func plural(_ n: Int) -> String {
        n == 1 ? "1 portrait" : "\(n) portraits"
    }

    /// Naam voor de toast; lege naam → zoals de tegel 'm toont.
    nonisolated static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
