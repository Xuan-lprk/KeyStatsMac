import XCTest
@testable import KeyStatsCore

final class AppStatsTests: XCTestCase {
    func testInitSetsExpectedDefaults() {
        let stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        XCTAssertEqual(stats.bundleId, "com.test.app")
        XCTAssertEqual(stats.displayName, "Test App")
        XCTAssertEqual(stats.keyPresses, 0)
        XCTAssertEqual(stats.keyPressCounts, [:])
        XCTAssertEqual(stats.leftClicks, 0)
        XCTAssertEqual(stats.rightClicks, 0)
        XCTAssertEqual(stats.sideBackClicks, 0)
        XCTAssertEqual(stats.sideForwardClicks, 0)
        XCTAssertEqual(stats.scrollDistance, 0)
        XCTAssertEqual(stats.scrollSessions, 0)
        XCTAssertEqual(stats.totalClicks, 0)
        XCTAssertFalse(stats.hasActivity)
    }

    func testRecordMethodsAccumulateCorrectly() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.recordKeyPress(keyName: "A")
        stats.recordLeftClick()
        stats.recordRightClick()
        stats.recordSideBackClick()
        stats.recordSideForwardClick()

        XCTAssertEqual(stats.keyPresses, 1)
        XCTAssertEqual(stats.keyPressCounts, ["A": 1])
        XCTAssertEqual(stats.leftClicks, 1)
        XCTAssertEqual(stats.rightClicks, 1)
        XCTAssertEqual(stats.sideBackClicks, 1)
        XCTAssertEqual(stats.sideForwardClicks, 1)
        XCTAssertEqual(stats.totalClicks, 4)
        XCTAssertTrue(stats.hasActivity)
    }

    func testRecordKeyPressAccumulatesKeyDistributionWithoutChangingTotalBehavior() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.recordKeyPress(keyName: "LeftCmd+A")
        stats.recordKeyPress(keyName: "LeftCmd+A")
        stats.recordKeyPress(keyName: "B")
        stats.recordKeyPress()

        XCTAssertEqual(stats.keyPresses, 4)
        XCTAssertEqual(stats.keyPressCounts, ["LeftCmd+A": 2, "B": 1])
    }

    func testKeyPressCountsAreIndependentBetweenApps() {
        var first = AppStats(bundleId: "com.test.first", displayName: "First")
        var second = AppStats(bundleId: "com.test.second", displayName: "Second")

        first.recordKeyPress(keyName: "A")
        first.recordKeyPress(keyName: "A")
        second.recordKeyPress(keyName: "B")

        XCTAssertEqual(first.keyPressCounts, ["A": 2])
        XCTAssertEqual(second.keyPressCounts, ["B": 1])
        XCTAssertEqual(first.keyPresses, 2)
        XCTAssertEqual(second.keyPresses, 1)
    }

    func testAddScrollDistanceUsesAbsoluteValue() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.addScrollDistance(-12.5)
        stats.addScrollDistance(7.5)

        XCTAssertEqual(stats.scrollDistance, 20.0, accuracy: 0.0001)
    }

    func testRecordScrollSessionDoesNotChangeScrollDistance() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Test App")

        stats.addScrollDistance(24.5)
        stats.recordScrollSession()
        stats.recordScrollSession()

        XCTAssertEqual(stats.scrollSessions, 2)
        XCTAssertEqual(stats.scrollDistance, 24.5, accuracy: 0.0001)
        XCTAssertTrue(stats.hasActivity)
    }

    func testScrollSessionsAreIndependentBetweenApps() {
        var first = AppStats(bundleId: "com.test.first", displayName: "First")
        var second = AppStats(bundleId: "com.test.second", displayName: "Second")

        first.recordScrollSession()
        first.recordScrollSession()
        second.recordScrollSession()

        XCTAssertEqual(first.scrollSessions, 2)
        XCTAssertEqual(second.scrollSessions, 1)
    }

    func testUpdateDisplayNameIgnoresEmptyName() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Original")

        stats.updateDisplayName("")

        XCTAssertEqual(stats.displayName, "Original")
    }

    func testUpdateDisplayNameUpdatesWhenNotEmpty() {
        var stats = AppStats(bundleId: "com.test.app", displayName: "Original")

        stats.updateDisplayName("Updated")

        XCTAssertEqual(stats.displayName, "Updated")
    }

    func testCodableRoundTripPreservesFields() throws {
        var original = AppStats(bundleId: "com.test.app", displayName: "Test App")
        original.keyPresses = 12
        original.keyPressCounts = ["A": 8, "LeftCmd+C": 4]
        original.leftClicks = 3
        original.rightClicks = 4
        original.sideBackClicks = 5
        original.sideForwardClicks = 6
        original.scrollDistance = 18.2
        original.scrollSessions = 6

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppStats.self, from: data)

        XCTAssertEqual(decoded.bundleId, original.bundleId)
        XCTAssertEqual(decoded.displayName, original.displayName)
        XCTAssertEqual(decoded.keyPresses, 12)
        XCTAssertEqual(decoded.keyPressCounts, original.keyPressCounts)
        XCTAssertEqual(decoded.leftClicks, 3)
        XCTAssertEqual(decoded.rightClicks, 4)
        XCTAssertEqual(decoded.sideBackClicks, 5)
        XCTAssertEqual(decoded.sideForwardClicks, 6)
        XCTAssertEqual(decoded.scrollDistance, 18.2, accuracy: 0.0001)
        XCTAssertEqual(decoded.scrollSessions, 6)
    }

    func testDecodeLegacyJSONWithoutKeyPressCountsDefaultsToEmpty() throws {
        let json = """
        {
          "bundleId": "com.test.legacy",
          "displayName": "Legacy App",
          "keyPresses": 12,
          "leftClicks": 1,
          "rightClicks": 2,
          "scrollDistance": 3.5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.keyPresses, 12)
        XCTAssertEqual(decoded.keyPressCounts, [:])
        XCTAssertEqual(decoded.scrollSessions, 0)
    }

    func testDecodeLegacyOtherClicksBackfillsSideBackClicks() throws {
        let json = """
        {
          "bundleId": "com.test.app",
          "displayName": "Test App",
          "keyPresses": 2,
          "leftClicks": 1,
          "rightClicks": 1,
          "otherClicks": 9,
          "scrollDistance": 4.5
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.sideBackClicks, 9)
        XCTAssertEqual(decoded.sideForwardClicks, 0)
        XCTAssertEqual(decoded.totalClicks, 11)
    }

    func testDecodeExplicitSideClicksDoesNotUseLegacyOtherClicks() throws {
        let json = """
        {
          "bundleId": "com.test.app",
          "displayName": "Test App",
          "leftClicks": 1,
          "rightClicks": 1,
          "sideBackClicks": 2,
          "sideForwardClicks": 3,
          "otherClicks": 100,
          "scrollDistance": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.sideBackClicks, 2)
        XCTAssertEqual(decoded.sideForwardClicks, 3)
        XCTAssertEqual(decoded.totalClicks, 7)
    }

    func testDecodeMissingFieldsFallsBackToZeroAndEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppStats.self, from: json)

        XCTAssertEqual(decoded.bundleId, "")
        XCTAssertEqual(decoded.displayName, "")
        XCTAssertEqual(decoded.keyPresses, 0)
        XCTAssertEqual(decoded.keyPressCounts, [:])
        XCTAssertEqual(decoded.leftClicks, 0)
        XCTAssertEqual(decoded.rightClicks, 0)
        XCTAssertEqual(decoded.sideBackClicks, 0)
        XCTAssertEqual(decoded.sideForwardClicks, 0)
        XCTAssertEqual(decoded.scrollDistance, 0)
        XCTAssertEqual(decoded.scrollSessions, 0)
        XCTAssertFalse(decoded.hasActivity)
    }
}
