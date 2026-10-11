import Foundation
import XCTest
@testable import KeyStatsCore

final class KeyboardTrackingPeriodTests: XCTestCase {
    func testFirstTrackedDayIgnoresEarlierNonkeyboardRecordsAndUsesLegacyTotal() throws {
        let context = try dateContext()
        var mouse = try stats("2026-09-27", context: context)
        mouse.leftClicks = 50
        var scroll = try stats("2026-09-28", context: context)
        scroll.scrollDistance = 100
        scroll.scrollSessions = 4
        var residualDetails = try stats("2026-09-29", context: context)
        residualDetails.keyPressCounts = ["A": 10]
        let pairs = [
            ("2026-09-26", try stats("2026-09-26", context: context)),
            ("2026-09-27", mouse),
            ("2026-09-28", scroll),
            ("2026-09-29", residualDetails),
            ("2026-10-01", try stats("2026-10-01", total: 10, context: context)),
            ("2026-10-03", try stats("2026-10-03", total: 2, context: context))
        ]
        let history = Dictionary(uniqueKeysWithValues: pairs)
        let first = try XCTUnwrap(period(history, context: context))
        let reversed = try XCTUnwrap(period(Dictionary(uniqueKeysWithValues: pairs.reversed()), context: context))
        XCTAssertEqual(first.firstTrackedDayKey, "2026-10-01")
        XCTAssertEqual(first.firstTrackedDate, try XCTUnwrap(context.formatter.date(from: "2026-10-01")))
        XCTAssertTrue(history["2026-10-01"]!.keyPressCounts.isEmpty)
        XCTAssertEqual(first.dayIndex(for: "2026-10-01"), 1)
        XCTAssertEqual(first.firstTrackedDayKey, reversed.firstTrackedDayKey)
        XCTAssertEqual(first.firstTrackedDate, reversed.firstTrackedDate)
        XCTAssertEqual(first.dayIndex(for: "2026-10-03"), reversed.dayIndex(for: "2026-10-03"))
    }

    func testNoKeyboardActivityHasNoPeriod() throws {
        let context = try dateContext()
        XCTAssertNil(period([:], context: context))
        var mouse = try stats("2026-10-01", context: context)
        mouse.mouseDistance = 100
        mouse.keyPressCounts = ["A": 4]
        XCTAssertNil(period(["2026-10-01": mouse], context: context))
        let negative = try stats("2026-10-02", total: -1, context: context)
        XCTAssertNil(period(["2026-10-01": mouse, "2026-10-02": negative], context: context))
    }

    func testMissingRecordsStillCountAsElapsedCalendarDays() throws {
        let context = try dateContext()
        let history = [
            "2026-10-01": try stats("2026-10-01", total: 10, context: context),
            "2026-10-03": try stats("2026-10-03", total: 5, context: context)
        ]
        let tracking = try XCTUnwrap(period(history, context: context))
        XCTAssertEqual(tracking.dayIndex(for: "2026-10-01"), 1)
        XCTAssertEqual(tracking.dayIndex(for: "2026-10-02"), 2) // No record needed.
        XCTAssertEqual(tracking.dayIndex(for: "2026-10-03"), 3)
        let snapshots = CumulativeKeyboardTimeline.build(history: history)
        XCTAssertEqual(snapshots.map { tracking.dayIndex(for: $0) }, [1, 3])
        XCTAssertEqual(snapshots.map(\.totalKeyPresses), [10, 15])
    }

    func testMonthYearAndLeapDayBoundaries() throws {
        let context = try dateContext()
        for (first, target, expected) in [
            ("2026-09-30", "2026-10-01", 2),
            ("2026-12-31", "2027-01-02", 3),
            ("2024-02-28", "2024-02-29", 2),
            ("2024-02-28", "2024-03-01", 3),
            ("2025-02-28", "2025-03-01", 2)
        ] {
            let tracking = try XCTUnwrap(period(
                [first: try stats(first, total: 1, context: context)], context: context))
            XCTAssertEqual(tracking.dayIndex(for: target), expected, "\(first) → \(target)")
        }
    }

    func testDSTUsesCalendarDaysForBothShortAndLongDays() throws {
        let context = try dateContext(timeZone: "America/Los_Angeles")
        for (first, target, elapsedHours) in [
            ("2026-03-07", "2026-03-09", 47.0),
            ("2026-10-31", "2026-11-02", 49.0)
        ] {
            let tracking = try XCTUnwrap(period(
                [first: try stats(first, total: 1, context: context)], context: context))
            let end = try XCTUnwrap(context.formatter.date(from: target))
            XCTAssertEqual(end.timeIntervalSince(tracking.firstTrackedDate) / 3600,
                           elapsedHours, accuracy: 1e-9)
            XCTAssertEqual(tracking.dayIndex(for: target), 3)
        }
    }

    func testEarlierAndInvalidTargetDatesHaveNoIndex() throws {
        let context = try dateContext()
        let tracking = try XCTUnwrap(period(
            ["2026-10-01": try stats("2026-10-01", total: 1, context: context)], context: context))
        for key in ["2026-09-30", "bad-date", "2026-02-30", "2026-10-1"] {
            XCTAssertNil(tracking.dayIndex(for: key), key)
        }
        XCTAssertEqual(tracking.dayIndex(for: "2026-10-01"), 1)
    }

    func testSnapshotUsesHistoricalKeyAndRetainsItsFormattingContext() throws {
        let context = try dateContext(timeZone: "Pacific/Kiritimati")
        let tracking = try XCTUnwrap(period(
            ["2026-10-01": try stats("2026-10-01", total: 1, context: context)], context: context))
        let snapshot = CumulativeKeyboardSnapshot(
            dayKey: "2026-10-03",
            date: try XCTUnwrap(context.formatter.date(from: "2026-10-04")),
            totalKeyPresses: 10, keyPressCounts: [:], detailedKeyPresses: 0)
        XCTAssertEqual(tracking.dayIndex(for: snapshot), 3)
        context.formatter.timeZone = TimeZone(identifier: "Etc/GMT+12")
        context.formatter.dateFormat = "MM/dd/yyyy"
        XCTAssertEqual(tracking.dayIndex(for: snapshot), 3)
    }

    private func dateContext(timeZone: String = "UTC") throws -> (calendar: Calendar, formatter: DateFormatter) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale
        formatter.dateFormat = "yyyy-MM-dd"
        return (calendar, formatter)
    }

    private func stats(
        _ dayKey: String, total: Int = 0,
        context: (calendar: Calendar, formatter: DateFormatter)
    ) throws -> DailyStats {
        let date = try XCTUnwrap(context.formatter.date(from: dayKey))
        var stats = DailyStats(date: date)
        stats.date = date // Keep fixtures independent of DailyStats' live calendar initializer.
        stats.keyPresses = total
        return stats
    }

    private func period(
        _ history: [String: DailyStats],
        context: (calendar: Calendar, formatter: DateFormatter)
    ) -> KeyboardTrackingPeriod? {
        KeyboardTrackingPeriod(history: history, calendar: context.calendar, dateKeyFormatter: context.formatter)
    }
}
