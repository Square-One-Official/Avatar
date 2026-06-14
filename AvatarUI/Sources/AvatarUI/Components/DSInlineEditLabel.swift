// Inline-edit-label — definitieve herbouw op een echt NSTextField (E03.17;
// na drie gefaalde iteraties op eigen caret/focus-afhandeling: bevindingen
// 9, 12, 20, 21). Acceptatiecriteria:
// 1. Rust: platte tekst zonder chrome; hover-badge (bg neutral-stronger,
//    r-md, pointer-cursor — punt 24a) alleen op het veld onder de cursor;
//    alle staten delen exact hetzelfde kader (punt 24b).
// 2. Edit: native NSTextField — caret op tekstpositie, placeholder links
//    van de caret die bij de eerste toetsaanslag verdwijnt, bestaande
//    waarde volledig geselecteerd bij focus (becomeFirstResponder).
// 3. Intrinsieke breedte via een pure meetfunctie (max van tekst en
//    placeholder + caret-marge) — nooit clippen; hoogte = de vaste
//    Figma-regelhoogte, identiek in alle staten.
// 4. Enter (insertNewline), blur (controlTextDidEndEditing) en klik-buiten
//    committen; Esc (cancelOperation) annuleert. De klik-buiten loopt via
//    een lokale NSEvent-monitor die het event dóórgeeft, zodat de
//    aangeklikte control z'n eigen actie uitvoert.

import AppKit
import SwiftUI

public struct DSInlineEditLabel: View {
    public enum Variant: Sendable {
        case heading
        case subtitle

        var textStyle: DSTextStyle { self == .heading ? .bodyMedium : .bodySmall }
        var color: Color {
            self == .heading ? DSColor.Foreground.primary : DSColor.Foreground.subtle
        }
        // Beide varianten zijn Content/Body (regular); alleen maat/kleur
        // verschillen. Alpha's = de exacte tokenwaarden (subtle 0xB2).
        var nsFont: NSFont {
            NSFont.systemFont(ofSize: textStyle.size, weight: .regular)
        }
        var nsColor: NSColor {
            self == .heading ? .white : NSColor.white.withAlphaComponent(0xB2 / 255.0)
        }
    }

    private let placeholder: String
    @Binding private var text: String
    private let variant: Variant
    /// E24.7: meldt begin/eind van de edit-staat (voor container-uitlijning).
    private let onEditingChanged: (Bool) -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draft = ""
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?
    @State private var cursorPushed = false

    public init(
        _ placeholder: String,
        text: Binding<String>,
        variant: Variant = .heading,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.placeholder = placeholder
        self._text = text
        self.variant = variant
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        // Punt 24b: alle staten delen exact hetzelfde kader — breedte uit
        // de meetfunctie (incl. caret-marge, óók in rust gereserveerd),
        // leading-alignment, vaste regelhoogte. Alleen achtergrond en rand
        // veranderen; de tekst beweegt geen pixel.
        let size = InlineEditTextField.measuredSize(
            text: isEditing ? draft : text,
            placeholder: placeholder,
            font: variant.nsFont,
            lineHeight: variant.textStyle.lineHeight
        )
        Group {
            if isEditing {
                InlineEditTextField(
                    placeholder: placeholder,
                    text: $draft,
                    font: variant.nsFont,
                    textColor: variant.nsColor,
                    lineHeight: variant.textStyle.lineHeight,
                    onCommit: { commit() },
                    onCancel: { cancel() }
                )
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .dsTextStyle(variant.textStyle)
                    .foregroundStyle(text.isEmpty ? DSColor.Foreground.muted : variant.color)
                    .lineLimit(1)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .padding(.horizontal, DSSpacing.gap2)
        .padding(.vertical, DSSpacing.gap0_5)
        // Punt 24a: hover-tint één stap sterker (neutral-stronger) —
        // neutral was op zwart nauwelijks zichtbaar.
        .background(
            isEditing || isHovering ? DSColor.Background.neutralStronger : .clear,
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
            isHovering = hovering && !isEditing
            setCursor(pushed: isHovering)
        }
        .onTapGesture {
            guard !isEditing else { return }
            beginEditing()
        }
        .onDisappear {
            removeClickMonitor()
            setCursor(pushed: false)
        }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityLabel(Text(placeholder))
        .accessibilityValue(Text(text))
    }

    /// Gebalanceerde push/pop zodat de pointer-cursor nooit blijft hangen.
    private func setCursor(pushed: Bool) {
        guard pushed != cursorPushed else { return }
        cursorPushed = pushed
        if pushed {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    private func beginEditing() {
        draft = text
        isEditing = true
        isHovering = false
        setCursor(pushed: false)
        installClickMonitor()
        onEditingChanged(true)
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
        removeClickMonitor()
        onEditingChanged(false)
    }

    /// Klik buiten het veld committet; het event passeert, dus de
    /// aangeklikte control (canvas/toolknop/sidebar) doet z'n eigen werk.
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

/// Echt NSTextField als editveld: native caret/placeholder/selectie,
/// Enter/Esc via de delegate, blur via controlTextDidEndEditing.
struct InlineEditTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let lineHeight: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void

    /// Pure meetfunctie (unit-getest): breedte = max(tekst, placeholder)
    /// + caret-marge; hoogte = de vaste Figma-regelhoogte.
    static func measuredSize(
        text: String, placeholder: String, font: NSFont, lineHeight: CGFloat
    ) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        let placeholderWidth = (placeholder as NSString).size(withAttributes: attributes).width
        return CGSize(
            width: ceil(max(textWidth, placeholderWidth)) + 8,
            height: ceil(lineHeight)
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        // E18.11: NSTextField top-uitlijnt z'n tekst in een hoogte die kleiner
        // is dan z'n natuurlijke celhoogte → de tekst sprong omhoog bij focus
        // t.o.v. de SwiftUI-Text (die centreert). Een verticaal centrerende cel
        // lijnt beide staten gelijk uit.
        let centeredCell = VerticallyCenteredTextFieldCell(textCell: text)
        centeredCell.isEditable = true
        centeredCell.isSelectable = true
        centeredCell.wraps = false
        centeredCell.isScrollable = true
        field.cell = centeredCell
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = textColor
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: font,
                // foreground/default/muted (#ffffff66) — de hint-tint.
                .foregroundColor: NSColor.white.withAlphaComponent(0x66 / 255.0)
            ]
        )
        field.delegate = context.coordinator
        // Native focus: becomeFirstResponder selecteert een bestaande
        // waarde volledig — typen vervangt direct (criterium 2).
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSTextField, context: Context
    ) -> CGSize? {
        Self.measuredSize(
            text: text, placeholder: placeholder, font: font, lineHeight: lineHeight
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// E18.11: centreert de tekst verticaal in de (kleine) celhoogte zodat de
    /// editstaat exact op de rust-Text valt — zowel het tekenen als de
    /// veld-editor (caret/selectie) gebruiken hetzelfde gecentreerde kader.
    final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
        private func centered(_ rect: NSRect) -> NSRect {
            let textHeight = cellSize(forBounds: rect).height
            guard textHeight < rect.height else { return rect }
            var result = rect
            result.origin.y += (rect.height - textHeight) / 2
            result.size.height = textHeight
            return result
        }

        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            super.drawingRect(forBounds: centered(rect))
        }

        override func edit(
            withFrame rect: NSRect, in controlView: NSView, editor: NSText,
            delegate: Any?, event: NSEvent?
        ) {
            super.edit(
                withFrame: centered(rect), in: controlView, editor: editor,
                delegate: delegate, event: event
            )
        }

        override func select(
            withFrame rect: NSRect, in controlView: NSView, editor: NSText,
            delegate: Any?, start selStart: Int, length selLength: Int
        ) {
            super.select(
                withFrame: centered(rect), in: controlView, editor: editor,
                delegate: delegate, start: selStart, length: selLength
            )
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditTextField

        init(_ parent: InlineEditTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
