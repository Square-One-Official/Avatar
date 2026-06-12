// Inline-edit-label (E03.13; bevinding 9 visuele pass 12 jun). Drie staten:
// 1. Rust — pure tekst (heading = Body/Medium primary, subtitle =
//    Body/Small subtle; lege waarde toont de placeholder in muted).
// 2. Hover — badge-affordance: bg background/neutral, padding rond de
//    tekst, zachte radius (r-md, continuous), pointer-cursor.
// 3. Edit (na klik) — een écht smal inputveld op dezelfde plek: zelfde
//    typografie/uitlijning, caret in het veld, hover-bg + focus-rand
//    (b-thin, muted). Breedte volgt de inhoud (verborgen maattekst met het
//    veld als overlay), padding is in alle staten gelijk → geen
//    verspringende layout. Enter/blur bevestigt, Esc annuleert.

import SwiftUI

public struct DSInlineEditLabel: View {
    public enum Variant: Sendable {
        case heading
        case subtitle

        var textStyle: DSTextStyle { self == .heading ? .bodyMedium : .bodySmall }
        var color: Color {
            self == .heading ? DSColor.Foreground.primary : DSColor.Foreground.subtle
        }
    }

    private let placeholder: String
    @Binding private var text: String
    private let variant: Variant

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    public init(_ placeholder: String, text: Binding<String>, variant: Variant = .heading) {
        self.placeholder = placeholder
        self._text = text
        self.variant = variant
    }

    public var body: some View {
        Group {
            if isEditing {
                // Breedte = max(maattekst + caret-marge, intrinsieke
                // veldbreedte): minimum op de huidige tekst, groeit mee
                // tijdens het typen, blijft gecentreerd, clipt nooit
                // (E03.14, bevinding 12).
                ZStack {
                    Text(draft.isEmpty ? placeholder : draft)
                        .dsTextStyle(variant.textStyle)
                        .opacity(DSOpacity.hidden)
                        .lineLimit(1)
                        .padding(.horizontal, DSSpacing.gap1)
                    TextField(
                        "",
                        text: $draft,
                        prompt: Text(placeholder)
                            .foregroundStyle(DSColor.Foreground.muted)
                    )
                    .textFieldStyle(.plain)
                    .dsTextStyle(variant.textStyle)
                    .foregroundStyle(variant.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
                    .focused($fieldFocused)
                    .onSubmit { commit() }
                    .onExitCommand { cancel() }
                }
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .dsTextStyle(variant.textStyle)
                    .foregroundStyle(text.isEmpty ? DSColor.Foreground.muted : variant.color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, DSSpacing.gap2)
        .padding(.vertical, DSSpacing.gap0_5)
        .background(
            isEditing || isHovering ? DSColor.Background.neutral : .clear,
            in: .rect(cornerRadius: DSRadius.md, style: .continuous)
        )
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.Foreground.muted, lineWidth: DSBorderWidth.thin)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isEditing {
                NSCursor.pointingHand.push()
            } else if !hovering {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            guard !isEditing else { return }
            beginEditing()
        }
        .onChange(of: fieldFocused) { _, focused in
            // Blur bevestigt — tenzij Esc/commit de editstaat al sloot.
            if !focused && isEditing { commit() }
        }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityLabel(Text(placeholder))
        .accessibilityValue(Text(text))
    }

    private func beginEditing() {
        draft = text
        isEditing = true
        fieldFocused = true
    }

    private func commit() {
        guard isEditing else { return }
        text = draft.trimmingCharacters(in: .whitespaces)
        isEditing = false
        fieldFocused = false
    }

    private func cancel() {
        isEditing = false
        fieldFocused = false
    }
}
