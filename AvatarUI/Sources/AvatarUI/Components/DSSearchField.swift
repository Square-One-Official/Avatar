// Figma "Components" → Search input (4016:14176; sidebar-instance 224×48).
// Capsuleveld h48: bg background/neutral, rand b-thin (divider in rust,
// muted bij focus — zelfde focusgedrag als DSTextField/Input), padding px
// gap-4, zoekicoon 20 muted met gap-2 ernaast, tekst 16/24 (Body/Medium):
// placeholder muted, waarde primary. Label/helper uit het component blijven
// buiten scope: geen enkel dark-frame gebruikt ze.

import SwiftUI

public struct DSSearchField: View {
    private let placeholder: String
    @Binding private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dsVectorExport) private var vectorExport

    public init(placeholder: String = "Search", text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        HStack(spacing: DSSpacing.gap2) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(DSColor.Foreground.muted)
            if vectorExport {
                // Vector-export: NSTextField rendert niet in ImageRenderer.
                Text(text.isEmpty ? placeholder : text)
                    .dsTextStyle(.bodyMedium)
                    .foregroundStyle(text.isEmpty ? DSColor.Foreground.muted : DSColor.Foreground.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            } else {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(DSColor.Foreground.muted)
            )
            .textFieldStyle(.plain)
            .dsTextStyle(.bodyMedium)
            .foregroundStyle(DSColor.Foreground.primary)
            .focused($isFocused)
            .dsFocusEffectDisabled()
            }
        }
        .padding(.horizontal, DSSpacing.gap4)
        .frame(height: 48)
        .background(DSColor.Background.neutral, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isFocused ? DSColor.Foreground.muted : DSColor.Foreground.divider,
                lineWidth: DSBorderWidth.thin
            )
        }
        .opacity(isEnabled ? DSOpacity.strong : DSOpacity.disabled)
    }
}
