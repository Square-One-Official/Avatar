// Isolating-animatie (E05.3 + E04.5-fix, Figma: App / Image added
// 4017:1817 + App / Isolating animation 4017:1762). De foto leeft in de
// canvas-kaart (DSCanvasCard, bevinding 6/11) — vast 1:1 (exportformaat);
// fase 1 toont het origineel gevuld, fase 2 fadet een app-achtergrondlaag
// over het origineel terwijl de cutout erbovenop ligt. De status-pill
// (Figma "Recording") hangt op vensterniveau in ShellView (bevinding 3).

import AvatarUI
import SwiftUI

struct IsolatingCanvas: View {
    let original: NSImage
    /// nil = fase 1 (cutout rekent nog); gevuld = fase 2 (reveal).
    let cutout: NSImage?

    var body: some View {
        DSCanvasCard {
            IsolatingFrameLayer(original: original, cutout: cutout)
        }
        .frame(maxWidth: 456, maxHeight: 456)
        .padding(.vertical, DSSpacing.gap8)
    }
}

/// De reveal-laag (E05.3): origineel gevuld → een app-achtergrondlaag fadet
/// erover terwijl de cutout erbovenop verschijnt. Gedeeld door de full-screen
/// `IsolatingCanvas` (eerste import) én de in-frame editor-isolating (E-fix:
/// bij een VERVANGENDE import blijft de editor-scaffold staan en speelt de
/// reveal ín het frame i.p.v. het hele scherm te vervangen). De clip-vorm
/// verschilt per context: de kaart-rechthoek (full-screen) of de frame-vorm
/// (cirkel) in de editor.
struct IsolatingFrameLayer: View {
    let original: NSImage
    let cutout: NSImage?
    var clipShape: AnyShape = AnyShape(Rectangle())
    /// Full-screen (eerste import) VULT de kaart (`.fill`, Figma-gedrag). In het
    /// editor-frame PAST de foto IN het frame (`.fit`): een staande foto zou met
    /// `.fill` tot een gezichts-crop inzoomen ("zoomt in bij droppen") — `.fit`
    /// toont de hele foto, dezelfde kadrering als de uiteindelijke (padded-fit) cutout.
    var fills = true

    @State private var backgroundFaded = false

    var body: some View {
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
            .clipShape(clipShape)
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
            .aspectRatio(contentMode: fills ? .fill : .fit)
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
