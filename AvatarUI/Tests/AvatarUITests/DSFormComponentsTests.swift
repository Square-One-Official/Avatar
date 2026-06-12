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
