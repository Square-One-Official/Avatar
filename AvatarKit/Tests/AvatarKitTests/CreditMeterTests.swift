import XCTest
@testable import AvatarKit

/// E14.3: CreditMeter spiegelt de besluit-tarieftabel.
final class CreditMeterTests: XCTestCase {
    func testTariffs() {
        XCTAssertEqual(CreditMeter.credits(for: .magicCutout), 1)
        XCTAssertEqual(CreditMeter.credits(for: .colorize), 1)
        XCTAssertEqual(CreditMeter.credits(for: .upscale), 1)
        XCTAssertEqual(CreditMeter.credits(for: .fillBody), 2)
        XCTAssertEqual(CreditMeter.credits(for: .generativeStandard), 4)
        XCTAssertEqual(CreditMeter.credits(for: .generativePremium), 7)
    }

    func testChipLabelSingularPlural() {
        XCTAssertEqual(CreditMeter.chipLabel(for: .magicCutout), "1 credit")
        XCTAssertEqual(CreditMeter.chipLabel(for: .fillBody), "2 credits")
        XCTAssertEqual(CreditMeter.chipLabel(for: .generativeStandard), "4 credits")
    }

    func testCanAfford() {
        XCTAssertTrue(CreditMeter.canAfford(.generativeStandard, creditsRemaining: 4))
        XCTAssertFalse(CreditMeter.canAfford(.generativeStandard, creditsRemaining: 3))
        XCTAssertTrue(CreditMeter.canAfford(.magicCutout, creditsRemaining: 1))
    }
}
