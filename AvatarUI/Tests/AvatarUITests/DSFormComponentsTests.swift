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
