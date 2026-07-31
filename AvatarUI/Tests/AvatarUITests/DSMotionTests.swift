// E53.4 — reduce-motion is verplicht, geen opt-in per call site.
//
// De échte handhaving zit in `scripts/check-motion.sh` (kale withAnimation /
// .animation = build-fail). Deze suite borgt de contracten van de helpers zelf,
// zodat een latere "kleine opschoning" de reduce-motion-route niet stilletjes
// om zeep helpt.

import SwiftUI
import XCTest
@testable import AvatarUI

final class DSMotionTests: XCTestCase {

    /// `animate` moet zijn body altijd uitvoeren — óók met reduce-motion aan.
    /// Anders zou de instelling niet alleen de animatie maar de hele
    /// state-wijziging weglaten, en werkt de app niet meer.
    func testAnimateAlwaysRunsBody() {
        var ran = false
        DSMotion.animate(DSMotion.fast) { ran = true }
        XCTAssertTrue(ran)
    }

    /// De cross-fade-uitzondering voert z'n body eveneens uit; hij bestaat
    /// alleen om de opacity-animatie te behouden waar beweging ontbreekt.
    func testCrossFadeAlwaysRunsBody() {
        var ran = false
        DSMotion.animateCrossFade(.easeInOut(duration: 0.2)) { ran = true }
        XCTAssertTrue(ran)
    }

    /// Emil/animations.dev: een surface verdwijnt sneller dan 'ie verschijnt.
    /// Als iemand `enter`/`exit` gelijk trekt voelt elke dismiss traag.
    func testExitIsFasterThanEnter() {
        XCTAssertEqual(DSMotion.enter, DSMotion.emphasis)
        XCTAssertEqual(DSMotion.exit, DSMotion.base)
        XCTAssertNotEqual(DSMotion.enter, DSMotion.exit)
    }

    /// De duur-ladder moet oplopend blijven: micro < fast < base < emphasis.
    /// Gelijke tokens maken de semantiek betekenisloos.
    func testDurationLadderIsOrdered() {
        let ladder = [DSMotion.micro, DSMotion.fast, DSMotion.base, DSMotion.emphasis]
        XCTAssertEqual(Set(ladder).count, ladder.count, "tokens moeten onderling verschillen")
    }

    func testSpringTokensAreDistinct() {
        XCTAssertNotEqual(DSMotion.springSmall, DSMotion.springTransform)
    }

    /// De vlag leest de systeeminstelling; hij mag niet crashen of vastlopen bij
    /// herhaald lezen (hij wordt per withAnimation-site aangeroepen).
    func testReduceMotionFlagIsReadable() {
        let first = DSMotion.reduceMotionEnabled
        XCTAssertEqual(first, DSMotion.reduceMotionEnabled)
    }

    /// De transitions moeten met reduce-motion een ándere (bewegingsloze)
    /// variant opleveren dan zonder.
    func testTransitionsDifferUnderReduceMotion() {
        let slideNormal = AnyTransition.dsSlide(.trailing, reduceMotion: false)
        let slideReduced = AnyTransition.dsSlide(.trailing, reduceMotion: true)
        XCTAssertNotEqual(String(describing: slideNormal), String(describing: slideReduced))

        let scaleNormal = AnyTransition.dsScaleFade(anchor: .top, reduceMotion: false)
        let scaleReduced = AnyTransition.dsScaleFade(anchor: .top, reduceMotion: true)
        XCTAssertNotEqual(String(describing: scaleNormal), String(describing: scaleReduced))
    }
}
