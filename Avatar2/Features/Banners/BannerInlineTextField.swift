// Inline canvas-tekstveld met select-all bij eerste focus (Freeform-placeholder).

import AppKit
import SwiftUI

struct BannerInlineTextField: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment = .center
    var placeholder: String
    var focusOnFirstAppear: Bool = false
    var selectAllOnFirstFocus: Bool
    var onSubmit: () -> Void
    var onDeleteWhenEmpty: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.delegate = context.coordinator
        if focusOnFirstAppear || selectAllOnFirstFocus {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                if selectAllOnFirstFocus { field.selectText(nil) }
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.font = font
        field.textColor = color
        field.alignment = alignment
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onDeleteWhenEmpty: onDeleteWhenEmpty)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        let onDeleteWhenEmpty: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onDeleteWhenEmpty: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
            self.onDeleteWhenEmpty = onDeleteWhenEmpty
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:)) {
                guard let field = control as? NSTextField else { return false }
                let value = field.stringValue
                if BannerTextPresets.isEmptyOrPlaceholder(value) {
                    onDeleteWhenEmpty()
                    return true
                }
                if let editor = field.currentEditor() {
                    let full = NSRange(location: 0, length: (value as NSString).length)
                    if editor.selectedRange == full {
                        onDeleteWhenEmpty()
                        return true
                    }
                }
            }
            return false
        }
    }
}
