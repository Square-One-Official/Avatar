// 37.18 (audit-B6) — Eenmalige migratie: vóór commit d1ec4e7 werd de literal
// placeholder-string ("Type to enter text") als échte `layer.string` opgeslagen
// én in `previewImageData` meegebakken; bestaande banners dragen die lagen nog.
// Deze sweep loopt één keer over ALLE BannerDocs, dropt lege/placeholder-lagen
// (`BannerDoc.dropEmptyTextLayers`) en herbakt previews — zodat gallery/Home/
// chooser/E40-achtergrond geen stale bake met meegebakken placeholder meer
// tonen. Idempotent; het UserDefaults-stempel voorkomt alleen onnodig herwerk.
// Documenten die deze bulk-run zouden missen worden alsnog gedekt door de
// Studio-open/-close-sweep (BannerStudioView) én de render-guard in
// BannerDocRenderer (placeholder-lagen komen in geen enkele render terecht).
//
// v2 (UXS-5/UX1): de audit zag ná de v1-sweep nog soep — (a) de matcher miste
// het legacy "Your text"-literal van het oude Text-paneel (E37.4), en (b) docs
// waarvan de lagen al schoon waren maar wier preview vóór de render-guard was
// gebakken werden nooit herbakken. De v2-run matcht breder
// (`BannerTextPresets.legacyPlaceholders`), herbakt ÁLLE bestaande bakes
// eenmalig, en stempelt pas ná een voltooide run (een afgebroken run herkanst).

import AppKit
import Foundation
import SwiftData

@MainActor
enum BannerPlaceholderMigration {
    static let defaultsKey = "banners.placeholderLayerSweep.v2"

    /// Draait de sweep éénmalig (per defaults-store). Aanroepen vanaf elke plek
    /// waar banner-previews zichtbaar worden (BannersGalleryView.task,
    /// HomeView.task).
    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        let docs = (try? context.fetch(FetchDescriptor<BannerDoc>())) ?? []
        for doc in docs {
            let droppedLayers = doc.dropEmptyTextLayers() != nil
            // Geforceerde herbake (UXS-5): ook een doc mét schone lagen kan een
            // stale bake dragen (preview gebakken vóór de render-guard, of een
            // Studio-close-sweep zonder afgeronde bake).
            guard droppedLayers || doc.previewImageData != nil else { continue }
            await rebakePreview(doc)
        }
        // Stempel pas ná de voltooide sweep: crasht/stopt de app halverwege,
        // dan draait de run bij de volgende kans opnieuw (idempotent).
        defaults.set(true, forKey: defaultsKey)
    }

    /// Herbakt `previewImageData` (render + PNG-encode off-main; alleen het
    /// schrijven naar het @Model op de main-actor — zelfde contract als
    /// `BannerStudioView.bakeThumbnail`).
    static func rebakePreview(_ doc: BannerDoc) async {
        guard let cg = await BannerDocRenderer.composedImageAsync(doc) else { return }
        let box = SendableCGImage(cgImage: cg)
        let png = await Task.detached(priority: .utility) {
            NSBitmapImageRep(cgImage: box.cgImage).representation(using: .png, properties: [:])
        }.value
        guard let png, doc.modelContext != nil else { return }
        doc.previewImageData = png
    }
}
