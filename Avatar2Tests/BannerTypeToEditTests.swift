// E37.17 (audit-B6) — Type-to-edit mag geen toetsen verliezen. Twee contracten:
// (1) de besluitlogica: toets 1 start de editor, toetsen die tijdens de
// first-responder-handoff nog in de chrome landen worden aan de draft geplakt
// (nooit genegeerd), en (2) de inline editor claimt first responder SYNCHROON
// zodra hij aan het venster hangt — geen runloop-gat meer (de oude async
// `makeFirstResponder`-hop was de bron van "One look" → "O look").

import AppKit
import XCTest
@testable import Avatar2

@MainActor
final class BannerTypeToEditTests: XCTestCase {

    // MARK: Besluitlogica

    func testFirstPrintableKeyBeginsEditing() {
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "O", hasCommandOrControl: false, isEditing: false),
            .begin(draft: "O")
        )
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "3", hasCommandOrControl: false, isEditing: false),
            .begin(draft: "3")
        )
        XCTAssertEqual(
            BannerTypeToEdit.action(for: " ", hasCommandOrControl: false, isEditing: false),
            .begin(draft: " ")
        )
    }

    /// Het hart van B6: toetsen die binnenkomen terwijl `isEditing` al waar is
    /// (de editor is nog geen first responder) worden GEBUFFERD, niet genegeerd.
    func testKeysDuringHandoffGapAreAppendedNotDropped() {
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "n", hasCommandOrControl: false, isEditing: true),
            .appendToDraft("n")
        )
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "e", hasCommandOrControl: false, isEditing: true),
            .appendToDraft("e")
        )
    }

    func testCommandAndControlChordsAreIgnored() {
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "a", hasCommandOrControl: true, isEditing: false),
            .ignore
        )
        XCTAssertEqual(
            BannerTypeToEdit.action(for: "a", hasCommandOrControl: true, isEditing: true),
            .ignore
        )
    }

    func testNonPrintableKeysAreIgnored() {
        // Pijltjes/functietoetsen leveren private-use-area-characters (bv. NSUpArrowFunctionKey).
        let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        XCTAssertEqual(BannerTypeToEdit.action(for: upArrow, hasCommandOrControl: false, isEditing: false), .ignore)
        XCTAssertEqual(BannerTypeToEdit.action(for: upArrow, hasCommandOrControl: false, isEditing: true), .ignore)
        XCTAssertEqual(BannerTypeToEdit.action(for: "", hasCommandOrControl: false, isEditing: false), .ignore)
    }

    // MARK: Synchrone first-responder-claim

    func testEditorClaimsFirstResponderSynchronouslyWhenMovedToWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let view = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.isEditable = true
        view.string = "O"
        view.wantsInitialFocus = true

        window.contentView?.addSubview(view)

        // Géén runloop-spin: de claim moet al gebeurd zijn tijdens addSubview.
        XCTAssertTrue(window.firstResponder === view,
                      "editor hoort synchroon first responder te worden — een async-hop verliest toetsen")
        // Cursor achteraan zodat gebufferde tekens netjes aansluiten.
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 0))
    }

    func testEditorSelectsAllOnInitialFocusWhenAsked() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let view = PlaceholderTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        view.isEditable = true
        view.string = BannerTextPresets.placeholder
        view.wantsInitialFocus = true
        view.selectAllOnInitialFocus = true

        window.contentView?.addSubview(view)

        XCTAssertTrue(window.firstResponder === view)
        XCTAssertEqual(view.selectedRange(),
                       NSRange(location: 0, length: (BannerTextPresets.placeholder as NSString).length))
    }
}
