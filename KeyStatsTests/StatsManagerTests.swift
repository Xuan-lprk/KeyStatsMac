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

    private func makeContext() throws -> StatsManagerTestContext {
        let suiteName = "keystats-stats-manager-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
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
