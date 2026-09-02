// Smoke-tests voor DSDialog — body-evaluatie (ImageRenderer) met lege en
// gevulde inhoud, enabled/disabled confirm.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSDialogTests: XCTestCase {
    @MainActor
    func testDialogRendertMetVeldEnActies() {
        let view = DSDialog(
            title: "Create folder",
            confirmLabel: "Create",
            confirmEnabled: false,
            onConfirm: {},
            onDismiss: {}
        ) {
            DSTextField(placeholder: "Folder name", text: .constant(""))
        }
        .frame(width: 360)
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)

        let filled = DSDialog(
            title: "Create folder",
            confirmLabel: "Create",
            onConfirm: {},
            onDismiss: {}
        ) {
            DSTextField(placeholder: "Folder name", text: .constant("Clients"))
        }
        .frame(width: 360)
        XCTAssertNotNil(ImageRenderer(content: filled).cgImage)
    }
}
