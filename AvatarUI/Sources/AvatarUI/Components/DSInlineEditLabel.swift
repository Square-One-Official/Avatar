// Inline-edit-label (E03.13 + E03.16; bevindingen 9/12/20/21). Drie staten:
// 1. Rust — pure tekst (heading = Body/Medium primary, subtitle =
//    Body/Small subtle; lege waarde toont de placeholder in muted).
// 2. Hover — badge-affordance: bg background/neutral, padding rond de
//    tekst, zachte radius (r-md, continuous), pointer-cursor.
// 3. Edit (na klik) — een écht NSTextField-gedreven veld op dezelfde plek,
//    leading uitgelijnd binnen een gecentreerde container (bevinding 20):
//    de caret staat vóór de hint (subtle) die op zijn plek blijft tot de
//    eerste toetsaanslag, en een bestaande waarde wordt bij focus volledig
//    geselecteerd (native NSTextField-becomeFirstResponder). Breedte volgt
//    de inhoud (verborgen maattekst), padding in alle staten gelijk — geen
//    layoutshift, nooit clippen (bevinding 12). Enter/blur committen, Esc
//    annuleert, en een klik búiten het veld committet ook (bevinding 21):
//    een NSEvent-monitor die het event gewoon doorlaat — de aangeklikte
//    control voert dus z'n eigen actie uit; geen view-blokkerende catcher.

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
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?
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
                // veldbreedte); leading-alignment zodat de caret vóór de
                // hint staat (bevinding 20) — de container centreert het
                // geheel, dus visueel blijft alles op zijn plek.
                ZStack(alignment: .leading) {
                    Text(draft.isEmpty ? placeholder : draft)
                        .dsTextStyle(variant.textStyle)
                        .opacity(DSOpacity.hidden)
                        .lineLimit(1)
                        .padding(.horizontal, DSSpacing.gap1)
                    TextField(
                        "",
                        text: $draft,
                        prompt: Text(placeholder)
                            .foregroundStyle(DSColor.Foreground.subtle)
                    )
                    .textFieldStyle(.plain)
                    .dsTextStyle(variant.textStyle)
                    .foregroundStyle(variant.color)
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
        .background {
            // Veldpositie in venstercoördinaten voor de buitenklik-check.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { fieldFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        fieldFrame = frame
                    }
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
        .onDisappear { removeClickMonitor() }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityLabel(Text(placeholder))
        .accessibilityValue(Text(text))
    }

    private func beginEditing() {
        draft = text
        isEditing = true
        fieldFocused = true
        installClickMonitor()
    }

    private func commit() {
        guard isEditing else { return }
        text = draft.trimmingCharacters(in: .whitespaces)
        endEditing()
    }

    private func cancel() {
        endEditing()
    }

    private func endEditing() {
        isEditing = false
        fieldFocused = false
        removeClickMonitor()
    }

    // MARK: - Buitenklik (bevinding 21)

    /// Lokale event-monitor zolang het veld actief is: een muisklik buiten
    /// het veld committet en wordt vervolgens gewoon doorgegeven, zodat de
    /// aangeklikte control (canvas, toolknop, sidebar-rij) z'n eigen actie
    /// uitvoert. AppKit flipt de y-as t.o.v. SwiftUI's globale ruimte.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            guard let contentView = event.window?.contentView else { return event }
            let location = CGPoint(
                x: event.locationInWindow.x,
                y: contentView.bounds.height - event.locationInWindow.y
            )
            if !fieldFrame.insetBy(dx: -DSSpacing.gap1, dy: -DSSpacing.gap1).contains(location) {
                Task { @MainActor in commit() }
            }
            return event
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }
}
