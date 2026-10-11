import XCTest
@testable import KeyStatsCore

final class AppDetailPresentationTests: XCTestCase {
    // Small fixture whitelist; production always passes KeyboardHeatmapView.supportedKeyIDs.
    private let supportedKeys: Set<String> = [
        "A", "C", "Z", "Cmd", "LeftCmd", "RightCmd", "Left", "Return", "Fn", "F1", "F12", "="
    ]
    private func bundle() throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(Bundle(path: root.appendingPathComponent("KeyStats/en.lproj").path))
    }

    func testRankedCardsMatchBundleAndKeepClicksHonest() throws {
        var app = AppStats(bundleId: "chosen", displayName: "Chosen")
        app.keyPresses = 10
        app.leftClicks = 2
        app.scrollDistance = 20
        app.scrollSessions = 1
        var other = AppStats(bundleId: "other", displayName: "Other")
        other.keyPresses = 20
        other.leftClicks = 4
        other.scrollDistance = 40
        other.scrollSessions = 2
        var day = DailyStats(date: Date(timeIntervalSince1970: 0))
        day.appStats = ["chosen": app, "other": other]
        let profiles = InteractionProfileCalculator.calculate(days: [day])
        let model = AppDetailPresentation(app: app, profiles: profiles.reversed(),
                                         rangeTitle: "Today", supportedHeatmapKeys: supportedKeys, bundle: try bundle(),
                                         locale: Locale(identifier: "en_US"))
        XCTAssertEqual(model.cards.map(\.score), [0.25, 0.25, 0.25])
        XCTAssertEqual(model.cards[0].rankText, "25th")
        XCTAssertEqual(model.cards[1].title, "Clicks")
        XCTAssertTrue(model.cards[1].evidence.contains("2 clicks"))
        XCTAssertTrue(model.cards[2].evidence.contains("20 px"))
        XCTAssertTrue(model.cards[2].evidence.contains("1 sessions"))
        XCTAssertTrue(model.cards[2].reference.contains("distance: 2"))
        XCTAssertEqual(model.rangeTitle, "Today")
    }

    func testSinglePositiveAndNoActivityDoNotDisplayFiftyPercentile() throws {
        var app = AppStats(bundleId: "chosen", displayName: "Chosen")
        app.keyPresses = 12
        var day = DailyStats(date: Date(timeIntervalSince1970: 0))
        day.appStats[app.bundleId] = app
        let model = AppDetailPresentation(app: app,
            profiles: InteractionProfileCalculator.calculate(days: [day]),
            rangeTitle: "Today", supportedHeatmapKeys: supportedKeys, bundle: try bundle())
        XCTAssertNil(model.cards[0].score)
        XCTAssertEqual(model.cards[0].rankText, "—")
        XCTAssertEqual(model.cards[0].caption, "Not enough comparable apps")
        XCTAssertNil(model.cards[1].score)
        XCTAssertEqual(model.cards[1].caption, "No activity in this range")
        XCTAssertEqual(model.cards[2].caption, "No activity in this range")
    }

    func testBreakdownPreservesFullListPartialCoverageAndCanonicalKeys() throws {
        var app = AppStats(bundleId: "chosen", displayName: "Chosen")
        app.keyPresses = 20
        app.keyPressCounts = ["LeftCmd+C": 4, "RightCmd+C": 4, "Left": 2, "+": 1, "Cmd++": 1]
        let original = app.keyPressCounts
        let model = AppDetailPresentation(app: app, profiles: [], rangeTitle: "All Time", supportedHeatmapKeys: supportedKeys,
                                         bundle: try bundle())
        XCTAssertEqual(model.rows.map(\.id), ["Cmd+C", "Left", "+", "Cmd++"])
        XCTAssertEqual(model.rows.map(\.usage), [1, 0.25, 0.125, 0.125])
        XCTAssertEqual(model.rows[1].label, "Left Arrow")
        XCTAssertEqual(model.breakdownSummary, "Key details available for 12 of 20 key presses.")
        XCTAssertNotNil(model.breakdownNotice)
        XCTAssertEqual(app.keyPressCounts, original)
        XCTAssertEqual(AppDetailPresentation.usage(count: 0, maximum: 0), 0)
        XCTAssertEqual(AppDetailPresentation.usage(count: 20, maximum: 10), 1)
    }

    func testZeroAppInRankedCohortIsNoActivityAndAllRowsRemainAvailable() throws {
        let zero = AppStats(bundleId: "zero", displayName: "Zero")
        var day = DailyStats(date: Date(timeIntervalSince1970: 0))
        day.appStats["zero"] = zero
        for index in 1...2 {
            var app = AppStats(bundleId: "\(index)", displayName: "\(index)")
            app.keyPresses = index
            day.appStats[app.bundleId] = app
        }
        let model = AppDetailPresentation(app: zero,
            profiles: InteractionProfileCalculator.calculate(days: [day]),
            rangeTitle: "Today", supportedHeatmapKeys: supportedKeys, bundle: try bundle())
        XCTAssertNil(model.cards[0].score)
        XCTAssertEqual(model.cards[0].caption, "No activity in this range")
        XCTAssertEqual(model.breakdownSummary, "0 key presses")
        var many = zero
        many.keyPresses = 300
        many.keyPressCounts = Dictionary(uniqueKeysWithValues: (1000..<1300).map { ("Key\($0)", 1) })
        let full = AppDetailPresentation(app: many, profiles: [], rangeTitle: "All Time", supportedHeatmapKeys: supportedKeys)
        XCTAssertEqual(full.rows.count, 300)
    }

    func testHeatmapUsesRawSideSpecificCountsAndKeepsAppSnapshotsIndependent() {
        var app = AppStats(bundleId: "first", displayName: "First")
        app.keyPresses = 8
        app.keyPressCounts = ["LeftCmd+C": 2, "RightCmd+C": 3, "Cmd+C": 3]
        let first = AppDetailPresentation(app: app, profiles: [], rangeTitle: "Today",
                                          supportedHeatmapKeys: supportedKeys)
        XCTAssertEqual(first.rows.map(\.id), ["Cmd+C"])
        XCTAssertEqual(first.heatmap.counts, ["LeftCmd": 2, "RightCmd": 3, "Cmd": 3, "C": 8])
        XCTAssertEqual(first.heatmap.coverage, .complete)
        XCTAssertNil(first.heatmap.emptyMessageKey)
        var other = AppStats(bundleId: "second", displayName: "Second")
        other.keyPresses = 1
        other.keyPressCounts = ["Z": 1]
        let second = AppDetailPresentation(app: other, profiles: [], rangeTitle: "Today",
                                           supportedHeatmapKeys: supportedKeys)
        XCTAssertEqual(second.heatmap.counts, ["Z": 1])
        XCTAssertEqual(first.heatmap.counts["C"], 8)
        XCTAssertEqual(app.keyPressCounts["RightCmd+C"], 3)
    }

    func testHeatmapCoverageIsNotComputedFromExpandedOrFilteredCounts() {
        var app = AppStats(bundleId: "app", displayName: "App")
        app.keyPresses = 10
        app.keyPressCounts = ["Cmd+C": 4]
        func snapshot() -> AppKeyboardHeatmapSnapshot {
            AppDetailPresentation(app: app, profiles: [], rangeTitle: "All Time",
                                  supportedHeatmapKeys: supportedKeys).heatmap
        }
        let partial = snapshot()
        XCTAssertEqual(partial.coverage, .partial)
        XCTAssertEqual(partial.counts, ["Cmd": 4, "C": 4])
        XCTAssertNil(partial.emptyMessageKey)
        app.keyPressCounts = [:]
        XCTAssertEqual(snapshot().coverage, .unavailable)
        XCTAssertEqual(snapshot().emptyMessageKey, "appDetail.heatmap.unavailable")
        app.keyPresses = 0
        XCTAssertEqual(snapshot().coverage, .noActivity)
        XCTAssertEqual(snapshot().emptyMessageKey, "appStats.breakdown.noActivity")
    }

    func testUnsupportedLayoutIsNotNoActivityAndDoesNotMapMediaToFunctionKeys() {
        var app = AppStats(bundleId: "app", displayName: "App")
        app.keyPressCounts = ["VolumeUp": 1, "BrightnessUp": 1, "Mute": 1, "PlayPause": 1,
                              "Rewind": 1, "FastForward": 1, "F19": 1, "Home": 1, "Key999": 1]
        app.keyPresses = app.keyPressCounts.count
        let unsupported = AppDetailPresentation(app: app, profiles: [], rangeTitle: "Today",
                                                supportedHeatmapKeys: supportedKeys)
        XCTAssertTrue(unsupported.heatmap.counts.isEmpty)
        XCTAssertEqual(unsupported.heatmap.coverage, .complete)
        XCTAssertEqual(unsupported.heatmap.emptyMessageKey, "appDetail.heatmap.unsupported")
        XCTAssertEqual(unsupported.rows.count, 9)
        app.keyPressCounts["F1"] = 2
        app.keyPresses += 2
        let mixed = AppDetailPresentation(app: app, profiles: [], rangeTitle: "Today",
                                          supportedHeatmapKeys: supportedKeys)
        XCTAssertEqual(mixed.heatmap.counts, ["F1": 2])
        XCTAssertNil(mixed.heatmap.emptyMessageKey)
    }

    func testHeatmapMapsPlusAndPreservesGenericModifierBoundaries() {
        let raw = ["+": 4, "Cmd++": 3, "LeftCmd+C": 2, "Function+A": 1]
        let snapshot = AppKeyboardHeatmapSnapshot(rawCounts: raw, coverage: .complete,
                                                  supportedKeys: supportedKeys)
        // Plus uses the '=' key without collapsing explicit or generic modifiers.
        XCTAssertEqual(snapshot.counts, ["Cmd": 3, "LeftCmd": 2, "C": 2, "Fn": 1, "A": 1, "=": 7])
        XCTAssertEqual(snapshot.counts["="], 7)
    }

    func testBridgeApplyGateSkipsEqualSnapshotsAndResetsForNewView() {
        var state = KeyboardHeatmapApplyState()
        XCTAssertTrue(state.accept([:]))
        XCTAssertFalse(state.accept([:]))
        XCTAssertTrue(state.accept(["C": 2, "Cmd": 2]))
        XCTAssertFalse(state.accept(["Cmd": 2, "C": 2]))
        XCTAssertTrue(state.accept(["C": 3, "Cmd": 2]))
        XCTAssertTrue(state.accept([:]))
        var newView = KeyboardHeatmapApplyState()
        XCTAssertTrue(newView.accept([:]))
    }
}
