// E13.5 (audit-C1) — UpdateManager app-breed + achtergrondcheck bij launch.
// De echte SPUUpdater zit achter het `UpdaterEngine`-seam; hier prikken we
// een fake engine in en toetsen we de launch-checklogica: precies één
// engine-start, precies één achtergrondcheck per proces, en respect voor de
// "Automatic updates"-toggle. Geen echte Sparkle/netwerk in deze tests.

import Combine
import XCTest
@testable import Avatar2

@MainActor
private final class FakeUpdaterEngine: UpdaterEngine {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?

    let canCheckSubject = PassthroughSubject<Bool, Never>()
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        canCheckSubject.eraseToAnyPublisher()
    }

    private(set) var startCount = 0
    private(set) var userCheckCount = 0
    private(set) var backgroundCheckCount = 0

    func start() throws { startCount += 1 }
    func checkForUpdates() { userCheckCount += 1 }
    func checkForUpdatesInBackground() { backgroundCheckCount += 1 }
}

@MainActor
final class UpdateManagerTests: XCTestCase {

    private func maakManager(
        engine: FakeUpdaterEngine
    ) -> UpdateManager {
        UpdateManager(makeEngine: { _ in engine })
    }

    // MARK: - init

    func testInitStartDeEnginePreciesEenKeer() {
        let engine = FakeUpdaterEngine()
        _ = maakManager(engine: engine)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(engine.backgroundCheckCount, 0,
                       "init zelf mag nog geen check triggeren")
    }

    // MARK: - launch-achtergrondcheck (audit-C1)

    func testLaunchTriggertPreciesEenAchtergrondcheck() {
        let engine = FakeUpdaterEngine()
        let manager = maakManager(engine: engine)

        XCTAssertNil(manager.lastBackgroundCheckRequest)
        manager.checkForUpdatesInBackgroundAtLaunch()

        XCTAssertEqual(engine.backgroundCheckCount, 1)
        XCTAssertNotNil(manager.lastBackgroundCheckRequest,
                        "observeerbaar bewijs van de launch-check (DoD)")

        // `.task` op de WindowGroup-content kan opnieuw draaien (venster
        // her-open) — de launch-check blijft eenmalig per proces.
        manager.checkForUpdatesInBackgroundAtLaunch()
        XCTAssertEqual(engine.backgroundCheckCount, 1)
    }

    func testLaunchRespecteertUitgeschakeldeAutomaticUpdates() {
        let engine = FakeUpdaterEngine()
        engine.automaticallyChecksForUpdates = false
        let manager = maakManager(engine: engine)

        manager.checkForUpdatesInBackgroundAtLaunch()

        XCTAssertEqual(engine.backgroundCheckCount, 0,
                       "toggle uit → launch checkt niet stilletjes")
        XCTAssertNil(manager.lastBackgroundCheckRequest)
    }

    // MARK: - doorgeefgedrag About-pagina

    func testCheckForUpdatesGaatNaarDeEngine() {
        let engine = FakeUpdaterEngine()
        let manager = maakManager(engine: engine)
        manager.checkForUpdates()
        XCTAssertEqual(engine.userCheckCount, 1)
    }

    func testAutomaticallyChecksForUpdatesSpiegeltDeEngine() {
        let engine = FakeUpdaterEngine()
        let manager = maakManager(engine: engine)
        XCTAssertTrue(manager.automaticallyChecksForUpdates)
        manager.automaticallyChecksForUpdates = false
        XCTAssertFalse(engine.automaticallyChecksForUpdates)
    }

    func testCanCheckForUpdatesVolgtDePublisher() async {
        let engine = FakeUpdaterEngine()
        let manager = maakManager(engine: engine)
        XCTAssertTrue(manager.canCheckForUpdates)

        engine.canCheckSubject.send(false)
        // sink levert via DispatchQueue.main — één hop wachten.
        let hop = expectation(description: "main-queue hop")
        DispatchQueue.main.async { hop.fulfill() }
        await fulfillment(of: [hop], timeout: 2)

        XCTAssertFalse(manager.canCheckForUpdates)
    }
}
