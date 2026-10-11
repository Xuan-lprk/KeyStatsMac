import Foundation
import XCTest
@testable import KeyStatsCore

final class CumulativeKeyboardSnapshotTests: XCTestCase {
    func testSingleDayRetainsWholeEventCountsAndDate() throws {
        let day = try stats("2026-09-01", total: 15, counts: ["A": 10, "B": 5])
        let result = CumulativeKeyboardTimeline.build(history: ["2026-09-01": day])
        XCTAssertEqual(result, [
            .init(dayKey: "2026-09-01", date: day.date, totalKeyPresses: 15,
                  keyPressCounts: ["A": 10, "B": 5], detailedKeyPresses: 15)
        ])
    }

    func testSequentialDaysAccumulateRepeatedAndDifferentKeys() throws {
        let history = [
            "2026-09-01": try stats("2026-09-01", total: 15, counts: ["A": 10, "B": 5]),
            "2026-09-02": try stats("2026-09-02", total: 11, counts: ["A": 3, "C": 8])
        ]
        let result = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertEqual(result.map(\.totalKeyPresses), [15, 26])
        XCTAssertEqual(result.map(\.keyPressCounts), [
            ["A": 10, "B": 5], ["A": 13, "B": 5, "C": 8]
        ])
        XCTAssertEqual(result.map(\.detailedKeyPresses), [15, 26])
    }

    func testMissingDaysMonthAndYearBoundariesFollowKeysInStableOrder() throws {
        let pairs = [
            ("2027-02-01", try stats("2027-02-01", total: 4, counts: ["A": 4])),
            ("2026-12-30", try stats("2026-12-30", total: 1, counts: ["A": 1])),
            ("2027-01-01", try stats("2027-01-01", total: 2, counts: ["A": 2])),
            ("2027-01-31", try stats("2027-01-31", total: 3, counts: ["A": 3]))
        ]
        let first = CumulativeKeyboardTimeline.build(history: Dictionary(uniqueKeysWithValues: pairs))
        let reversed = CumulativeKeyboardTimeline.build(history:
            Dictionary(uniqueKeysWithValues: pairs.reversed()))
        XCTAssertEqual(first, reversed)
        XCTAssertEqual(first.map(\.dayKey), ["2026-12-30", "2027-01-01", "2027-01-31", "2027-02-01"])
        XCTAssertEqual(first.map(\.totalKeyPresses), [1, 3, 6, 10])
        XCTAssertEqual(first.map { $0.keyPressCounts["A"] }, [1, 3, 6, 10])
        XCTAssertEqual(first.count, 4) // No invented records for intervening dates.
    }

    func testLegacyMissingAndPartialDetailsDoNotReplaceTotal() throws {
        let history = [
            "2026-09-01": try stats("2026-09-01", total: 10, counts: [:]),
            "2026-09-02": try stats("2026-09-02", total: 5, counts: ["Cmd+C": 2]),
            "2026-09-03": try stats("2026-09-03", total: 3, counts: ["A": 3])
        ]
        let result = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertEqual(result.map(\.totalKeyPresses), [10, 15, 18])
        XCTAssertEqual(result.map(\.detailedKeyPresses), [0, 2, 5])
        XCTAssertEqual(result.map(\.keyPressCounts), [[:], ["Cmd+C": 2], ["Cmd+C": 2, "A": 3]])
    }

    func testCanonicalCombinationsRemainRawAndMapAfterAccumulation() throws {
        let history = [
            "2026-09-01": try stats("2026-09-01", total: 6,
                counts: ["LeftCmd+C": 2, "Cmd++": 3, "+": 1]),
            "2026-09-02": try stats("2026-09-02", total: 8,
                counts: ["LeftCmd+C": 4, "RightCmd+C": 2, "BrightnessUp": 2])
        ]
        let original = history.mapValues(\.keyPressCounts)
        let cumulative = try XCTUnwrap(CumulativeKeyboardTimeline.build(history: history).last)
        XCTAssertEqual(cumulative.keyPressCounts,
            ["LeftCmd+C": 6, "RightCmd+C": 2, "Cmd++": 3, "+": 1, "BrightnessUp": 2])
        XCTAssertEqual(cumulative.totalKeyPresses, 14)
        let physical = PhysicalKeyMapping.map(cumulative.keyPressCounts)
        XCTAssertEqual(physical.counts, ["LeftCmd": 6, "RightCmd": 2, "C": 8, "Cmd": 3, "=": 4])
        XCTAssertEqual(physical.unsupported, ["BrightnessUp": 2])
        XCTAssertGreaterThan(physical.counts.values.reduce(0, +), cumulative.totalKeyPresses)
        XCTAssertEqual(history.mapValues(\.keyPressCounts), original)
    }

    func testSingleCutoffIsInclusiveAndMatchesTimelineWithoutFillingMissingDays() throws {
        let history = [
            "2026-09-01": try stats("2026-09-01", total: 2, counts: ["A": 2]),
            "2026-09-03": try stats("2026-09-03", total: 3, counts: ["A": 3])
        ]
        let timeline = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertNil(CumulativeKeyboardTimeline.snapshot(asOf: "2026-08-31", history: history))
        XCTAssertEqual(CumulativeKeyboardTimeline.snapshot(asOf: "2026-09-01", history: history), timeline[0])
        XCTAssertEqual(CumulativeKeyboardTimeline.snapshot(asOf: "2026-09-02", history: history), timeline[0])
        XCTAssertEqual(CumulativeKeyboardTimeline.snapshot(asOf: "2026-09-03", history: history), timeline[1])
        XCTAssertEqual(CumulativeKeyboardTimeline.snapshot(asOf: "2026-10-01", history: history), timeline[1])
    }

    func testEmptyHistoryAndExistingZeroActivityDays() throws {
        XCTAssertTrue(CumulativeKeyboardTimeline.build(history: [:]).isEmpty)
        XCTAssertNil(CumulativeKeyboardTimeline.snapshot(asOf: "2026-09-01", history: [:]))
        var pointerOnly = try stats("2026-09-03", total: 0, counts: [:])
        pointerOnly.leftClicks = 20
        let history = ["2026-09-01": try stats("2026-09-01", total: 0, counts: [:]),
                       "2026-09-03": pointerOnly]
        let timeline = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertEqual(timeline.map(\.dayKey), ["2026-09-01", "2026-09-03"])
        XCTAssertEqual(timeline.map(\.totalKeyPresses), [0, 0])
        XCTAssertTrue(timeline.allSatisfy { $0.keyPressCounts.isEmpty && $0.detailedKeyPresses == 0 })
    }

    func testNonpositiveCountsAndOverflowUseExistingNonnegativeSaturationPolicy() throws {
        let history = [
            "2026-09-01": try stats("2026-09-01", total: -1, counts: ["A": -5, "B": 0]),
            "2026-09-02": try stats("2026-09-02", total: Int.max, counts: ["A": Int.max]),
            "2026-09-03": try stats("2026-09-03", total: 1, counts: ["A": 1, "B": 1])
        ]
        let result = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertEqual(result[0].totalKeyPresses, 0)
        XCTAssertTrue(result[0].keyPressCounts.isEmpty)
        XCTAssertEqual(result[2].totalKeyPresses, Int.max)
        XCTAssertEqual(result[2].keyPressCounts, ["A": Int.max, "B": 1])
        XCTAssertEqual(result[2].detailedKeyPresses, Int.max)
    }

    private func stats(_ dayKey: String, total: Int, counts: [String: Int]) throws -> DailyStats {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        let date = try XCTUnwrap(calendar.date(from:
            DateComponents(year: parts[0], month: parts[1], day: parts[2])))
        var day = DailyStats(date: date)
        day.date = date // DailyStats.init uses the live calendar; fixture dates must remain fixed.
        day.keyPresses = total
        day.keyPressCounts = counts
        return day
    }
}
