// Isolating-animatie (E05.3 + E04.5-fix, Figma: App / Image added
// 4017:1817 + App / Isolating animation 4017:1762). De foto leeft in de
// canvas-kaart (DSCanvasCard, bevinding 6) op het frameformaat 465×456;
// fase 1 toont het origineel gevuld, fase 2 fadet een app-achtergrondlaag
// over het origineel terwijl de cutout erbovenop ligt. De status-pill
// (Figma "Recording") hangt op vensterniveau in ShellView (bevinding 3).

import AvatarUI
import SwiftUI

struct IsolatingCanvas: View {
    let original: NSImage
    /// nil = fase 1 (cutout rekent nog); gevuld = fase 2 (reveal).
    let cutout: NSImage?

    @State private var backgroundFaded = false

    var body: some View {
        DSCanvasCard {
            portraitLayer(original)
                .overlay {
                    DSColor.Background.app
                        .opacity(backgroundFaded ? 1 : 0)
                }
                .overlay {
                    if let cutout {
                        portraitLayer(cutout)
                    }
                }
        }
        .aspectRatio(465.0 / 456.0, contentMode: .fit)
        .frame(maxWidth: 465, maxHeight: 456)
        .padding(.vertical, DSSpacing.gap8)
        .onChange(of: cutout != nil, initial: true) { _, hasCutout in
            guard hasCutout else { return }
            withAnimation(.easeInOut(duration: IsolatingTiming.backgroundFade)) {
                backgroundFaded = true
            }
        }
    }

    private func portraitLayer(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

/// Eén plek voor de reveal-timing: de view animeert de zwartfade, het
/// model wacht dezelfde duur vóór de overstap naar .result.
enum IsolatingTiming {
    static let backgroundFade: TimeInterval = 0.8
    static let settle: TimeInterval = 0.2
}

/// Status-pill rechtsonder (Figma "Recording"): capsule h48 bg Card,
/// padding gap-2, 32-container met kleine activity-indicator, label
/// Labels/Small subtle.
struct IsolatingStatusPill: View {
    let label: String

    var body: some View {
        HStack(spacing: DSSpacing.gap3) {
            ZStack {
                Circle()
                    .fill(DSColor.Background.neutral)
                    .frame(width: 32, height: 32)
                ProgressView()
                    .controlSize(.small)
            }
            Text(label)
                .dsTextStyle(.labelSmall)
                .foregroundStyle(DSColor.Foreground.subtle)
                .padding(.trailing, DSSpacing.gap2)
        }
        .padding(DSSpacing.gap2)
        .background(DSColor.Background.card, in: Capsule())
    }
}
