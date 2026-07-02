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
        if focusOnFirstAppear || selectAllOnFirstFocus {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                if selectAllOnFirstFocus {
                    view.selectAll(nil)
                } else {
                    let end = (view.string as NSString).length
                    view.setSelectedRange(NSRange(location: end, length: 0))
                }
            }
        }
        return view
    }

    func updateNSView(_ view: PlaceholderTextView, context: Context) {
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
        Coordinator(text: $text, onSubmit: onSubmit, onDeleteWhenEmpty: onDeleteWhenEmpty)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        let onDeleteWhenEmpty: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onDeleteWhenEmpty: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onDeleteWhenEmpty = onDeleteWhenEmpty
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text = view.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Return / Escape committen (geen handmatige newline; word-wrap regelt
            // meerregelig — consistent met de gebakken render).
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onSubmit()
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
