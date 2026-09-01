// Enhance-paneel — één-tik AI-acties (Retouch/Studio Light/Portrait/Colorise/
// Boost/Restore body) als compacte chips. Handmatige color-sliders leven in
// AdjustPanel (aparte toolbar-tool) zodat het portret zichtbaar blijft tijdens
// aanpassen.
// One-click retouch verhuisde hierheen uit het Face-paneel (Thierry, 2026-06-23).

import AvatarKit
import AvatarUI
import SwiftUI

struct EditColorPanel: View {
    /// One-click retouch (lokaal) — verhuisd uit Face (Thierry, 2026-06-23). Toont
    /// als eerste chip wanneer `showRetouch`.
    var onRetouch: () -> Void = {}
    var onStudioLight: () -> Void = {}
    /// Portrait-modus (achtergrond-blur) aan/uit — verhuist niet, blurt de
    /// achtergrondLAAG en houdt het onderwerp scherp (macOS-webcam-Portrait).
    var onPortrait: () -> Void = {}
    var onColorise: () -> Void = {}
    var onBoost: () -> Void = {}
    // E31.3: Restore body verhuisde mee uit de frame-toolbar-AI-dropdown.
    var onRestoreBody: () -> Void = {}
    var isPro: Bool = false
    /// E24.28: of de lokale "Studio Light"-toggle momenteel AAN staat.
    var studioLightOn: Bool = false
    /// Of "Portrait" (achtergrond-blur) momenteel AAN staat.
    var portraitOn: Bool = false
    /// One-click retouch-toggle AAN (editor); op de board een one-shot (false).
    var retouchOn: Bool = false
    /// Toon de "One click retouch"-chip als eerste in de één-tik-rij. Default uit
    /// zodat de board batch-adjust 'm niet toont (retouch = per beeld).
    var showRetouch: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.gap2) {
                // One-click retouch verhuisde hierheen uit Face — eerste chip.
                if showRetouch {
                    quickAction("One click retouch", icon: "wand.and.stars", isOn: retouchOn, action: onRetouch)
                }
                quickAction("Studio Light", icon: "sun.max", isOn: studioLightOn, action: onStudioLight)
                // Portrait: vervaagt de achtergrond (origineel/custom), onderwerp scherp.
                quickAction("Portrait", icon: "camera.aperture", isOn: portraitOn, action: onPortrait)
                quickAction("Colorise", icon: "paintbrush.pointed", pro: !isPro, action: onColorise)
                quickAction("Boost", icon: "arrow.up.backward.and.arrow.down.forward",
                            credit: CreditMeter.chipLabel(for: .upscale), action: onBoost)
                // E31.3: Restore body uit de oude frame-toolbar-AI-dropdown.
                quickAction("Restore body", icon: "person.crop.rectangle", pro: !isPro, action: onRestoreBody)
            }
            .padding(.vertical, DSSpacing.gap1)
            .scrollRowTrailingInset()
        }
        .horizontalScrollEdgeFade()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// E24.27/24.28: compacte één-tik-actie-chip met optionele Pro-badge/credit
    /// en — voor toggle-acties — een duidelijke active-state (lime fill + check).
    private func quickAction(_ label: String, icon: String, pro: Bool = false,
                             credit: String? = nil, isOn: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.gap1) {
                Image(systemName: isOn ? "checkmark" : icon).font(.system(size: 12, weight: .medium))
                Text(label).dsTextStyle(.labelSmall)
                if pro {
                    DSProChip()
                } else if let credit {
                    DSBadge(credit, type: .neutral, compact: true)
                }
            }
            // E24.28: lime fill + onAction-tekst als de toggle AAN staat.
            .foregroundStyle(isOn ? DSColor.Action.onAction : DSColor.Foreground.primary)
            .padding(.horizontal, DSSpacing.gap2)
            .frame(height: 32)
            .background(isOn ? DSColor.Action.primary : DSColor.Background.neutral, in: Capsule())
        }
        .buttonStyle(.plain)
        .dsHoverScale()
        .fixedSize()
    }
}
