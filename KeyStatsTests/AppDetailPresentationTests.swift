import XCTest
@testable import KeyStatsCore

final class AppDetailPresentationTests: XCTestCase {
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
                                         rangeTitle: "Today", bundle: try bundle(),
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
            rangeTitle: "Today", bundle: try bundle())
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
        let model = AppDetailPresentation(app: app, profiles: [], rangeTitle: "All Time",
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
            rangeTitle: "Today", bundle: try bundle())
        XCTAssertNil(model.cards[0].score)
        XCTAssertEqual(model.cards[0].caption, "No activity in this range")
        XCTAssertEqual(model.breakdownSummary, "0 key presses")
        var many = zero
        many.keyPresses = 300
        many.keyPressCounts = Dictionary(uniqueKeysWithValues: (1000..<1300).map { ("Key\($0)", 1) })
        let full = AppDetailPresentation(app: many, profiles: [], rangeTitle: "All Time")
        XCTAssertEqual(full.rows.count, 300)
    }
}
