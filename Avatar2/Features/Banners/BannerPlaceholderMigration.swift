// 37.18 (audit-B6) — Eenmalige migratie: vóór commit d1ec4e7 werd de literal
// placeholder-string ("Type to enter text") als échte `layer.string` opgeslagen
// én in `previewImageData` meegebakken; bestaande banners dragen die lagen nog.
// Deze sweep loopt één keer over ALLE BannerDocs, dropt lege/placeholder-lagen
// (`BannerDoc.dropEmptyTextLayers`) en herbakt de preview van gewijzigde
// documenten — zodat gallery/chooser/E40-achtergrond geen stale bake met
// meegebakken placeholder meer tonen. Idempotent; het UserDefaults-stempel
// voorkomt alleen onnodig herwerk. Documenten die deze bulk-run zouden missen
// worden alsnog gedekt door de Studio-open/-close-sweep (BannerStudioView).

import AppKit
import Foundation
import SwiftData

@MainActor
enum BannerPlaceholderMigration {
    static let defaultsKey = "banners.placeholderLayerSweep.v1"

    /// Draait de sweep éénmalig (per defaults-store). Aanroepen vanaf een plek
    /// waar de banner-bibliotheek zichtbaar wordt (BannersGalleryView.task).
    static func runIfNeeded(context: ModelContext, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        defaults.set(true, forKey: defaultsKey)
        let docs = (try? context.fetch(FetchDescriptor<BannerDoc>())) ?? []
        for doc in docs {
            guard doc.dropEmptyTextLayers() != nil else { continue }
            await rebakePreview(doc)
        }
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
