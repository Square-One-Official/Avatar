// Tijdelijke bibliotheek-tegel voor een batch-import (drop van meerdere
// bestanden, zie `ShellModel.importImages`). Staat in het grid op de plek
// waar het portret straks landt en speelt dezelfde isolating-crossfade als
// de studio (`IsolatingTiming`): het origineel vult de tegel en fadet, zodra
// de cutout klaar is, weg naar de uiteindelijke compositie (cutout op de
// map-achtergrond — exact de render die de echte tegel daarna toont). Niet
// klikbaar: er is nog geen portret.

import AvatarUI
import SwiftUI

struct LibraryImportTile: View {
    let job: ShellModel.LibraryImportJob

    @State private var originalFaded = false

    private var preview: NSImage? {
        if case .revealing(let preview) = job.phase { return preview }
        return nil
    }

    private var isFailed: Bool {
        if case .failed = job.phase { return true }
        return false
    }

    var body: some View {
        // Zelfde vierkant + hoekstraal + rand als PortraitGridTile, zodat de
        // wissel tegel → portret geen vorm verandert.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { composed }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xl2, style: .continuous)
                    .strokeBorder(DSColor.Foreground.divider, lineWidth: DSBorderWidth.thin)
            )
            .onChange(of: preview != nil, initial: true) { _, hasPreview in
                guard hasPreview else { return }
                // Pure opacity-reveal → mag óók onder reduce-motion lopen (E53.4),
                // net als IsolatingFrameLayer.
                DSMotion.animateCrossFade(.easeInOut(duration: IsolatingTiming.backgroundFade)) {
                    originalFaded = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    private var composed: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                DSColor.Background.inset
                if let preview {
                    layer(preview)
                }
                layer(job.original)
                    .opacity(originalFaded ? 0 : (isFailed ? 0.4 : 1))
            }

            // Zelfde naam-scrim als de echte tegel; de status komt op de rol-regel.
            DSCardLabelScrim()

            VStack(alignment: .leading, spacing: 0) {
                Text(job.name.isEmpty ? "Untitled" : job.name)
                    .dsTextStyle(.labelBase).foregroundStyle(.white).lineLimit(1)
                Text(statusText)
                    .dsTextStyle(.labelSmall).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            .padding(DSSpacing.gap3)
        }
        .dsMotion(DSMotion.micro, value: isFailed)
    }

    private var statusText: String {
        switch job.phase {
        case .queued: "Waiting…"
        case .isolating: "Removing background…"
        case .revealing: "Cutting out hair…"
        case .failed: "Couldn't find a person"
        }
    }

    private var accessibilityLabel: String {
        let name = job.name.isEmpty ? "Untitled portrait" : job.name
        return "\(name), \(statusText)"
    }

    private func layer(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
