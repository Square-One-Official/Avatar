// Inline canvas-tekst-editor (Freeform-stijl). Een transparante NSTextView die
// — net als de gebakken render — word-wrapt binnen een vaste box-breedte, of als
// auto-hug één regel laat groeien. Placeholder, select-all bij eerste focus,
// Return/Escape committen en ⌫ op een lege/volledig-geselecteerde laag verwijdert.

import AppKit
import SwiftUI

struct BannerInlineTextField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var underline: Bool = false
    var alignment: NSTextAlignment = .center
    var placeholder: String
    /// Wrap-breedte in schermpunten. `nil` = auto-hug (geen wrap, groeit op één regel).
    var containerWidth: CGFloat?
    var focusOnFirstAppear: Bool = false
    var selectAllOnFirstFocus: Bool
    var onSubmit: () -> Void
    /// UXS-1: Escape = cancel (macOS-conventie), niet commit. De call site zet de
    /// tekst terug op de stand van vóór de edit en sluit de editor.
    var onCancel: () -> Void
    var onDeleteWhenEmpty: () -> Void

    func makeNSView(context: Context) -> PlaceholderTextView {
        let view = PlaceholderTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.focusRingType = .none
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.string = text
        applyStyle(to: view)
        // 37.17 (audit-B6): first responder wordt SYNCHROON geclaimd zodra de view
        // aan het venster hangt (`viewDidMoveToWindow`), niet via een async-hop.
        // De oude `DispatchQueue.main.async { makeFirstResponder }` liet minimaal
        // één runloop-cyclus gaan waarin toetsaanslagen nergens landden.
        if focusOnFirstAppear || selectAllOnFirstFocus {
            view.wantsInitialFocus = true
            view.selectAllOnInitialFocus = selectAllOnFirstFocus
        }
        return view
    }

    func updateNSView(_ view: PlaceholderTextView, context: Context) {
        updateCoordinator(context.coordinator)
        if view.string != text { view.string = text }
        applyStyle(to: view)
    }

    private func applyStyle(to view: PlaceholderTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment

        view.placeholderString = placeholder
        view.placeholderColor = color.withAlphaComponent(0.45)
        view.font = font
        view.textColor = color
        view.alignment = alignment

        // Container volgt altijd de view-breedte zodat (center-)uitlijning binnen
        // het zichtbare veld gebeurt. Bij vaste breedte wrapt de tekst; in auto-hug
        // groeit het SwiftUI-frame met de tekst mee, dus dan wrapt er niets.
        let big = CGFloat.greatestFiniteMagnitude
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = CGSize(width: containerWidth ?? big, height: big)

        var typing: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if underline { typing[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        view.typingAttributes = typing
        let full = NSRange(location: 0, length: (view.string as NSString).length)
        if full.length > 0, let storage = view.textStorage {
            if underline {
                storage.addAttributes(typing, range: full)
            } else {
                storage.addAttributes(typing, range: full)
                storage.removeAttribute(.underlineStyle, range: full)
            }
        }
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, onDeleteWhenEmpty: onDeleteWhenEmpty)
    }

    /// De coordinator wordt één keer gemaakt, maar de closures komen uit een
    /// struct die SwiftUI bij elke render opnieuw bouwt — dus bij elke update
    /// verversen, anders houdt een oude closure een verouderde laag-id vast.
    func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.onSubmit = onSubmit
        coordinator.onCancel = onCancel
        coordinator.onDeleteWhenEmpty = onDeleteWhenEmpty
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onCancel: () -> Void
        var onDeleteWhenEmpty: () -> Void

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onCancel: @escaping () -> Void,
            onDeleteWhenEmpty: @escaping () -> Void
        ) {
            _text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onDeleteWhenEmpty = onDeleteWhenEmpty
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Return committeert (geen handmatige newline; word-wrap regelt
            // meerregelig — consistent met de gebakken render).
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            // UXS-1: Escape annuleert. Was hier tot 2026-07-31 samengevoegd met
            // Return, waardoor Esc de bewerking juist vastlegde — precies het
            // tegenovergestelde van de macOS-conventie.
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:)) {
                let value = textView.string
                if BannerTextPresets.isEmptyOrPlaceholder(value) {
                    onDeleteWhenEmpty()
                    return true
                }
                let full = NSRange(location: 0, length: (value as NSString).length)
                if textView.selectedRange() == full {
                    onDeleteWhenEmpty()
                    return true
                }
            }
            return false
        }
    }
}

/// NSTextView met een placeholder die getekend wordt zolang de inhoud leeg is.
final class PlaceholderTextView: NSTextView {
    var placeholderString: String = ""
    var placeholderColor: NSColor = .secondaryLabelColor

    /// 37.17 — claim first responder zodra de view aan een venster hangt. Dit
    /// gebeurt synchroon tijdens de SwiftUI-render-commit, dus vóór het volgende
    /// key-event wordt verwerkt: geen runloop-gat waarin toetsen verloren gaan.
    var wantsInitialFocus = false
    var selectAllOnInitialFocus = false
    private var didClaimInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard wantsInitialFocus, !didClaimInitialFocus, let window else { return }
        didClaimInitialFocus = true
        window.makeFirstResponder(self)
        if selectAllOnInitialFocus {
            selectAll(nil)
        } else {
            let end = (string as NSString).length
            setSelectedRange(NSRange(location: end, length: 0))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: placeholderColor,
            .paragraphStyle: paragraph,
        ]
        let inset = textContainerInset
        let rect = NSRect(
            x: inset.width,
            y: inset.height,
            width: bounds.width - inset.width * 2,
            height: bounds.height - inset.height * 2
        )
        placeholderString.draw(in: rect, withAttributes: attrs)
    }
}
