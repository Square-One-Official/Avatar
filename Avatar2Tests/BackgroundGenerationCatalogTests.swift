import XCTest
@testable import Avatar2

final class BackgroundGenerationCatalogTests: XCTestCase {

    func testPortraitContextHint() {
        XCTAssertEqual(
            BackgroundGenerationContext.portrait.contextHint,
            "Square · fits your portrait"
        )
    }

    func testBannerContextHint() {
        let ctx = BackgroundGenerationContext.banner(width: 1500, height: 500)
        XCTAssertEqual(ctx.contextHint, "1500 × 500 · fits this banner")
        XCTAssertTrue(ctx.isWide)
        XCTAssertEqual(ctx.creditCost, 3)
    }

    func testPortraitCreditCost() {
        XCTAssertEqual(BackgroundGenerationContext.portrait.creditCost, 2)
        XCTAssertFalse(BackgroundGenerationContext.portrait.isWide)
    }

    func testCanGenerateRequiresPrompt() {
        XCTAssertFalse(
            BackgroundGenerationCatalog.canGenerate(
                prompt: "  ",
                style: .photorealistic,
                customStyleText: ""
            )
        )
        XCTAssertTrue(
            BackgroundGenerationCatalog.canGenerate(
                prompt: "Modern office",
                style: .photorealistic,
                customStyleText: ""
            )
        )
    }

    func testCanGenerateCustomStyleRequiresText() {
        XCTAssertFalse(
            BackgroundGenerationCatalog.canGenerate(
                prompt: "Forest path",
                style: .custom,
                customStyleText: ""
            )
        )
        XCTAssertTrue(
            BackgroundGenerationCatalog.canGenerate(
                prompt: "Forest path",
                style: .custom,
                customStyleText: "Oil painting"
            )
        )
    }

    func testTargetSizePortrait() {
        XCTAssertEqual(BackgroundGenerationContext.portrait.targetWidth, PortraitExporter.exportSide)
        XCTAssertEqual(BackgroundGenerationContext.portrait.targetHeight, PortraitExporter.exportSide)
    }
}
