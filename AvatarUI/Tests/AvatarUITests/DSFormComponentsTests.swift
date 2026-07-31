// Smoke-tests voor E03.5: body-evaluatie van de formulier- en
// lijstcomponenten, plus de cijferfilter-contractcheck van het OTP-veld.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSFormComponentsTests: XCTestCase {

    @MainActor
    func testTextFieldRendert() {
        for label in [String?.none, "Name"] {
            let view = DSTextField(
                label: label,
                placeholder: "Enter your email",
                icon: Image(systemName: "envelope"),
                text: .constant("thierry@example.com")
            )
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    @MainActor
    func testOTPFieldRendertLeegDeelsEnVol() {
        for code in ["", "123", "123456"] {
            let view = DSOTPField(code: .constant(code))
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    @MainActor
    func testPanelHeaderRendert() {
        let view = DSPanelHeader("Check your email", subtitle: "We've sent a 6-digit code")
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }

    @MainActor
    func testSidebarRowRendert() {
        for selected in [true, false] {
            let view = DSSidebarRow(name: "Sonja Bakker", role: "Designer", isSelected: selected, action: {}) {
                Color.gray
            }
            XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        }
    }

    @MainActor
    func testNeutralEnAddButtonRenderen() {
        XCTAssertNotNil(ImageRenderer(content: DSNeutralButton("Cancel") {}).cgImage)
        XCTAssertNotNil(ImageRenderer(content: DSAddButton("Add person") {}).cgImage)
    }
}

// E03.9 — full-width + ghost-tekstknop
extension DSFormComponentsTests {

    @MainActor
    func testFullWidthEnGhostButtonsRenderen() {
        XCTAssertNotNil(ImageRenderer(content:
            DSPrimaryButton("Continue with email", fullWidth: true) {}.frame(width: 360)
        ).cgImage)
        XCTAssertNotNil(ImageRenderer(content:
            DSNeutralButton("Choose file…", fullWidth: true) {}.frame(width: 360)
        ).cgImage)
        XCTAssertNotNil(ImageRenderer(content: DSGhostButton("Resend code") {}).cgImage)
    }
}

// E03.10 — search input
extension DSFormComponentsTests {

    @MainActor
    func testSearchFieldRendert() {
        let view = DSSearchField(text: .constant("")).frame(width: 224)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}

// E03.13 — inline-edit-label
extension DSFormComponentsTests {

    @MainActor
    func testInlineEditLabelRendertBeideVarianten() {
        for variant in [DSInlineEditLabel.Variant.heading, .subtitle] {
            let leeg = DSInlineEditLabel("Name", text: .constant(""), variant: variant)
            let gevuld = DSInlineEditLabel("Name", text: .constant("Sonja"), variant: variant)
            XCTAssertNotNil(ImageRenderer(content: leeg).cgImage)
            XCTAssertNotNil(ImageRenderer(content: gevuld).cgImage)
        }
    }
}

// E03.17 — inline-edit op echt NSTextField
extension DSFormComponentsTests {

    @MainActor
    private func makeField(
        text: String = "", onCommit: @escaping () -> Void = {}, onCancel: @escaping () -> Void = {}
    ) -> InlineEditTextField {
        InlineEditTextField(
            placeholder: "Name", text: .constant(text),
            font: .systemFont(ofSize: 16), textColor: .white, lineHeight: 24,
            onCommit: onCommit, onCancel: onCancel
        )
    }

    @MainActor
    func testEnterCommitEnEscCancelViaDelegate() {
        var committed = false
        var cancelled = false
        let field = makeField(onCommit: { committed = true }, onCancel: { cancelled = true })
        let coordinator = InlineEditTextField.Coordinator(field)
        let control = NSTextField()
        let textView = NSTextView()

        XCTAssertTrue(coordinator.control(
            control, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertTrue(committed)
        XCTAssertTrue(coordinator.control(
            control, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        XCTAssertTrue(cancelled)
        XCTAssertFalse(coordinator.control(
            control, textView: textView, doCommandBy: #selector(NSResponder.moveLeft(_:))
        ))
    }

    @MainActor
    func testBlurCommitViaDelegate() {
        var committed = false
        let coordinator = InlineEditTextField.Coordinator(makeField(onCommit: { committed = true }))
        coordinator.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: NSTextField())
        )
        XCTAssertTrue(committed)
    }

    @MainActor
    func testMeetfunctieClipNooit() {
        let font = NSFont.systemFont(ofSize: 16)
        let leeg = InlineEditTextField.measuredSize(
            text: "", placeholder: "Name", font: font, lineHeight: 24)
        let kort = InlineEditTextField.measuredSize(
            text: "Jo", placeholder: "Name", font: font, lineHeight: 24)
        let lang = InlineEditTextField.measuredSize(
            text: "Jan van den Berg", placeholder: "Name", font: font, lineHeight: 24)
        let placeholderBreedte = ("Name" as NSString)
            .size(withAttributes: [.font: font]).width
        XCTAssertGreaterThanOrEqual(leeg.width, placeholderBreedte)
        XCTAssertGreaterThanOrEqual(kort.width, leeg.width)
        XCTAssertGreaterThan(lang.width, leeg.width)
        XCTAssertEqual(leeg.height, 24)
    }
}

// E33 — macOS-native dubbelklik-overlay
extension DSFormComponentsTests {

    @MainActor
    func testOnDoubleClickModifierRendert() {
        let view = Text("Name")
            .padding()
            .onDoubleClick {}
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
    }
}
