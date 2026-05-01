#if !APP_STORE
import Foundation
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

@MainActor
@Observable
final class UpdateManager: NSObject {
    private(set) var state: UpdateState = .idle
    /// Mirrors `SPUUpdater.canCheckForUpdates`. Defaults to `true` so the
    /// "Check Now" button is enabled at first paint, before Sparkle's KVO
    /// has had a chance to publish. Sparkle flips this to `false` for the
    /// duration of an active check and back to `true` when it ends — that
    /// is the only time the button should be disabled.
    private(set) var canCheckForUpdates = true

    private var updater: SPUUpdater!
    private var userDriver: InAppUserDriver!

    @ObservationIgnored
    private var cancellables = Set<AnyCancellable>()

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? true }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updater?.lastUpdateCheckDate
    }

    override init() {
        super.init()
        userDriver = InAppUserDriver(manager: self)
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        do {
            try updater.start()
            // Capture the post-start value synchronously. Don't trust the
            // publisher to deliver an initial value — Sparkle's KVO has been
            // observed to skip the initial publish, leaving the button stuck
            // disabled if `canCheckForUpdates` defaulted to false.
            canCheckForUpdates = updater.canCheckForUpdates
        } catch {
            // start() failure shouldn't disable the manual check button —
            // Sparkle may still recover, and `checkForUpdates()` is safe to
            // call regardless. Surface the error in `state`.
            state = .error(error.localizedDescription)
        }

        // DispatchQueue.main delivers in all run-loop modes. RunLoop.main
        // only delivers in default mode and silently queues during control
        // tracking (segmented pickers, sheets), which can leave the mirror
        // stale until the user clicks elsewhere.
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func checkForUpdatesInBackground() {
        updater.checkForUpdatesInBackground()
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

    // MARK: SPUUserDriver — Required Methods

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
#endif
