import XCTest
@testable import Avatar2

final class BannerToolCopyTests: XCTestCase {
    func testShadersToolIsNotNamedEffects() {
        XCTAssertEqual(BannerTool.shaders.label, "Shaders")
        XCTAssertEqual(BannerTool.shaders.summary, "Procedural shaders applied to the whole banner.")
    }

    func testPointerCopyUsesClickNotTap() {
        for tool in BannerTool.allCases {
            XCTAssertFalse(
                tool.summary.localizedCaseInsensitiveContains("tap"),
                "\(tool.label) summary still says tap: \(tool.summary)"
            )
        }
    }

    func testToolbarLabelsStayDistinctFromPortraitEffects() {
        XCTAssertEqual(
            BannerTool.allCases.map(\.label),
            ["Background", "Shaders", "Text", "Logo", "Size"]
        )
    }
}
