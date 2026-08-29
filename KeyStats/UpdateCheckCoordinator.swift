import Foundation

enum UpdateCheckRequestAction: Equatable {
    case none
    case queued
    case startNow
}

struct UpdateCheckCoordinator {
    private(set) var hasPendingForegroundCheck = false
    private var lastAvailabilityProbeStartedAt: Date?

    mutating func requestForegroundCheck(canCheckForUpdates: Bool) -> UpdateCheckRequestAction {
        guard canCheckForUpdates else {
            hasPendingForegroundCheck = true
            return .queued
        }

        return .startNow
    }

    mutating func didUpdateCanCheckForUpdates(_ canCheckForUpdates: Bool) -> UpdateCheckRequestAction {
        guard canCheckForUpdates, hasPendingForegroundCheck else { return .none }
        hasPendingForegroundCheck = false
        return .startNow
    }

    mutating func requestAvailabilityProbe(
        now: Date,
        hasAvailableUpdate: Bool,
        sessionInProgress: Bool,
        throttleInterval: TimeInterval
    ) -> UpdateCheckRequestAction {
        guard !hasAvailableUpdate, !sessionInProgress else { return .none }

        if let lastAvailabilityProbeStartedAt,
           now.timeIntervalSince(lastAvailabilityProbeStartedAt) < throttleInterval {
            return .none
        }

        lastAvailabilityProbeStartedAt = now
        return .startNow
    }
}

struct UpdateButtonState: Equatable {
    let isHidden: Bool
    let isEnabled: Bool

    init(hasAvailableUpdate: Bool, canCheckForUpdates: Bool) {
        isHidden = !hasAvailableUpdate
        isEnabled = hasAvailableUpdate && canCheckForUpdates
    }
}
