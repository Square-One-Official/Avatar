// Gedeelde actielijst voor de subject-edit-panelen (E21.1). Eén kolom met
// secties; elke rij toont links een optioneel leading-icoon + titel, daaronder
// de credit-kost (subtiel grijs, E18.13), rechts een aan/uit-checkmark
// (E18.12) en — voor niet-Pro — een Pro-badge als gating-indicator. Gebruikt
// door zowel Edit (kleur/technisch) als Face (beauty).

import AvatarKit
import AvatarUI
import SwiftUI

struct EditorAction: Identifiable {
    let id = UUID()
    let title: String
    /// E14.3: credit-tier voor het kosten-label. nil = lokaal/gratis.
    var meter: CreditMeter.Action? = nil
    var isCloud: Bool = false
    var handler: (() -> Void)? = nil
    /// E18.12: toggle-acties tonen een aan/uit-staat.
    var isOn: Bool = false
    /// E20.2/21.3: leading-icoon (semantisch, DSIcon). nil = geen icoon.
    var icon: DSIcon.Symbol? = nil
}

struct EditorActionSection: Identifiable {
    let id = UUID()
    let title: String
    let actions: [EditorAction]
}

struct EditorActionList: View {
    let sections: [EditorActionSection]
    var isPro: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap4) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: DSSpacing.gap2) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .dsTextStyle(.bodySmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                    ForEach(section.actions) { row($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ action: EditorAction) -> some View {
        Button {
            action.handler?()
        } label: {
            HStack(spacing: DSSpacing.gap2) {
                if let icon = action.icon {
                    DSIcon(icon, size: 20)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: DSSpacing.gap1) {
                    Text(action.title)
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Foreground.primary)
                        .lineLimit(1)
                    if let meter = action.meter {
                        Text(CreditMeter.chipLabel(for: meter))
                            .dsTextStyle(.labelSmall)
                            .foregroundStyle(DSColor.Foreground.muted)
                    }
                }
                Spacer(minLength: DSSpacing.gap2)
                if action.isOn {
                    Image(systemName: "checkmark")
                        .dsTextStyle(.labelBase)
                        .foregroundStyle(DSColor.Action.primary)
                }
                if action.isCloud && !isPro {
                    DSProChip()
                }
            }
            .padding(.horizontal, DSSpacing.gap4)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(action.isOn ? DSColor.Background.neutralStronger : DSColor.Background.neutral)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl))
            .overlay {
                if action.isOn {
                    RoundedRectangle(cornerRadius: DSRadius.xl)
                        .strokeBorder(DSColor.Action.primary, lineWidth: DSBorderWidth.medium)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.xl))
        }
        .buttonStyle(.plain)
        .opacity(action.handler == nil ? 0.55 : 1)
        .disabled(action.handler == nil)
    }
}
