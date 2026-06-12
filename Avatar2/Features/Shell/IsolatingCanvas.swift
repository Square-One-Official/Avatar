// Isolating-animatie (E05.3, Figma: App / Image added 4017:1817 + App /
// Isolating animation "Background fading dark loop" 4017:1762). Fase 1:
// volle foto (r-2xl) met status-pill "Removing background...". Fase 2
// (cutout klaar): de achtergrond fadet naar donker — app-achtergrondlaag
// animeert over het origineel terwijl de cutout (alleen persoon-pixels)
// erbovenop ligt; status "Cutting out hair...". De pill (Figma
// "Recording": h48, 32-container + label, rechtsonder) toont een kleine
// activity-indicator in de logo-container; het frame exposeert daar geen
// eigen asset voor.

import AvatarUI
import SwiftUI

struct IsolatingCanvas: View {
    let original: NSImage
    /// nil = fase 1 (cutout rekent nog); gevuld = fase 2 (reveal).
    let cutout: NSImage?

    @State private var backgroundFaded = false

    var body: some View {
        Image(nsImage: original)
            .resizable()
            .scaledToFit()
            .overlay {
                DSColor.Background.app
                    .opacity(backgroundFaded ? 1 : 0)
            }
            .overlay {
                if let cutout {
                    Image(nsImage: cutout)
                        .resizable()
                        .scaledToFit()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
            .padding(DSSpacing.gap8)
            .onChange(of: cutout != nil, initial: true) { _, hasCutout in
                guard hasCutout else { return }
                withAnimation(.easeInOut(duration: IsolatingTiming.backgroundFade)) {
                    backgroundFaded = true
                }
            }
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
