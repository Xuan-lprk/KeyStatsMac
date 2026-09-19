import XCTest
@testable import KeyStatsCore

final class AppKeyBreakdownTests: XCTestCase {
    private func prepare(total: Int, counts: [String: Int]) -> AppKeyBreakdown {
        var app = AppStats(bundleId: "test.app", displayName: "Test")
        app.keyPresses = total
        app.keyPressCounts = counts
        return AppKeyBreakdown(appStats: app)
    }

    func testStableDescendingOrderWithKeyTieBreak() {
        let pairs = [("B", 3), ("A", 3), ("Return", 8)]
        let first = prepare(total: 14, counts: Dictionary(uniqueKeysWithValues: pairs))
        let second = prepare(total: 14, counts: Dictionary(uniqueKeysWithValues: pairs.reversed()))
        XCTAssertEqual(first.entries, second.entries)
        XCTAssertEqual(first.entries.map(\.key), ["Return", "A", "B"])
        XCTAssertEqual(first.entries.map(\.count), [8, 3, 3])
        XCTAssertEqual(first.coverage, .complete)
    }

    func testReusesComboNormalizationWithoutSplittingEvents() {
        let result = prepare(total: 15, counts: [
            "LeftCmd+C": 2, "RightCmd+C": 3,
            "LeftShift+RightOption+A": 4, "RightShift+LeftOption+A": 1,
            "+": 1, "Cmd++": 2, "FUNCTION+F1": 1, "Key179": 1
        ])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: result.entries.map { ($0.key, $0.count) }), [
            "Cmd+C": 5, "Shift+Option+A": 5, "+": 1, "Cmd++": 2, "Fn+F1": 1, "Fn": 1
        ])
        XCTAssertEqual(result.namedKeyPresses, 15)
        XCTAssertEqual(result.coverage, .complete)
    }

    func testLegacyTotalsAreUnavailableNotNoActivity() {
        let result = prepare(total: 100, counts: [:])
        XCTAssertEqual(result.coverage, .unavailable)
        XCTAssertEqual(result.totalKeyPresses, 100)
        XCTAssertEqual(result.namedKeyPresses, 0)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testPartialCoveragePreservesAvailableEntries() {
        let result = prepare(total: 100, counts: ["Return": 20, "A": 10])
        XCTAssertEqual(result.coverage, .partial)
        XCTAssertEqual(result.namedKeyPresses, 30)
        XCTAssertEqual(result.totalKeyPresses, 100)
        XCTAssertEqual(result.entries.map(\.count), [20, 10])
    }

    func testArrowLabelsAreDisplayOnlyAndLocalized() throws {
        var app = AppStats(bundleId: "test.app", displayName: "Test")
        app.keyPresses = 4
        app.keyPressCounts = ["Left": 1, "Right": 1, "Up": 1, "Down": 1]
        let original = app.keyPressCounts
        let result = AppKeyBreakdown(appStats: app)
        let keys = result.entries.map(\.key)
        let expected: [(String, [String])] = [
            ("en", ["Down Arrow", "Left Arrow", "Right Arrow", "Up Arrow"]),
            ("zh-Hans", ["下方向键", "左方向键", "右方向键", "上方向键"]),
            ("zh-Hant", ["下方向鍵", "左方向鍵", "右方向鍵", "上方向鍵"])
        ]
        for (language, labels) in expected {
            let bundle = try localizationBundle(language)
            XCTAssertEqual(keys.map { AppKeyBreakdown.displayKey($0, bundle: bundle) }, labels)
        }
        let english = try localizationBundle("en")
        XCTAssertEqual(AppKeyBreakdown.displayKey("Cmd+Left", bundle: english), "Cmd+Left Arrow")
        for key in ["Cmd+C", "Cmd+Shift+P", "+", "Cmd++", "Return", "Delete", "Fn+F1"] {
            XCTAssertEqual(AppKeyBreakdown.displayKey(key, bundle: english), key)
        }
        XCTAssertEqual(result.entries.map(\.key), keys)
        XCTAssertEqual(app.keyPressCounts, original)
        let encoded = try JSONEncoder().encode(app)
        XCTAssertEqual(try JSONDecoder().decode(AppStats.self, from: encoded).keyPressCounts, original)
    }

    func testFullAndPartialSummaryCopyUsesRealLocalizations() throws {
        let complete = prepare(total: 11172, counts: ["A": 11172])
        let partial = prepare(total: 11172, counts: ["A": 8421])
        let expected = [
            ("en", "11,172 key presses", "Key details available for 8,421 of 11,172 key presses."),
            ("zh-Hans", "11,172 次按键", "8,421 次有按键明细，共 11,172 次按键。"),
            ("zh-Hant", "11,172 次按鍵", "8,421 次有按鍵明細，共 11,172 次按鍵。")
        ]
        for (language, fullText, partialText) in expected {
            let bundle = try localizationBundle(language)
            XCTAssertEqual(complete.summaryText(bundle: bundle, locale: Locale(identifier: "en_US")), fullText)
            XCTAssertEqual(partial.summaryText(bundle: bundle, locale: Locale(identifier: "en_US")), partialText)
        }
        XCTAssertNil(complete.noticeLocalizationKey)
        XCTAssertEqual(partial.noticeLocalizationKey, "appStats.breakdown.incomplete")
    }

    func testEmptyCopyDistinguishesNoActivityFromUnavailableDetails() throws {
        let bundle = try localizationBundle("en")
        let empty = prepare(total: 0, counts: [:])
        let unavailable = prepare(total: 100, counts: [:])
        XCTAssertEqual(empty.summaryText(bundle: bundle), "0 key presses")
        XCTAssertEqual(empty.noticeLocalizationKey, "appStats.breakdown.noActivity")
        XCTAssertEqual(unavailable.summaryText(bundle: bundle), "Key details available for 0 of 100 key presses.")
        XCTAssertEqual(unavailable.noticeLocalizationKey, "appStats.breakdown.unavailable")
        XCTAssertEqual(bundle.localizedString(forKey: empty.noticeLocalizationKey!, value: nil, table: nil),
                       "No key presses for this app in this date range.")
    }

    private func localizationBundle(_ language: String) throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(Bundle(path: root.appendingPathComponent("KeyStats/\(language).lproj").path))
    }

    func testNoKeyboardActivityIsDistinctFromMissingHistory() {
        let result = prepare(total: 0, counts: [:])
        XCTAssertEqual(result.coverage, .noActivity)
        XCTAssertTrue(result.entries.isEmpty)
    }
}
