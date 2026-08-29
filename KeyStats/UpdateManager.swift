import Foundation
import Sparkle

/// Manages Sparkle update checks and lifecycle.
final class UpdateManager: NSObject {
    static let shared = UpdateManager()

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private let availabilityProbeThrottleInterval: TimeInterval = 15 * 60
    private var updateButtonStateHandlers: [UUID: (UpdateButtonState) -> Void] = [:]
    private var sparkleNotificationObservers: [NSObjectProtocol] = []
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private var updateCheckCoordinator = UpdateCheckCoordinator()
    private(set) var hasAvailableUpdate = false
    private(set) var canCheckForUpdates = false

    private override init() {
        super.init()
        registerSparkleObservers()
        observeCanCheckForUpdates()
        probeForUpdateAvailability()
    }

    // MARK: - Updates

    func checkForUpdates() {
        if Thread.isMainThread {
            requestForegroundUpdateCheck()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.requestForegroundUpdateCheck()
            }
        }
    }

    func probeForUpdateAvailability() {
        let probe = { [weak self] in
            guard let self = self else { return }
            let updater = self.updaterController.updater
            switch self.updateCheckCoordinator.requestAvailabilityProbe(
                now: Date(),
                hasAvailableUpdate: self.hasAvailableUpdate,
                sessionInProgress: updater.sessionInProgress,
                throttleInterval: self.availabilityProbeThrottleInterval
            ) {
            case .startNow:
                updater.checkForUpdateInformation()
            case .queued:
                break
            case .none:
                break
            }
        }

        if Thread.isMainThread {
            probe()
        } else {
            DispatchQueue.main.async {
                probe()
            }
        }
    }

    func addUpdateButtonStateHandler(_ handler: @escaping (UpdateButtonState) -> Void) -> UUID {
        let token = UUID()
        updateButtonStateHandlers[token] = handler
        handler(updateButtonState)
        return token
    }

    func removeUpdateButtonStateHandler(_ token: UUID) {
        updateButtonStateHandlers.removeValue(forKey: token)
    }

    // MARK: - Private

    private var updateButtonState: UpdateButtonState {
        UpdateButtonState(
            hasAvailableUpdate: hasAvailableUpdate,
            canCheckForUpdates: canCheckForUpdates
        )
    }

    private func registerSparkleObservers() {
        let center = NotificationCenter.default
        let updater = updaterController.updater

        let willRestartObserver = center.addObserver(
            forName: NSNotification.Name.SUUpdaterWillRestart,
            object: updater,
            queue: .main
        ) { [weak self] _ in
            self?.setHasAvailableUpdate(false)
        }

        sparkleNotificationObservers = [willRestartObserver]
    }

    private func observeCanCheckForUpdates() {
        canCheckForUpdatesObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.setCanCheckForUpdates(updater.canCheckForUpdates)
            }
        }
    }

    private func requestForegroundUpdateCheck() {
        let updater = updaterController.updater
        setCanCheckForUpdates(updater.canCheckForUpdates, startsPendingCheck: false)

        switch updateCheckCoordinator.requestForegroundCheck(canCheckForUpdates: updater.canCheckForUpdates) {
        case .startNow:
            updaterController.checkForUpdates(nil)
        case .queued:
            break
        case .none:
            break
        }
    }

    private func setHasAvailableUpdate(_ hasUpdate: Bool) {
        guard hasAvailableUpdate != hasUpdate else { return }
        hasAvailableUpdate = hasUpdate
        notifyUpdateButtonStateHandlers()
    }

    private func setHasAvailableUpdateOnMain(_ hasUpdate: Bool) {
        if Thread.isMainThread {
            setHasAvailableUpdate(hasUpdate)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setHasAvailableUpdate(hasUpdate)
            }
        }
    }

    private func setCanCheckForUpdates(_ canCheck: Bool, startsPendingCheck: Bool = true) {
        let previousCanCheck = canCheckForUpdates
        canCheckForUpdates = canCheck
        if previousCanCheck != canCheck {
            notifyUpdateButtonStateHandlers()
        }

        guard startsPendingCheck else { return }
        switch updateCheckCoordinator.didUpdateCanCheckForUpdates(canCheck) {
        case .startNow:
            updaterController.checkForUpdates(nil)
        case .queued:
            break
        case .none:
            break
        }
    }

    private func notifyUpdateButtonStateHandlers() {
        let state = updateButtonState
        updateButtonStateHandlers.values.forEach { $0(state) }
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setHasAvailableUpdateOnMain(true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        setHasAvailableUpdateOnMain(false)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        setHasAvailableUpdateOnMain(false)
    }
}
