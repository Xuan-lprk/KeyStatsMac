import Cocoa
import XCTest
@testable import KeyStatsCore

private final class PlaybackTestScheduler {
    final class Entry {
        let action: () -> Void
        var cancelled = false
        init(_ action: @escaping () -> Void) { self.action = action }
    }
    var entries: [Entry] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
        XCTAssertEqual(delay, 0.15)
        let entry = Entry(action)
        entries.append(entry)
        return { entry.cancelled = true }
    }
}

final class GrowthKeyboardTests: XCTestCase {
    private var suites: [String] = []
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f
    }
    private func date(_ key: String) -> Date { formatter.date(from: key)! }
    private func day(_ key: String, total: Int, counts: [String: Int] = [:]) -> DailyStats {
        var value = DailyStats(date: date(key))
        value.date = date(key); value.keyPresses = total; value.keyPressCounts = counts
        return value
    }
    private func model(_ history: [String: DailyStats], today: String = "2026-10-05") throws -> GrowthKeyboardPresentation {
        let period = try XCTUnwrap(KeyboardTrackingPeriod(history: history, calendar: calendar, dateKeyFormatter: formatter))
        return try XCTUnwrap(GrowthKeyboardPresentation(timeline: CumulativeKeyboardTimeline.build(history: history),
            period: period, now: date(today), calendar: calendar))
    }
    private func manager(history: [String: DailyStats], current: DailyStats,
                         remote: [CoreDaySnapshotV1] = []) throws -> (StatsManager, UserDefaults) {
        let suite = "KeyStatsTests.Growth." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(try JSONEncoder().encode(current), forKey: "dailyStats")
        defaults.set(try JSONEncoder().encode(history), forKey: "dailyStatsHistory")
        let now = date("2026-10-05"), cal = calendar, fmt = formatter
        let manager = StatsManager(environment: .init(userDefaults: defaults, now: { now }, calendar: { cal },
            makeDateKeyFormatter: { fmt.copy() as! DateFormatter }, notificationCenter: NotificationCenter(),
            schedulesAutomaticWork: false, blocksLegacyImport: { false },
            syncDisplayContext: { remote.isEmpty ? nil : .init(deviceId: "local", remoteSnapshots: remote) },
            sendThresholdNotification: { _, _, _ in }))
        return (manager, defaults)
    }
    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    func testProductionAdapterIncludesUnsavedTodayWithoutWritingDefaults() throws {
        let (manager, defaults) = try manager(history: ["2026-10-03": day("2026-10-03", total: 4, counts: ["B": 4])],
                                            current: day("2026-10-05", total: 2, counts: ["A": 2]))
        manager.incrementKeyPresses(keyName: "A")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let presentation = try XCTUnwrap(GrowthKeyboardPresentation.load(from: manager, now: date("2026-10-05"), calendar: calendar))
        let frame = presentation.frame(at: presentation.dayCount - 1)
        XCTAssertEqual(frame.snapshot.totalKeyPresses, 7)
        XCTAssertEqual(frame.snapshot.keyPressCounts, ["A": 3, "B": 4])
        XCTAssertEqual(frame.dayIndex, 3)
        XCTAssertEqual(frame.snapshot, manager.cumulativeKeyboardSnapshot(asOf: date("2026-10-05")))
        XCTAssertEqual(try JSONDecoder().decode(DailyStats.self, from: XCTUnwrap(defaults.data(forKey: "dailyStats"))).keyPresses, 2)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    func testProductionAdapterUsesDisplaySyncAndExcludesCurrentDeviceDuplicate() throws {
        let remote = [
            CoreDaySnapshotV1(deviceId: "local", localDay: "2026-10-05", revision: 1,
                keyPresses: 100, keyPressCounts: ["Z": 100], clicks: .zero),
            CoreDaySnapshotV1(deviceId: "other", localDay: "2026-10-02", revision: 1,
                keyPresses: 7, keyPressCounts: ["B": 7], clicks: .zero),
            CoreDaySnapshotV1(deviceId: "other", localDay: "2026-10-05", revision: 1,
                keyPresses: 3, keyPressCounts: ["Cmd++": 3], clicks: .zero)
        ]
        let (manager, defaults) = try manager(history: [:],
            current: day("2026-10-05", total: 2, counts: ["LeftCmd+C": 2]), remote: remote)
        manager.incrementKeyPresses(keyName: "A")
        let before = defaults.dictionaryRepresentation() as NSDictionary
        let p = try XCTUnwrap(GrowthKeyboardPresentation.load(from: manager, now: date("2026-10-05"), calendar: calendar))
        XCTAssertEqual(p.period.firstTrackedDayKey, "2026-10-02")
        XCTAssertEqual(p.dayCount, 4)
        let frame = p.frame(at: 3)
        XCTAssertEqual(frame.snapshot.totalKeyPresses, 13)
        XCTAssertNil(frame.snapshot.keyPressCounts["Z"])
        XCTAssertEqual(frame.physical.counts["="], 3)
        XCTAssertEqual(frame.physical.counts["LeftCmd"], 2)
        XCTAssertEqual(frame.physical.counts["Cmd"], 3)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    }

    func testSnapshotCacheRemainsStableUntilExplicitFormalRefresh() throws {
        let (manager, _) = try manager(history: [:], current: day("2026-10-05", total: 1, counts: ["A": 1]))
        let old = try XCTUnwrap(GrowthKeyboardPresentation.load(from: manager, now: date("2026-10-05"), calendar: calendar))
        manager.incrementKeyPresses(keyName: "A")
        XCTAssertEqual(old.frame(at: 0).snapshot.totalKeyPresses, 1)
        let refreshed = try XCTUnwrap(GrowthKeyboardPresentation.load(from: manager, now: date("2026-10-05"), calendar: calendar))
        XCTAssertEqual(refreshed.frame(at: 0).snapshot.totalKeyPresses, 2)
    }

    func testHistoricalSelectionAndMissingCalendarDates() throws {
        let p = try model(["2026-10-01": day("2026-10-01", total: 10, counts: ["A": 10]),
                           "2026-10-03": day("2026-10-03", total: 7, counts: ["B": 7])])
        XCTAssertEqual(p.dayCount, 5)
        XCTAssertEqual((0..<5).map { p.frame(at: $0).dayIndex }, [1, 2, 3, 4, 5])
        XCTAssertEqual((0..<5).map { p.frame(at: $0).snapshot.totalKeyPresses }, [10, 10, 17, 17, 17])
        XCTAssertEqual(p.frame(at: 1).dayKey, "2026-10-02")
        XCTAssertEqual(p.frame(at: 1).snapshot.dayKey, "2026-10-01")
        XCTAssertEqual(p.frame(at: 0).snapshot.keyPressCounts, ["A": 10])
        XCTAssertEqual(p.frame(at: 2).snapshot.keyPressCounts, ["A": 10, "B": 7])
    }

    func testDateAndPreviousNextBoundsClampWithoutInventingRecords() throws {
        let p = try model(["2026-10-01": day("2026-10-01", total: 1)])
        XCTAssertEqual(p.frame(at: -1).dayIndex, 1)
        XCTAssertEqual(p.frame(at: Int.max).dayIndex, 5)
        XCTAssertEqual(p.offset(for: date("2026-09-01")), 0)
        XCTAssertEqual(p.offset(for: date("2026-11-01")), 4)
        XCTAssertEqual(p.snapshots.count, 1)
    }

    func testLegacyPartialDetailsRetainAuthoritativeTotals() throws {
        let p = try model(["2026-09-30": day("2026-09-30", total: 0),
                           "2026-10-01": day("2026-10-01", total: 10),
                           "2026-10-03": day("2026-10-03", total: 3, counts: ["A": 2])])
        XCTAssertEqual(p.period.firstTrackedDayKey, "2026-10-01")
        XCTAssertTrue(p.frame(at: 0).hasPartialDetails)
        XCTAssertEqual(p.frame(at: 0).snapshot.totalKeyPresses, 10)
        XCTAssertTrue(p.frame(at: 0).physical.counts.isEmpty)
        XCTAssertEqual(p.frame(at: 4).snapshot.totalKeyPresses, 13)
        XCTAssertEqual(p.frame(at: 4).snapshot.detailedKeyPresses, 2)
        XCTAssertTrue(p.frame(at: 4).hasPartialDetails)
    }

    func testPhysicalMappingAndStableProgressAreTheActualRendererInputs() throws {
        let p = try model(["2026-10-01": day("2026-10-01", total: 10_000,
            counts: ["+": 5_000, "Cmd++": 5_000, "BrightnessUp": 2])])
        let frame = p.frame(at: 0)
        let equal = try XCTUnwrap(frame.keyUsages.first { $0.id == "=" })
        XCTAssertEqual(equal.count, 10_000)
        XCTAssertEqual(equal.progress, 0.5)
        XCTAssertEqual(frame.physical.unsupported, ["BrightnessUp": 2])
        XCTAssertNil(frame.keyUsages.first { $0.id == "BrightnessUp" })
        XCTAssertEqual(frame.keyUsages.first { $0.id == "LeftCmd" }?.count, 5_000)
    }

    func testDayIndexAcrossDSTUsesCalendarDays() throws {
        var cal = calendar; cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "yyyy-MM-dd"
        var first = day("2026-03-07", total: 1)
        first.date = try XCTUnwrap(f.date(from: "2026-03-07"))
        let history = ["2026-03-07": first]
        let period = try XCTUnwrap(KeyboardTrackingPeriod(history: history, calendar: cal, dateKeyFormatter: f))
        let p = try XCTUnwrap(GrowthKeyboardPresentation(timeline: CumulativeKeyboardTimeline.build(history: history),
            period: period, now: try XCTUnwrap(f.date(from: "2026-03-09")), calendar: cal))
        XCTAssertEqual(p.dayCount, 3)
        XCTAssertEqual(p.date(at: 2).timeIntervalSince(p.date(at: 0)) / 3600, 47)
        XCTAssertEqual(p.frame(at: 2).dayIndex, 3)
    }

    func testEmptyFormalKeyboardHistoryReturnsNoPresentation() throws {
        let (manager, _) = try manager(history: [:], current: day("2026-10-05", total: 0))
        XCTAssertNil(GrowthKeyboardPresentation.load(from: manager, now: date("2026-10-05"), calendar: calendar))
    }

    func testPlaybackRunsDayOneToTodayAndDoesNotLoop() {
        let scheduler = PlaybackTestScheduler()
        let driver = GrowthPlaybackDriver(schedule: scheduler.schedule)
        var observed: [Int] = []
        driver.onChange = { observed.append($0) }
        driver.reset(dayCount: 3); observed = []
        driver.setActive(true); driver.start()
        XCTAssertEqual(observed, [0])
        scheduler.entries[0].action()
        scheduler.entries[1].action()
        XCTAssertEqual(observed, [0, 1, 2])
        XCTAssertFalse(driver.state.isPlaying)
        XCTAssertFalse(driver.hasScheduledStep)
        XCTAssertEqual(scheduler.entries.count, 2)
    }

    func testHiddenCloseAndPauseCancelPendingWorkAndRejectStaleCallbacks() {
        let scheduler = PlaybackTestScheduler()
        let driver = GrowthPlaybackDriver(schedule: scheduler.schedule)
        driver.reset(dayCount: 3); driver.setActive(true); driver.start()
        let old = scheduler.entries[0]
        driver.setActive(false)
        XCTAssertTrue(old.cancelled); XCTAssertFalse(driver.hasScheduledStep)
        old.action() // Simulate cancellation racing an already dequeued callback.
        XCTAssertEqual(driver.state.offset, 0)
        driver.setActive(true); driver.start()
        old.action()
        XCTAssertEqual(driver.state.offset, 0)
        scheduler.entries[1].action()
        XCTAssertEqual(driver.state.offset, 1)
        driver.pause()
        XCTAssertTrue(scheduler.entries[2].cancelled)
        scheduler.entries[2].action()
        XCTAssertEqual(driver.state.offset, 1)
        XCTAssertFalse(driver.hasScheduledStep)
    }

    func testInactiveAndSingleDayPlaybackDoNotSchedule() {
        let scheduler = PlaybackTestScheduler()
        let driver = GrowthPlaybackDriver(schedule: scheduler.schedule)
        driver.reset(dayCount: 3); driver.start()
        XCTAssertTrue(scheduler.entries.isEmpty)
        driver.reset(dayCount: 1); driver.setActive(true); driver.start()
        XCTAssertTrue(scheduler.entries.isEmpty)
        XCTAssertFalse(driver.state.isPlaying)
    }

    func testManualSelectionStopsPlaybackAndClamps() {
        let scheduler = PlaybackTestScheduler()
        let driver = GrowthPlaybackDriver(schedule: scheduler.schedule)
        driver.reset(dayCount: 3); driver.setActive(true); driver.start()
        driver.select(99)
        XCTAssertEqual(driver.state.offset, 2); XCTAssertFalse(driver.state.isPlaying)
        XCTAssertTrue(scheduler.entries[0].cancelled)
        driver.select(-1)
        XCTAssertEqual(driver.state.offset, 0)
        XCTAssertFalse(driver.hasScheduledStep)
    }

    func testDriverDeinitCancelsAndDoesNotRetainController() {
        let scheduler = PlaybackTestScheduler()
        var driver: GrowthPlaybackDriver? = GrowthPlaybackDriver(schedule: scheduler.schedule)
        weak var weakDriver = driver
        driver?.reset(dayCount: 3); driver?.setActive(true); driver?.start()
        driver = nil
        XCTAssertNil(weakDriver)
        XCTAssertTrue(scheduler.entries[0].cancelled)
        scheduler.entries[0].action()
    }

    func testRendererKeepsStaticPathsAndLayersAcrossDatesAndResize() throws {
        _ = NSApplication.shared
        let renderer = EditorialKeyboardRenderer(frame: NSRect(x: 0, y: 0, width: 1112, height: 470))
        renderer.layoutSubtreeIfNeeded()
        let p = try model(["2026-10-01": day("2026-10-01", total: 1, counts: ["A": 1]),
                           "2026-10-03": day("2026-10-03", total: 10_000, counts: ["A": 10_000])])
        let paths = renderer.staticGeometryPaths
        let builds = renderer.geometryBuildCount
        XCTAssertEqual(renderer.keyIDs, KeyboardLayout.macStyle.keys.map(\.id))
        XCTAssertEqual(renderer.keyIDs.count, 77)
        for offset in [0, 1, 2, 4] {
            let values = p.frame(at: offset).keyUsages
            renderer.apply(values)
            let updates = renderer.dataUpdateCount
            renderer.apply(values)
            XCTAssertEqual(renderer.dataUpdateCount, updates)
            XCTAssertTrue(zip(paths, renderer.staticGeometryPaths).allSatisfy { $0 === $1 })
        }
        renderer.frame.size = NSSize(width: 960, height: 420)
        renderer.needsLayout = true
        renderer.layoutSubtreeIfNeeded()
        XCTAssertEqual(renderer.geometryBuildCount, builds)
        XCTAssertTrue(zip(paths, renderer.staticGeometryPaths).allSatisfy { $0 === $1 })
    }

    func testSharedCanvasUnifiesWindowAndPageAndRestoresHeatmapBackground() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let canvas = KeyboardVisualizationCanvasView(frame: window.contentView!.bounds)
        window.contentView = canvas
        let expected = NSColor(srgbRed: 242.0 / 255, green: 242.0 / 255, blue: 238.0 / 255, alpha: 1)
        XCTAssertEqual(canvas.layer?.backgroundColor, expected.cgColor)
        XCTAssertEqual(window.backgroundColor.cgColor, expected.cgColor)
        canvas.showsGrowth = false
        let heatmap = KeyboardVisualizationCanvasView.backgroundColor(for: window.effectiveAppearance, showsGrowth: false)
        XCTAssertEqual(canvas.layer?.backgroundColor, heatmap.cgColor)
        XCTAssertEqual(window.backgroundColor.cgColor, heatmap.cgColor)
        // A loaded but hidden Growth page must not override the outer page's choice.
        let growthPage = KeyboardVisualizationCanvasView(frame: .zero)
        canvas.addSubview(growthPage)
        growthPage.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(window.backgroundColor.cgColor, heatmap.cgColor)
        canvas.showsGrowth = true
        XCTAssertEqual(canvas.layer?.backgroundColor, expected.cgColor)
        XCTAssertEqual(window.backgroundColor.cgColor, expected.cgColor)
    }

    func testSharedCanvasResolvesDarkAppearanceWithoutForcingLightMode() throws {
        _ = NSApplication.shared
        let canvas = KeyboardVisualizationCanvasView(frame: .zero)
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        canvas.appearance = dark
        canvas.viewDidChangeEffectiveAppearance()
        let expected = KeyboardVisualizationCanvasView.backgroundColor(for: dark, showsGrowth: false)
        XCTAssertEqual(canvas.layer?.backgroundColor, expected.cgColor)
        XCTAssertEqual(canvas.appearance?.name, .darkAqua)
    }

    func testRendererCanvasUsesTheWindowBackground() {
        _ = NSApplication.shared
        let renderer = EditorialKeyboardRenderer(frame: NSRect(x: 24, y: 140, width: 1112, height: 470))
        XCTAssertEqual(renderer.layer?.backgroundColor?.alpha ?? 0, 0)
    }

    func testRendererLayoutPreservesAppKitManagedBackingFrame() throws {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1160, height: 736))
        host.wantsLayer = true
        let renderer = EditorialKeyboardRenderer(frame: NSRect(x: 24, y: 140, width: 1112, height: 470))
        host.addSubview(renderer)
        let backing = try XCTUnwrap(renderer.layer)
        let managedFrame = backing.frame
        XCTAssertNotEqual(managedFrame.origin, .zero)
        renderer.needsLayout = true
        renderer.layoutSubtreeIfNeeded()
        XCTAssertEqual(backing.frame, managedFrame)
    }

    func testSelectedExactCountUpdatesWithoutHover() {
        _ = NSApplication.shared
        let renderer = EditorialKeyboardRenderer(frame: .zero)
        var selected: GrowthKeyboardKeyUsage?
        renderer.onSelectionChanged = { selected = $0 }
        renderer.apply([.init(id: "A", count: 6_521)])
        renderer.selectKey("A")
        XCTAssertEqual(selected?.count, 6_521)
        renderer.apply([.init(id: "A", count: 10_000)])
        XCTAssertEqual(selected?.count, 10_000)
        XCTAssertEqual(selected?.progress, 0.5)
        renderer.selectKey(nil)
        XCTAssertNil(selected)
    }
}
