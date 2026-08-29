import XCTest
@testable import KeyStatsCore

final class UpdateCheckCoordinatorTests: XCTestCase {
    private let probeThrottleInterval: TimeInterval = 15 * 60

    func testForegroundCheckRequestsAreQueuedWhileSparkleCannotCheck() {
        var coordinator = UpdateCheckCoordinator()

        XCTAssertEqual(coordinator.requestForegroundCheck(canCheckForUpdates: false), .queued)
        XCTAssertEqual(coordinator.didUpdateCanCheckForUpdates(false), .none)
        XCTAssertEqual(coordinator.didUpdateCanCheckForUpdates(true), .startNow)
        XCTAssertEqual(coordinator.didUpdateCanCheckForUpdates(true), .none)
    }

    func testUpdateButtonStaysVisibleButDisabledWhenUpdateExistsAndSparkleIsBusy() {
        let busyState = UpdateButtonState(hasAvailableUpdate: true, canCheckForUpdates: false)
        XCTAssertFalse(busyState.isHidden)
        XCTAssertFalse(busyState.isEnabled)

        let readyState = UpdateButtonState(hasAvailableUpdate: true, canCheckForUpdates: true)
        XCTAssertFalse(readyState.isHidden)
        XCTAssertTrue(readyState.isEnabled)
    }

    func testAvailabilityProbeIsThrottledAfterStarting() {
        var coordinator = UpdateCheckCoordinator()
        let firstProbeDate = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            coordinator.requestAvailabilityProbe(
                now: firstProbeDate,
                hasAvailableUpdate: false,
                sessionInProgress: false,
                throttleInterval: probeThrottleInterval
            ),
            .startNow
        )
        XCTAssertEqual(
            coordinator.requestAvailabilityProbe(
                now: firstProbeDate.addingTimeInterval(probeThrottleInterval - 1),
                hasAvailableUpdate: false,
                sessionInProgress: false,
                throttleInterval: probeThrottleInterval
            ),
            .none
        )
        XCTAssertEqual(
            coordinator.requestAvailabilityProbe(
                now: firstProbeDate.addingTimeInterval(probeThrottleInterval),
                hasAvailableUpdate: false,
                sessionInProgress: false,
                throttleInterval: probeThrottleInterval
            ),
            .startNow
        )
    }

    func testAvailabilityProbeDoesNotStartWhenUpdateAlreadyAvailableOrSessionInProgress() {
        var coordinator = UpdateCheckCoordinator()
        let now = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(
            coordinator.requestAvailabilityProbe(
                now: now,
                hasAvailableUpdate: true,
                sessionInProgress: false,
                throttleInterval: probeThrottleInterval
            ),
            .none
        )
        XCTAssertEqual(
            coordinator.requestAvailabilityProbe(
                now: now,
                hasAvailableUpdate: false,
                sessionInProgress: true,
                throttleInterval: probeThrottleInterval
            ),
            .none
        )
    }
}
