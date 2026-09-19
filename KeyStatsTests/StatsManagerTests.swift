import Foundation
import XCTest
@testable import KeyStatsCore

private final class MutableTestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private struct StatsManagerTestContext {
    let suiteName: String
    let defaults: UserDefaults
    let calendar: Calendar
    let clock: MutableTestClock

    func makeManager(blocksLegacyImport: @escaping () -> Bool = { false }) -> StatsManager {
        StatsManager(environment: StatsManager.Environment(
            userDefaults: defaults,
            now: { clock.now },
            calendar: { calendar },
            makeDateKeyFormatter: {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            },
            notificationCenter: NotificationCenter(),
            schedulesAutomaticWork: false,
            blocksLegacyImport: blocksLegacyImport,
            syncDisplayContext: { nil },
            sendThresholdNotification: { _, _, _ in }
        ))
    }

    func day(offset: Int) -> Date {
        let today = calendar.startOfDay(for: clock.now)
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct StatsImportPayload: Encodable {
    let version: Int
    let scope: String?
    let exportedAt: Date
    let currentStats: DailyStats
    let history: [String: DailyStats]
}

final class StatsManagerTests: XCTestCase {
    private let statsKey = "dailyStats"
    private let historyKey = "dailyStatsHistory"

    func testLoadPrefersPersistedCurrentForTodayOverHistoryToday() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let today = context.day(offset: 0)
        let yesterday = context.day(offset: -1)
        let current = makeStats(on: today, keyPresses: 11)
        let historyToday = makeStats(on: today, keyPresses: 99)
        let historyYesterday = makeStats(on: yesterday, keyPresses: 4)
        try seed(
            defaults: context.defaults,
            current: current,
            history: [
                context.dayKey(today): historyToday,
                context.dayKey(yesterday): historyYesterday
            ]
        )

        let manager = context.makeManager()
        let snapshot = manager.localSyncHistorySnapshot()

        XCTAssertEqual(manager.currentStats.keyPresses, 11)
        XCTAssertEqual(snapshot[context.dayKey(today)]?.keyPresses, 11)
        XCTAssertEqual(snapshot[context.dayKey(yesterday)]?.keyPresses, 4)
    }

    func testLoadFallsBackToHistoryTodayWhenPersistedCurrentIsStale() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let today = context.day(offset: 0)
        let yesterday = context.day(offset: -1)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: yesterday, keyPresses: 5),
            history: [context.dayKey(today): makeStats(on: today, keyPresses: 22)]
        )

        let manager = context.makeManager()

        XCTAssertTrue(context.calendar.isDate(manager.currentStats.date, inSameDayAs: today))
        XCTAssertEqual(manager.currentStats.keyPresses, 22)
    }

    func testMalformedCurrentFallsBackToValidHistoryToday() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let today = context.day(offset: 0)
        context.defaults.set(Data("not-json".utf8), forKey: statsKey)
        context.defaults.set(
            try JSONEncoder().encode([context.dayKey(today): makeStats(on: today, keyPresses: 13)]),
            forKey: historyKey
        )

        let manager = context.makeManager()

        XCTAssertEqual(manager.currentStats.keyPresses, 13)
    }

    func testMalformedHistoryDoesNotDiscardValidCurrentToday() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let today = context.day(offset: 0)
        context.defaults.set(try JSONEncoder().encode(makeStats(on: today, keyPresses: 8)), forKey: statsKey)
        context.defaults.set(Data("not-json".utf8), forKey: historyKey)

        let manager = context.makeManager()

        XCTAssertEqual(manager.currentStats.keyPresses, 8)
        let persistedHistoryData = try XCTUnwrap(context.defaults.data(forKey: historyKey))
        let persistedHistory = try JSONDecoder().decode([String: DailyStats].self, from: persistedHistoryData)
        XCTAssertEqual(persistedHistory[context.dayKey(today)]?.keyPresses, 8)
    }

    func testMalformedCurrentAndHistoryRecoverToPersistedZeroToday() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        context.defaults.set(Data("bad-current".utf8), forKey: statsKey)
        context.defaults.set(Data("bad-history".utf8), forKey: historyKey)

        let manager = context.makeManager()

        XCTAssertEqual(manager.currentStats.keyPresses, 0)
        XCTAssertTrue(context.calendar.isDate(manager.currentStats.date, inSameDayAs: context.clock.now))
        XCTAssertNoThrow(try decodePersistedCurrent(from: context.defaults))
        XCTAssertNoThrow(try decodePersistedHistory(from: context.defaults))
    }

    func testHistoryNormalizationPreservesDistinctValidDayKeysAcrossTimeZoneShift() throws {
        let targetTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 14 * 60 * 60))
        let context = try makeContext(timeZone: targetTimeZone)
        defer { context.cleanUp() }

        let westTimeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -12 * 60 * 60))
        let firstDate = try makeDate(year: 2026, month: 1, day: 1, timeZone: westTimeZone)
        let secondDate = try makeDate(year: 2026, month: 1, day: 2, timeZone: targetTimeZone)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: context.day(offset: 0)),
            history: [
                "2026-01-01": makeStats(on: firstDate, keyPresses: 11),
                "2026-01-02": makeStats(on: secondDate, keyPresses: 22)
            ]
        )

        let snapshot = context.makeManager().localSyncHistorySnapshot()

        XCTAssertEqual(snapshot["2026-01-01"]?.keyPresses, 11)
        XCTAssertEqual(snapshot["2026-01-02"]?.keyPresses, 22)
    }

    func testHistoryNormalizationUsesValidKeyAsDateIdentityWhenStoredDateDisagrees() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let keyDate = try makeDate(year: 2026, month: 5, day: 10, timeZone: context.calendar.timeZone)
        let storedDate = try makeDate(year: 2026, month: 5, day: 11, timeZone: context.calendar.timeZone)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: context.day(offset: 0)),
            history: ["2026-05-10": makeStats(on: storedDate, keyPresses: 7)]
        )

        let snapshot = context.makeManager().localSyncHistorySnapshot()
        let normalized = try XCTUnwrap(snapshot["2026-05-10"])

        XCTAssertEqual(normalized.keyPresses, 7)
        XCTAssertEqual(normalized.date, context.calendar.startOfDay(for: keyDate))
        XCTAssertNil(snapshot["2026-05-11"])
    }

    func testHistoryNormalizationKeepsOrdinaryCanonicalEntryUnchanged() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let date = try makeDate(year: 2026, month: 5, day: 12, timeZone: context.calendar.timeZone)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: context.day(offset: 0)),
            history: ["2026-05-12": makeStats(on: date, keyPresses: 8)]
        )

        let normalized = try XCTUnwrap(context.makeManager().localSyncHistorySnapshot()["2026-05-12"])

        XCTAssertEqual(normalized.keyPresses, 8)
        XCTAssertEqual(normalized.date, context.calendar.startOfDay(for: date))
    }

    func testHistoryNormalizationFallsBackToStoredDateForInvalidKey() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let date = try makeDate(year: 2026, month: 5, day: 13, timeZone: context.calendar.timeZone)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: context.day(offset: 0)),
            history: ["legacy-entry": makeStats(on: date, keyPresses: 9)]
        )

        let snapshot = context.makeManager().localSyncHistorySnapshot()

        XCTAssertNil(snapshot["legacy-entry"])
        XCTAssertEqual(snapshot["2026-05-13"]?.keyPresses, 9)
    }

    func testHistoryNormalizationFallbackCollisionIsStableAcrossInputOrder() throws {
        let firstContext = try makeContext()
        let secondContext = try makeContext()
        defer {
            firstContext.cleanUp()
            secondContext.cleanUp()
        }

        let date = try makeDate(year: 2026, month: 5, day: 14, timeZone: firstContext.calendar.timeZone)
        let firstEntries = [
            ("z-invalid", makeStats(on: date, keyPresses: 90)),
            ("a-invalid", makeStats(on: date, keyPresses: 30))
        ]
        let secondEntries = Array(firstEntries.reversed())
        try seed(
            defaults: firstContext.defaults,
            current: makeStats(on: firstContext.day(offset: 0)),
            history: Dictionary(uniqueKeysWithValues: firstEntries)
        )
        try seed(
            defaults: secondContext.defaults,
            current: makeStats(on: secondContext.day(offset: 0)),
            history: Dictionary(uniqueKeysWithValues: secondEntries)
        )

        let firstResult = firstContext.makeManager().localSyncHistorySnapshot()["2026-05-14"]
        let secondResult = secondContext.makeManager().localSyncHistorySnapshot()["2026-05-14"]

        XCTAssertEqual(firstResult?.keyPresses, 30)
        XCTAssertEqual(secondResult?.keyPresses, 30)
    }

    func testHistoryNormalizationPrefersValidKeyOverInvalidFallbackCollision() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let date = try makeDate(year: 2026, month: 5, day: 15, timeZone: context.calendar.timeZone)
        try seed(
            defaults: context.defaults,
            current: makeStats(on: context.day(offset: 0)),
            history: [
                "2026-05-15": makeStats(on: date, keyPresses: 15),
                "a-invalid": makeStats(on: date, keyPresses: 99)
            ]
        )

        let snapshot = context.makeManager().localSyncHistorySnapshot()

        XCTAssertEqual(snapshot["2026-05-15"]?.keyPresses, 15)
    }

    func testFlushPersistsDataForASecondManagerUsingTheSameSuite() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        var first: StatsManager? = context.makeManager()
        first?.incrementKeyPresses(keyName: "A")
        first?.incrementLeftClicks()
        first?.flushPendingSave()
        first = nil

        let restored = context.makeManager()

        XCTAssertEqual(restored.currentStats.keyPresses, 1)
        XCTAssertEqual(restored.currentStats.keyPressCounts, ["A": 1])
        XCTAssertEqual(restored.currentStats.leftClicks, 1)
    }

    func testImportOverwriteReplacesLocalHistoryAndCurrentWinsPayloadTodayConflict() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        let today = context.day(offset: 0)
        let localOnlyDay = context.day(offset: -3)
        let importedDay = context.day(offset: -1)

        try manager.importStatsData(
            from: try importData(
                current: makeStats(on: today, keyPresses: 2),
                history: [context.dayKey(localOnlyDay): makeStats(on: localOnlyDay, keyPresses: 4)]
            ),
            mode: .overwrite
        )

        try manager.importStatsData(
            from: try importData(
                current: makeStats(on: today, keyPresses: 7),
                history: [
                    context.dayKey(today): makeStats(on: today, keyPresses: 99),
                    context.dayKey(importedDay): makeStats(on: importedDay, keyPresses: 3)
                ]
            ),
            mode: .overwrite
        )

        let snapshot = manager.localSyncHistorySnapshot()
        XCTAssertNil(snapshot[context.dayKey(localOnlyDay)])
        XCTAssertEqual(snapshot[context.dayKey(importedDay)]?.keyPresses, 3)
        XCTAssertEqual(snapshot[context.dayKey(today)]?.keyPresses, 7)
        XCTAssertEqual(manager.currentStats.keyPresses, 7)
    }

    func testImportMergeCombinesCurrentCountersKeysAppsAndDistinctDays() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        let today = context.day(offset: 0)
        let baseDay = context.day(offset: -2)
        let importedDay = context.day(offset: -1)

        var baseToday = makeStats(on: today, keyPresses: 10)
        baseToday.leftClicks = 2
        baseToday.mouseDistance = 4
        baseToday.scrollSessions = 1
        baseToday.peakKPS = 3
        baseToday.keyPressCounts = ["Fn+A": 2]
        var baseApp = AppStats(bundleId: "com.test.editor", displayName: "Base Editor")
        baseApp.keyPresses = 2
        baseApp.keyPressCounts = ["A": 2]
        baseApp.leftClicks = 1
        baseApp.scrollSessions = 1
        baseToday.appStats[baseApp.bundleId] = baseApp

        try manager.importStatsData(
            from: try importData(
                current: baseToday,
                history: [context.dayKey(baseDay): makeStats(on: baseDay, keyPresses: 4)]
            ),
            mode: .overwrite
        )

        var importedToday = makeStats(on: today, keyPresses: 7)
        importedToday.rightClicks = 3
        importedToday.mouseDistance = 6
        importedToday.scrollSessions = 2
        importedToday.peakKPS = 5
        importedToday.keyPressCounts = ["Function+A": 3, "B": 4]
        var importedApp = AppStats(bundleId: "com.test.editor", displayName: "Imported Editor")
        importedApp.keyPresses = 3
        importedApp.keyPressCounts = ["A": 1, "B": 2]
        importedApp.rightClicks = 2
        importedApp.scrollSessions = 2
        importedToday.appStats[importedApp.bundleId] = importedApp

        try manager.importStatsData(
            from: try importData(
                current: importedToday,
                history: [context.dayKey(importedDay): makeStats(on: importedDay, keyPresses: 6)]
            ),
            mode: .merge
        )

        let snapshot = manager.localSyncHistorySnapshot()
        let merged = try XCTUnwrap(snapshot[context.dayKey(today)])
        let mergedApp = try XCTUnwrap(merged.appStats["com.test.editor"])

        XCTAssertEqual(merged.keyPresses, 17)
        XCTAssertEqual(merged.leftClicks, 2)
        XCTAssertEqual(merged.rightClicks, 3)
        XCTAssertEqual(merged.mouseDistance, 10, accuracy: 0.0001)
        XCTAssertEqual(merged.scrollSessions, 3)
        XCTAssertEqual(merged.peakKPS, 5)
        XCTAssertEqual(merged.keyPressCounts, ["Fn+A": 5, "B": 4])
        XCTAssertEqual(mergedApp.displayName, "Imported Editor")
        XCTAssertEqual(mergedApp.keyPresses, 5)
        XCTAssertEqual(mergedApp.keyPressCounts, ["A": 3, "B": 2])
        XCTAssertEqual(mergedApp.leftClicks, 1)
        XCTAssertEqual(mergedApp.rightClicks, 2)
        XCTAssertEqual(mergedApp.scrollSessions, 3)
        XCTAssertEqual(snapshot[context.dayKey(baseDay)]?.keyPresses, 4)
        XCTAssertEqual(snapshot[context.dayKey(importedDay)]?.keyPresses, 6)
    }

    func testMalformedImportDoesNotMutateExistingStats() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        manager.incrementKeyPresses(keyName: "A")
        let before = manager.localSyncHistorySnapshot()

        XCTAssertThrowsError(try manager.importStatsData(from: Data("not-json".utf8), mode: .overwrite))

        let after = manager.localSyncHistorySnapshot()
        XCTAssertEqual(manager.currentStats.keyPresses, 1)
        XCTAssertEqual(after[context.dayKey(context.day(offset: 0))]?.keyPresses, 1)
        XCTAssertEqual(after.count, before.count)
    }

    func testRolloverAfterFlushedDayKeepsPreviousDayAndStartsNewCurrentDay() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        let firstDay = context.day(offset: 0)
        manager.incrementKeyPresses(keyName: "A")
        manager.incrementKeyPresses(keyName: "A")
        manager.flushPendingSave()

        let secondDay = context.calendar.date(byAdding: .day, value: 1, to: context.clock.now)!
        context.clock.now = secondDay
        manager.incrementKeyPresses(keyName: "B")

        let snapshot = manager.localSyncHistorySnapshot()
        XCTAssertTrue(context.calendar.isDate(manager.currentStats.date, inSameDayAs: secondDay))
        XCTAssertEqual(manager.currentStats.keyPresses, 1)
        XCTAssertEqual(manager.currentStats.keyPressCounts, ["B": 1])
        XCTAssertEqual(snapshot[context.dayKey(firstDay)]?.keyPresses, 2)
        XCTAssertEqual(snapshot[context.dayKey(context.calendar.startOfDay(for: secondDay))]?.keyPresses, 1)
    }

    func testRolloverPreservesUnflushedPreviousDayBeforeCountingNewDayInput() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        let firstDay = context.day(offset: 0)
        manager.incrementKeyPresses(keyName: "A")
        manager.incrementKeyPresses(keyName: "A")

        let secondDay = context.calendar.date(byAdding: .day, value: 1, to: context.clock.now)!
        context.clock.now = secondDay
        manager.incrementKeyPresses(keyName: "B")

        let snapshot = manager.localSyncHistorySnapshot()
        XCTAssertEqual(snapshot[context.dayKey(firstDay)]?.keyPresses, 2)
        XCTAssertEqual(snapshot[context.dayKey(firstDay)]?.keyPressCounts, ["A": 2])
        XCTAssertTrue(context.calendar.isDate(manager.currentStats.date, inSameDayAs: secondDay))
        XCTAssertEqual(manager.currentStats.keyPresses, 1)
        XCTAssertEqual(manager.currentStats.keyPressCounts, ["B": 1])
    }

    func testAllTimeAggregationUsesLocalHistoryWithoutDoubleCountingCurrentDay() throws {
        let context = try makeContext()
        defer { context.cleanUp() }

        let manager = context.makeManager()
        let today = context.day(offset: 0)
        let yesterday = context.day(offset: -1)
        var current = makeStats(on: today, keyPresses: 4)
        current.leftClicks = 1
        current.scrollSessions = 1
        var past = makeStats(on: yesterday, keyPresses: 6)
        past.rightClicks = 2
        past.scrollSessions = 2

        try manager.importStatsData(
            from: try importData(
                current: current,
                history: [context.dayKey(yesterday): past]
            ),
            mode: .overwrite
        )

        let allTime = manager.getAllTimeStats()

        XCTAssertEqual(allTime.totalKeyPresses, 10)
        XCTAssertEqual(allTime.totalLeftClicks, 1)
        XCTAssertEqual(allTime.totalRightClicks, 2)
        XCTAssertEqual(allTime.totalScrollSessions, 3)
        XCTAssertEqual(allTime.activeDays, 2)
        XCTAssertTrue(context.calendar.isDate(try XCTUnwrap(allTime.firstDate), inSameDayAs: yesterday))
        XCTAssertTrue(context.calendar.isDate(try XCTUnwrap(allTime.lastDate), inSameDayAs: today))
    }

    func testAppBreakdownUsesSelectedRangeSummaryAndDetectsPartialHistory() throws {
        let context = try makeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        defer { context.cleanUp() }
        func daily(_ offset: Int, total: Int, counts: [String: Int]) -> DailyStats {
            var day = makeStats(on: context.day(offset: offset), keyPresses: total)
            var app = AppStats(bundleId: "selected.app", displayName: "Selected")
            app.keyPresses = total
            app.keyPressCounts = counts
            app.leftClicks = total
            app.scrollDistance = Double(total * 10)
            app.scrollSessions = total
            day.appStats[app.bundleId] = app
            var other = AppStats(bundleId: "other.app", displayName: "Other")
            other.keyPresses = 999
            other.keyPressCounts = ["Z": 999]
            day.appStats[other.bundleId] = other
            return day
        }
        let current = daily(0, total: 2, counts: ["LeftCmd+C": 2])
        let days = [daily(-1, total: 10, counts: [:]),
                    daily(-8, total: 3, counts: ["RightCmd+C": 3]),
                    daily(-31, total: 4, counts: ["Return": 4])]
        try seed(defaults: context.defaults, current: current,
                 history: Dictionary(uniqueKeysWithValues: days.map { (context.dayKey($0.date), $0) }))
        let manager = context.makeManager()
        let expectations: [(StatsManager.AppStatsRange, Int, Int, AppKeyBreakdown.Coverage)] = [
            (.today, 2, 2, .complete), (.week, 12, 2, .partial),
            (.month, 15, 5, .partial), (.all, 19, 9, .partial)
        ]
        for (range, total, named, coverage) in expectations {
            let defaultsBefore = context.defaults.dictionaryRepresentation() as NSDictionary
            let app = try XCTUnwrap(manager.appStatsSummary(range: range)
                .first { $0.bundleId == "selected.app" })
            let profile = try XCTUnwrap(manager.interactionProfiles(range: range)
                .first { $0.bundleId == app.bundleId })
            XCTAssertEqual(profile.keyboard.rawValue, Double(total))
            XCTAssertEqual(profile.pointer.rawValue, Double(app.totalClicks))
            XCTAssertEqual(profile.scroll.distance.rawValue, app.scrollDistance)
            XCTAssertEqual(profile.scroll.sessions.rawValue, Double(app.scrollSessions))
            XCTAssertEqual(profile.keyboard.cohortSize, 2)
            XCTAssertEqual(profile.keyboard.score, 0.25)
            let snapshot = AppDetailPresentation(app: app, profiles: [profile],
                                                 rangeTitle: String(describing: range))
            XCTAssertEqual(snapshot.rangeTitle, String(describing: range))
            XCTAssertEqual(snapshot.cards[0].score, 0.25)
            XCTAssertEqual(context.defaults.dictionaryRepresentation() as NSDictionary, defaultsBefore)
            let detail = AppKeyBreakdown(appStats: app)
            XCTAssertEqual(detail.totalKeyPresses, total)
            XCTAssertEqual(detail.namedKeyPresses, named)
            XCTAssertEqual(detail.coverage, coverage)
            XCTAssertFalse(detail.entries.contains { $0.key == "Z" })
        }
        let all = try XCTUnwrap(manager.appStatsSummary(range: .all)
            .first { $0.bundleId == "selected.app" })
        XCTAssertEqual(AppKeyBreakdown(appStats: all).entries, [
            .init(key: "Cmd+C", count: 5), .init(key: "Return", count: 4)
        ])
    }

    private func makeContext(timeZone: TimeZone = .current) throws -> StatsManagerTestContext {
        let suiteName = "keystats-stats-manager-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 31,
            hour: 12
        )))

        return StatsManagerTestContext(
            suiteName: suiteName,
            defaults: defaults,
            calendar: calendar,
            clock: MutableTestClock(now: now)
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func makeStats(on date: Date, keyPresses: Int = 0) -> DailyStats {
        var stats = DailyStats(date: date)
        stats.date = date
        stats.keyPresses = keyPresses
        return stats
    }

    private func seed(
        defaults: UserDefaults,
        current: DailyStats,
        history: [String: DailyStats]
    ) throws {
        defaults.set(try JSONEncoder().encode(current), forKey: statsKey)
        defaults.set(try JSONEncoder().encode(history), forKey: historyKey)
    }

    private func importData(current: DailyStats, history: [String: DailyStats]) throws -> Data {
        let payload = StatsImportPayload(
            version: 1,
            scope: "currentDevice",
            exportedAt: current.date,
            currentStats: current,
            history: history
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private func decodePersistedCurrent(from defaults: UserDefaults) throws -> DailyStats {
        let data = try XCTUnwrap(defaults.data(forKey: statsKey))
        return try JSONDecoder().decode(DailyStats.self, from: data)
    }

    private func decodePersistedHistory(from defaults: UserDefaults) throws -> [String: DailyStats] {
        let data = try XCTUnwrap(defaults.data(forKey: historyKey))
        return try JSONDecoder().decode([String: DailyStats].self, from: data)
    }
}
