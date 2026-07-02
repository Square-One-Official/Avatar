// E52.1 — gedeelde cel-view voor CMS-thumbnails (backgrounds, effects,
// banner-presets, face-presets). Vervangt de AsyncImage + per-panel-NSCache-
// combinatie: AsyncImage leunt op URLCache, maar Supabase Storage stuurt
// `Cache-Control: no-cache`, dus elke panel-open downloadde opnieuw. Deze view
// leest synchroon de memory-laag van `ThumbnailCache` (instant bij her-open)
// en laadt anders async via disk/netwerk met downsampled decode.
//
// N.B. los van `ThumbnailStore` (Features/Shared): die decodeert LOKALE
// portret-data (SwiftData) — dit is de remote-URL-tegenhanger (AvatarKit).

import AppKit
import AvatarKit
import SwiftUI

struct RemoteThumbnail<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            // Synchrone memory-hit eerst: her-openen van een panel rendert dan
            // in dezelfde frame, zonder placeholder-flits.
            if let hit = ThumbnailCache.shared.cachedImage(for: url) {
                image = hit
                return
            }
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}
