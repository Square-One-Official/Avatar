// Sparkle-updater voor Avatar2 (E01.11) — 1-op-1 port van de v1
// `Avatar/Services/UpdateManager.swift` (zelfde self-hosted appcast + EdDSA-
// publieke sleutel, zie project.yml). Wrappt SPUUpdater met een eigen
// in-app user-driver zodat de About-pagina (E15.4) check/auto-check stuurt
// zonder Sparkle's eigen vensters. De v1-`#if !APP_STORE`-gate is hier weg:
// Avatar2 is voorlopig DMG-only; een latere MAS-target sluit dit bestand uit.
//
// E13.5 (audit-C1): de manager is nu app-breed — Avatar2App bezit de ENIGE
// instance (@State) en geeft hem via Environment door; SettingsAboutPage
// consumeert die. Sparkle verwacht één SPUUpdater per proces, dus hier mag
// nooit meer per-view geconstrueerd worden. De SPUUpdater zit achter het
// `UpdaterEngine`-seam zodat de launch-checklogica zonder echte Sparkle
// testbaar is (Avatar2Tests/UpdateManagerTests.swift) en de unit-test-host
// nooit een echte updater start.

import Foundation
import OSLog
import SwiftUI
import Combine
import Sparkle

enum UpdateState: Equatable {
    case idle
    case checking
    case downloading(progress: Double)
    case extracting
    case readyToRelaunch(version: String)
    case error(String)
}

// MARK: - Engine-seam (E13.5)

/// Dun laagje over `SPUUpdater` zodat `UpdateManager` in tests een fake
/// engine kan krijgen (geen echte Sparkle-start / netwerk in unit-tests).
@MainActor
protocol UpdaterEngine: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    var lastUpdateCheckDate: Date? { get }
    func start() throws
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

/// Productie-engine: de echte `SPUUpdater` op de main bundle.
@MainActor
private final class SparkleUpdaterEngine: UpdaterEngine {
    private let updater: SPUUpdater

    init(userDriver: any SPUUserDriver) {
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    func start() throws { try updater.start() }
    func checkForUpdates() { updater.checkForUpdates() }
    func checkForUpdatesInBackground() { updater.checkForUpdatesInBackground() }
}

/// No-op-engine voor de unit-test-host: Avatar2Tests draait gehost in
/// Aaavatar 2.app, dus `Avatar2App.init` (en dus `UpdateManager()`) draait
/// óók tijdens `xcodebuild test`. Daar mag nooit een echte SPUUpdater
/// starten (netwerk-check tegen de appcast midden in een testrun).
@MainActor
private final class NoopUpdaterEngine: UpdaterEngine {
    var automaticallyChecksForUpdates = true
    var canCheckForUpdates = true
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        Empty().eraseToAnyPublisher()
    }
    var lastUpdateCheckDate: Date? { nil }
    func start() throws {}
    func checkForUpdates() {}
    func checkForUpdatesInBackground() {}
}

// MARK: - UpdateManager

@MainActor
@Observable
final class UpdateManager: NSObject {
    private(set) var state: UpdateState = .idle
    /// Mirrors `SPUUpdater.canCheckForUpdates`. Defaults to `true` so the
    /// "Check Now" button is enabled at first paint, before Sparkle's KVO
    /// has had a chance to publish.
    private(set) var canCheckForUpdates = true
    /// E13.5: observeerbaar bewijs dat de launch-achtergrondcheck is
    /// aangevraagd (DoD-verificatie zonder echte download).
    private(set) var lastBackgroundCheckRequest: Date?

    private var engine: (any UpdaterEngine)!
    private var userDriver: InAppUserDriver!
    /// E13.5: de launch-check mag maar één keer per proces vuren — `.task`
    /// op de WindowGroup-content kan opnieuw draaien (venster her-open).
    private var hasRequestedLaunchCheck = false

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private let logger = Logger(subsystem: "nl.squareone.aaavatar2", category: "UpdateManager")

    var automaticallyChecksForUpdates: Bool {
        get { engine?.automaticallyChecksForUpdates ?? true }
        set { engine?.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        engine?.lastUpdateCheckDate
    }

    /// - Parameter makeEngine: test-seam; default is de echte Sparkle-engine
    ///   (of een no-op wanneer we als unit-test-host draaien, zie
    ///   `NoopUpdaterEngine`).
    init(makeEngine: ((any SPUUserDriver) -> any UpdaterEngine)? = nil) {
        super.init()
        userDriver = InAppUserDriver(manager: self)
        if let makeEngine {
            engine = makeEngine(userDriver)
        } else if NSClassFromString("XCTestCase") != nil {
            engine = NoopUpdaterEngine()
        } else {
            engine = SparkleUpdaterEngine(userDriver: userDriver)
        }
        do {
            try engine.start()
            canCheckForUpdates = engine.canCheckForUpdates
        } catch {
            state = .error(error.localizedDescription)
        }

        engine.canCheckForUpdatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        engine.checkForUpdates()
    }

    func checkForUpdatesInBackground() {
        engine.checkForUpdatesInBackground()
    }

    /// E13.5: achtergrond-update-check bij app-launch (audit-C1). Eenmalig
    /// per proces; respecteert de "Automatic updates"-toggle (staat die uit,
    /// dan checkt de launch ook niet stilletjes).
    func checkForUpdatesInBackgroundAtLaunch() {
        guard !hasRequestedLaunchCheck else { return }
        hasRequestedLaunchCheck = true
        guard automaticallyChecksForUpdates else {
            // .notice (default level) zodat de breadcrumb in `log show`
            // terug te vinden is — .info wordt niet naar disk gepersisteerd.
            logger.notice("Launch update check skipped: automatic updates disabled")
            return
        }
        lastBackgroundCheckRequest = Date()
        logger.notice("Launch background update check requested (E13.5)")
        engine.checkForUpdatesInBackground()
    }

    func relaunchAndInstall() {
        userDriver.confirmInstallAndRelaunch()
    }

    fileprivate func updateState(_ newState: UpdateState) {
        state = newState
    }
}

// MARK: - Custom SPUUserDriver

private final class InAppUserDriver: NSObject, SPUUserDriver {
    private weak var manager: UpdateManager?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var cachedNewVersion: String?

    init(manager: UpdateManager) {
        self.manager = manager
    }

    func confirmInstallAndRelaunch() {
        installReply?(.install)
        installReply = nil
    }

    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(.init(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        Task { @MainActor in manager?.updateState(.checking) }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cachedNewVersion = appcastItem.displayVersionString
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error,
                                     acknowledgement: @escaping () -> Void) {
        Task { @MainActor in manager?.updateState(.idle) }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in manager?.updateState(.error(error.localizedDescription)) }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor in manager?.updateState(.downloading(progress: 0)) }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        Task { @MainActor in manager?.updateState(.extracting) }
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        let version = cachedNewVersion ?? ""
        Task { @MainActor in manager?.updateState(.readyToRelaunch(version: version)) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool,
                                          acknowledgement: @escaping () -> Void) {
        Task { @MainActor in manager?.updateState(.idle) }
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        installReply = nil
        cachedNewVersion = nil
        Task { @MainActor in manager?.updateState(.idle) }
    }
}
