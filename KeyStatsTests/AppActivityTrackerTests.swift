import Darwin
import XCTest
@testable import KeyStatsCore

final class AppActivityTrackerTests: XCTestCase {
    func testRemovingTerminatedPIDKeepsOtherPIDAndDisplayNameEntries() {
        var cache = PIDAppIdentityCache()
        let terminatedPID: pid_t = 101
        let sameAppPID: pid_t = 102
        let otherAppPID: pid_t = 103

        cache.store(bundleId: "com.test.same", displayName: "Same App", forPID: terminatedPID)
        cache.store(bundleId: "com.test.same", displayName: "", forPID: sameAppPID)
        cache.store(bundleId: "com.test.other", displayName: "Other App", forPID: otherAppPID)

        XCTAssertTrue(cache.removePID(terminatedPID, matchingBundleId: "com.test.same"))
        XCTAssertNil(cache.identity(forPID: terminatedPID))
        XCTAssertEqual(
            cache.identity(forPID: sameAppPID),
            AppIdentity(bundleId: "com.test.same", displayName: "Same App")
        )
        XCTAssertEqual(
            cache.identity(forPID: otherAppPID),
            AppIdentity(bundleId: "com.test.other", displayName: "Other App")
        )
    }

    func testDelayedTerminationDoesNotRemoveReusedPID() {
        var cache = PIDAppIdentityCache()
        let reusedPID: pid_t = 201

        cache.store(bundleId: "com.test.new", displayName: "New App", forPID: reusedPID)

        XCTAssertFalse(cache.removePID(reusedPID, matchingBundleId: "com.test.old"))
        XCTAssertEqual(
            cache.identity(forPID: reusedPID),
            AppIdentity(bundleId: "com.test.new", displayName: "New App")
        )
    }

    func testPIDCanBeCachedForNewAppAfterTermination() {
        var cache = PIDAppIdentityCache()
        let reusedPID: pid_t = 301

        cache.store(bundleId: "com.test.old", displayName: "Old App", forPID: reusedPID)
        XCTAssertTrue(cache.removePID(reusedPID, matchingBundleId: "com.test.old"))
        cache.store(bundleId: "com.test.new", displayName: "New App", forPID: reusedPID)

        XCTAssertEqual(
            cache.identity(forPID: reusedPID),
            AppIdentity(bundleId: "com.test.new", displayName: "New App")
        )
    }

    func testTerminationWithoutBundleIdentifierStillRemovesPID() {
        var cache = PIDAppIdentityCache()
        let terminatedPID: pid_t = 401

        cache.store(bundleId: "com.test.app", displayName: "Test App", forPID: terminatedPID)

        XCTAssertTrue(cache.removePID(terminatedPID, matchingBundleId: nil))
        XCTAssertNil(cache.identity(forPID: terminatedPID))
    }

    func testUpdatedDisplayNameIsReusedWithoutKeepingTerminatedPID() {
        var cache = PIDAppIdentityCache()
        let oldPID: pid_t = 501
        let newPID: pid_t = 502

        cache.store(bundleId: "com.test.app", displayName: "Old Name", forPID: oldPID)
        cache.storeDisplayName("New Name", forBundleId: "com.test.app")
        XCTAssertTrue(cache.removePID(oldPID, matchingBundleId: "com.test.app"))

        cache.store(bundleId: "com.test.app", displayName: "", forPID: newPID)

        XCTAssertNil(cache.identity(forPID: oldPID))
        XCTAssertEqual(
            cache.identity(forPID: newPID),
            AppIdentity(bundleId: "com.test.app", displayName: "New Name")
        )
    }
}
