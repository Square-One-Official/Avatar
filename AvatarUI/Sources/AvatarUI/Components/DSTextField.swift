// Figma "Components" → Input (59:621), zoals gebruikt in Onboarding / Email
// (dark). Kolom: optioneel label (UI/Labels/Base, muted) met gap-1.5 boven
// het veld. Veld: h40 (py gap-2.5 + regel 20), px gap-4, gap-2, bg
// background/neutral, capsule (r-full), rand b-thin — divider in rust,
// muted bij focus (State=Active). Tekst Content/Body/Small: placeholder
// muted, waarde primary. Disabled volgt de Figma-opacityschaal.

import SwiftUI

public struct DSTextField: View {
    private let label: String?
    private let placeholder: String
    private let icon: Image?
    @Binding private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(
        label: String? = nil,
        placeholder: String,
        icon: Image? = nil,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.icon = icon
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.gap1_5) {
            if let label {
                Text(label)
                    .dsTextStyle(.labelBase)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .lineLimit(1)
            }
            HStack(spacing: DSSpacing.gap2) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
                TextField(
                    "",
                    text: $text,
                    prompt: Text(placeholder).foregroundStyle(DSColor.Foreground.muted)
                )
                .textFieldStyle(.plain)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.primary)
                .focused($isFocused)
            }
            .padding(.horizontal, DSSpacing.gap4)
            .padding(.vertical, DSSpacing.gap2_5)
            .background(DSColor.Background.neutral, in: Capsule())
            .overlay {
                Capsule().strokeBorder(
                    isFocused ? DSColor.Foreground.muted : DSColor.Foreground.divider,
                    lineWidth: DSBorderWidth.thin
                )
            }
        }
        .opacity(isEnabled ? DSOpacity.strong : DSOpacity.disabled)
    }
}
