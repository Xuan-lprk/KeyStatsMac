import Cocoa
import XCTest
@testable import KeyStatsCore

private final class StaticRenderScheduler {
    var actions: [() -> Void] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
        XCTAssertEqual(delay, 0.08)
        actions.append(action)
        // Deliberately keep cancelled work executable to test the generation guard.
        return {}
    }
    func fireAll() { let pending = actions; actions = []; pending.forEach { $0() } }
}

final class GrowthKeyboard3DTests: XCTestCase {
    func test3DReplayWaitsForEachRenderedDayReusesGapsAndStopsAtToday() throws {
        for mechanical in [false, true] {
            let layout = layout(), renderScheduler = StaticRenderScheduler()
            let model: MechanicalKeyboardScene?
            if mechanical {
                model = try MechanicalKeyboardScene()
                try model!.configureFullModel()
            } else { model = nil }
            let imageSize = mechanical ? MechanicalKeyboardScene.size : GrowthKeyboard3DScene.size
            var steps: [() -> Void] = []
            let driver = GrowthPlaybackDriver(schedule: { delay, action in
                XCTAssertEqual(delay, 0.35); steps.append(action); return {}
            })
            driver.waitsForPresentation = true; driver.stepInterval = 0.35
            driver.reset(dayCount: 4)
            let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { values, _ in
                if let model {
                    model.applyGrowth(values)
                    let usage = values.first { $0.id == "A" }!
                    XCTAssertEqual(model.growthHeights.count, 77)
                    XCTAssertEqual(model.growthHeights["A"], MechanicalKeyboardScene.growthHeight(usage.progress))
                    let node = model.fullModelNodes.first { $0.name == "A" }!
                    XCTAssertEqual(node.geometry?.firstMaterial?.diffuse.contents as? NSColor,
                                   model.baseline.usageColor(usage.progress))
                }
                return GrowthKeyboard3DFrame(image: NSImage(size: imageSize),
                    rects: Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.id, $0.rect) }))
            }, imageSize: imageSize, bakesLegends: mechanical, schedule: renderScheduler.schedule)
            var observed: [Int] = []
            var displayed: [Int] = []
            let counts = [1, 1, 20, 100]
            driver.onChange = { offset in
                observed.append(offset)
                let token = driver.presentationGeneration
                view.apply([.init(id: "A", count: counts[offset])], animated: driver.isPresentingPlaybackFrame) {
                    displayed.append(offset)
                    driver.framePresented(at: offset, generation: token)
                }
            }
            view.setActive(true); driver.setActive(true); driver.start()
            XCTAssertEqual(observed, [0])
            XCTAssertTrue(steps.isEmpty) // A cold render cannot be skipped by a calendar timer.
            renderScheduler.fireAll()
            XCTAssertEqual(displayed, [0]); XCTAssertEqual(steps.count, 1)
            steps[0]() // A missing date holds identical cumulative values.
            XCTAssertEqual(displayed, [0, 1]); XCTAssertEqual(view.renderCount, 1)
            XCTAssertEqual(steps.count, 2)
            steps[1]()
            XCTAssertEqual(observed, [0, 1, 2]); XCTAssertEqual(displayed, [0, 1])
            XCTAssertNotNil(view.displayedFrame) // Keep the previous image during replay rendering.
            XCTAssertEqual(steps.count, 2)
            renderScheduler.fireAll()
            XCTAssertEqual(displayed, [0, 1, 2]); XCTAssertEqual(steps.count, 3)
            steps[2](); renderScheduler.fireAll()
            XCTAssertEqual(displayed, [0, 1, 2, 3])
            XCTAssertEqual(view.renderCount, 3)
            XCTAssertEqual(view.cachedFrameCount, 3)
            XCTAssertFalse(driver.state.isPlaying)
            XCTAssertFalse(driver.hasScheduledStep)
            XCTAssertEqual(steps.count, 3)
        }
    }

    func test3DReplayRejectsDuplicateAndStalePresentationAcknowledgements() {
        var steps: [() -> Void] = []
        let driver = GrowthPlaybackDriver(schedule: { _, action in steps.append(action); return {} })
        driver.waitsForPresentation = true; driver.reset(dayCount: 3); driver.setActive(true); driver.start()
        let old = driver.presentationGeneration
        driver.framePresented(at: 1, generation: old)
        XCTAssertTrue(steps.isEmpty)
        driver.pause()
        driver.framePresented(at: 0, generation: old)
        XCTAssertTrue(steps.isEmpty)
        driver.start()
        driver.framePresented(at: 0, generation: old)
        XCTAssertTrue(steps.isEmpty)
        let current = driver.presentationGeneration
        driver.framePresented(at: 0, generation: current)
        driver.framePresented(at: 0, generation: current)
        XCTAssertEqual(steps.count, 1)
        driver.setActive(false); steps[0]()
        XCTAssertEqual(driver.state.offset, 0)
        XCTAssertFalse(driver.state.isPlaying)
    }

    func testReturningToDisplayedDateCancelsPendingReplayFrame() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { _, _ in self.fakeFrame(layout) }, schedule: scheduler.schedule)
        view.setActive(true)
        view.apply([.init(id: "A", count: 1)]); scheduler.fireAll()
        var presented: [Int] = []
        view.apply([.init(id: "A", count: 2)], animated: true) { presented.append(2) }
        view.apply([.init(id: "A", count: 1)], animated: true) { presented.append(1) }
        scheduler.fireAll()
        XCTAssertEqual(presented, [1])
        XCTAssertEqual(view.renderCount, 1)
    }

    func testReplayCountsStayWithDisplayedImageUntilNextFrameIsReady() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { _, _ in self.fakeFrame(layout) }, schedule: scheduler.schedule)
        view.setActive(true)
        view.apply([.init(id: "A", count: 1)]); scheduler.fireAll()
        var selected: GrowthKeyboardKeyUsage?
        view.onSelectionChanged = { selected = $0 }; view.selectKey("A")
        view.apply([.init(id: "A", count: 2)], animated: true)
        XCTAssertEqual(selected?.count, 1)
        scheduler.fireAll()
        XCTAssertEqual(selected?.count, 2)
        XCTAssertEqual(view.renderCount, 2)
    }

    func testProductionPageSwitchesModesKeepsDateSelectionAndEnables3DReplay() throws {
        let calendar = Calendar.current
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.date(from: "2026-10-01")!, now = formatter.date(from: "2026-10-03")!
        let suite = "KeyStatsTests.3DPage." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var past = DailyStats(date: first); past.keyPresses = 3; past.keyPressCounts = ["A": 3]
        var today = DailyStats(date: now); today.keyPresses = 7; today.keyPressCounts = ["A": 7]
        defaults.set(try JSONEncoder().encode(["2026-10-01": past]), forKey: "dailyStatsHistory")
        defaults.set(try JSONEncoder().encode(today), forKey: "dailyStats")
        let manager = StatsManager(environment: .init(userDefaults: defaults, now: { now }, calendar: { calendar },
            makeDateKeyFormatter: { formatter.copy() as! DateFormatter }, notificationCenter: NotificationCenter(),
            schedulesAutomaticWork: false, blocksLegacyImport: { false }, syncDisplayContext: { nil },
            sendThresholdNotification: { _, _, _ in }))
        let page = GrowthKeyboardViewController(manager: manager)
        page.refreshData(resetToToday: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let views = descendants(page.view)
        let selector = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }.first)
        let play = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("togglePlayback") })
        XCTAssertEqual(selector.selectedSegment, 0)
        XCTAssertTrue(play.isEnabled)
        selector.selectedSegment = 1
        page.perform(selector.action!)
        XCTAssertTrue(play.isEnabled)
        let spatial = try XCTUnwrap(descendants(page.view).compactMap { $0 as? GrowthKeyboard3DRenderer }.first)
        XCTAssertFalse(spatial.hasScheduledRender) // No window: mode/date changes must not start SceneKit.
        var selected: GrowthKeyboardKeyUsage?
        spatial.onSelectionChanged = { selected = $0 }
        spatial.selectKey("A")
        // The production load uses today's actual date. Select this fixture's history explicitly.
        let picker = try XCTUnwrap(views.compactMap { $0 as? NSDatePicker }.first)
        picker.dateValue = first; page.perform(picker.action!)
        XCTAssertEqual(selected?.count, 3)
        picker.dateValue = now; page.perform(picker.action!)
        XCTAssertEqual(selected?.count, 10)
        selector.selectedSegment = 0; page.perform(selector.action!)
        XCTAssertTrue(play.isEnabled)
        XCTAssertTrue(spatial.isHidden)
        XCTAssertFalse(spatial.isActive)
        XCTAssertEqual(spatial.renderCount, 0)
        page.setMechanical(true)
        XCTAssertTrue(page.usesMechanical)
        XCTAssertTrue(play.isEnabled)
        let mechanical = try XCTUnwrap(descendants(page.view).compactMap { $0 as? GrowthKeyboard3DRenderer }.first)
        var mechanicalSelection: GrowthKeyboardKeyUsage?
        mechanical.onSelectionChanged = { mechanicalSelection = $0 }
        mechanical.selectKey("A")
        XCTAssertEqual(mechanicalSelection?.count, 10)
        picker.dateValue = first; page.perform(picker.action!)
        XCTAssertEqual(mechanicalSelection?.count, 3)
        XCTAssertFalse(mechanical.hasScheduledRender)
        page.setMechanical(false)
        XCTAssertFalse(page.usesMechanical)
        XCTAssertTrue(play.isEnabled)
    }

    func testMechanicalGrowthHeightIsFixedBoundedAndMonotonic() {
        var previous: CGFloat = 0
        for index in 0...1000 {
            let height = MechanicalKeyboardScene.growthHeight(Double(index) / 1000)
            XCTAssertGreaterThanOrEqual(height, previous)
            XCTAssertGreaterThanOrEqual(height, 0.35)
            XCTAssertLessThanOrEqual(height, 0.75)
            previous = height
        }
        XCTAssertEqual(MechanicalKeyboardScene.growthHeight(-1), 0.35)
        XCTAssertEqual(MechanicalKeyboardScene.growthHeight(2), 0.75)
    }

    func testMechanicalGrowthUsesFormalPaletteAndReusesUnchangedGeometry() throws {
        let model = try MechanicalKeyboardScene()
        try model.configureFullModel()
        let values = [GrowthKeyboardKeyUsage(id: "A", count: 10_000), .init(id: "Space", count: 1_000_000)]
        model.applyGrowth(values)
        let nodes = Dictionary(uniqueKeysWithValues: model.fullModelNodes.map { ($0.name!, $0) })
        let identities = model.fullModelNodes.map { ObjectIdentifier($0.geometry!) }
        XCTAssertEqual(model.growthHeights.count, 77)
        for value in values {
            XCTAssertEqual(model.growthHeights[value.id], MechanicalKeyboardScene.growthHeight(value.progress))
            let color = try XCTUnwrap(nodes[value.id]?.geometry?.firstMaterial?.diffuse.contents as? NSColor)
            XCTAssertEqual(color, model.baseline.usageColor(value.progress))
        }
        XCTAssertEqual(model.growthHeights["F1"], 0.35)
        model.applyGrowth(values + [.init(id: "S", count: 900_000)])
        XCTAssertEqual(ObjectIdentifier(nodes["A"]!.geometry!), identities[model.keys.firstIndex { $0.id == "A" }!])
        XCTAssertEqual(model.growthHeights["A"], MechanicalKeyboardScene.growthHeight(0.5))
        let updated = model.fullModelNodes.map { ObjectIdentifier($0.geometry!) }
        model.applyGrowth(values + [.init(id: "S", count: 900_000)])
        XCTAssertEqual(model.fullModelNodes.map { ObjectIdentifier($0.geometry!) }, updated)
    }

    private func layout() -> EditorialKeyboardSceneLayout {
        EditorialKeyboardRenderer(frame: .zero).sceneLayout
    }
    private func fakeFrame(_ layout: EditorialKeyboardSceneLayout) -> GrowthKeyboard3DFrame {
        GrowthKeyboard3DFrame(image: NSImage(size: GrowthKeyboard3DScene.size),
            rects: Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.id, $0.rect) }))
    }
    private func assertSameRect(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1e-9, file: file, line: line)
    }

    func testGeometryV2RemainsBoundedMonotonicAndSeparateFromStatisticalProgress() {
        var previous: CGFloat = 0
        for index in 0...1000 {
            let p = Double(index) / 1000
            let formation = -expm1(-pow(p / 0.32, 1.6)) / -expm1(-pow(1 / 0.32, 1.6))
            let height = GrowthKeyboard3DGeometry.height(p)
            XCTAssertEqual(height, 0.012 + (0.476 - 0.012) * formation, accuracy: 1e-12)
            XCTAssertGreaterThanOrEqual(height, previous)
            XCTAssertLessThanOrEqual(height, 0.476)
            XCTAssertLessThan(GrowthKeyboard3DGeometry.bevel(p), height / 2)
            previous = height
        }
        XCTAssertEqual(GrowthKeyboard3DGeometry.height(0), 0.012)
        XCTAssertEqual(GrowthKeyboard3DGeometry.height(1), 0.476, accuracy: 1e-12)
        XCTAssertGreaterThan(GrowthKeyboard3DGeometry.formation(0.5), 0.85)
        XCTAssertEqual(GrowthKeyboardKeyUsage(id: "A", count: 10_000).progress, 0.5, accuracy: 1e-12)
    }

    func testExplicitSceneInterfaceMatchesApproved77KeyPrototypeInputsWithoutLayerIndexBridge() throws {
        let reference = EditorialKeyboardRenderer(frame: .zero)
        let layout = reference.sceneLayout
        XCTAssertEqual(layout.keys.map(\.id), KeyboardLayout.macStyle.keys.map(\.id))
        XCTAssertEqual(layout.keys.count, 77)
        let board = try XCTUnwrap(reference.layer?.sublayers?.first)
        XCTAssertEqual(layout.boardSize, board.bounds.size)
        for key in layout.keys {
            let cap = try XCTUnwrap(board.sublayers?.first { $0.name == key.id })
            let shapes = try XCTUnwrap(cap.sublayers).compactMap { $0 as? CAShapeLayer }
            let legend = try XCTUnwrap(cap.sublayers?.compactMap { $0 as? CATextLayer }.first)
            XCTAssertEqual(key.rect, cap.frame)
            XCTAssertEqual(key.size, cap.bounds.size)
            XCTAssertTrue(key.topPath === shapes[2].path)
            XCTAssertEqual(key.legend, legend.string as? NSAttributedString)
            assertSameRect(key.legendFrame, legend.frame)
            XCTAssertEqual(key.legendAlignment, legend.alignmentMode)
        }
        let rest = layout.keys.first { $0.id == "A" }!.legendFrame
        reference.selectKey("A")
        assertSameRect(reference.sceneLayout.keys.first { $0.id == "A" }!.legendFrame, rest)
    }

    func testHiddenViewNeverRendersAndCancelledDatesCannotRenderAfterHide() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        var calls = 0
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { _, _ in
            calls += 1; return self.fakeFrame(layout)
        }, schedule: scheduler.schedule)
        view.apply([.init(id: "A", count: 1)])
        XCTAssertFalse(view.hasScheduledRender)
        view.setActive(true)
        XCTAssertTrue(view.hasScheduledRender)
        view.setActive(false)
        scheduler.fireAll()
        XCTAssertEqual(calls, 0)
        view.apply([.init(id: "A", count: 2)])
        scheduler.fireAll()
        XCTAssertEqual(calls, 0)
        view.setActive(true); scheduler.fireAll()
        XCTAssertEqual(calls, 1)
    }

    func testReactivationPresentsLatestPendingSnapshotWithoutAcknowledgingWhileHidden() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        var rendered: [Int] = [], presented: [Int] = []
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { values, _ in
            rendered.append(values.first { $0.id == "A" }!.count)
            return self.fakeFrame(layout)
        }, schedule: scheduler.schedule)
        view.setActive(true)
        view.apply([.init(id: "A", count: 1)]) { presented.append(1) }
        view.setActive(false)
        scheduler.fireAll()
        XCTAssertTrue(rendered.isEmpty)
        XCTAssertTrue(presented.isEmpty)

        view.setActive(true)
        scheduler.fireAll()
        XCTAssertEqual(rendered, [1])
        XCTAssertEqual(presented, [1])

        view.apply([.init(id: "A", count: 2)]) { presented.append(2) }
        view.setActive(false)
        view.apply([.init(id: "A", count: 3)]) { presented.append(3) }
        view.setActive(false)
        scheduler.fireAll()
        XCTAssertEqual(presented, [1])
        view.setActive(true)
        scheduler.fireAll()
        view.setActive(true)
        XCTAssertEqual(rendered, [1, 3])
        XCTAssertEqual(presented, [1, 3])
    }

    func testDateChangesCoalesceAndThreeFrameCacheIncludesCountsAndAppearance() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        var renderedCounts: [Int] = []
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { values, _ in
            renderedCounts.append(values.first { $0.id == "A" }!.count)
            return self.fakeFrame(layout)
        }, schedule: scheduler.schedule)
        view.appearance = NSAppearance(named: .aqua)
        view.setActive(true)
        view.apply([.init(id: "A", count: 1)])
        view.apply([.init(id: "A", count: 2)])
        view.apply([.init(id: "A", count: 3)])
        scheduler.fireAll()
        XCTAssertEqual(renderedCounts, [3])
        for count in [1, 2] { view.apply([.init(id: "A", count: count)]); scheduler.fireAll() }
        XCTAssertEqual(view.cachedFrameCount, 3)
        view.apply([.init(id: "A", count: 3)]); scheduler.fireAll()
        XCTAssertEqual(renderedCounts, [3, 1, 2])
        view.apply([.init(id: "A", count: 4)]); scheduler.fireAll()
        XCTAssertEqual(view.cachedFrameCount, 3)
        view.apply([.init(id: "A", count: 1)]); scheduler.fireAll()
        XCTAssertEqual(renderedCounts, [3, 1, 2, 4, 1])
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance(); scheduler.fireAll()
        XCTAssertEqual(renderedCounts.count, 6)
        XCTAssertEqual(view.cachedFrameCount, 3)
    }

    func testKeySelectionShowsExactCountsAcrossDatesWithoutSceneRender() {
        let layout = layout(), scheduler = StaticRenderScheduler()
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { _, _ in self.fakeFrame(layout) }, schedule: scheduler.schedule)
        var selection: GrowthKeyboardKeyUsage?
        view.onSelectionChanged = { selection = $0 }
        view.apply([.init(id: "A", count: 73)])
        view.setActive(true); scheduler.fireAll()
        view.selectKey("A")
        XCTAssertEqual(selection?.count, 73)
        XCTAssertEqual(view.renderCount, 1)
        view.clearHover(); scheduler.fireAll()
        XCTAssertEqual(view.renderCount, 1)
        view.apply([.init(id: "A", count: 81)])
        XCTAssertEqual(selection?.count, 73)
        scheduler.fireAll()
        XCTAssertEqual(selection?.count, 81)
        XCTAssertEqual(view.renderCount, 2)
        view.selectKey("not-a-key")
        XCTAssertNil(selection)
        XCTAssertEqual(view.renderCount, 2)
    }

    func testFormalHistoryMapsTo3DWithCalendarGapsAndModifierFallback() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        func day(_ key: String, counts: [String: Int]) -> DailyStats {
            var value = DailyStats(date: formatter.date(from: key)!)
            value.keyPresses = counts.values.reduce(0, +); value.keyPressCounts = counts
            return value
        }
        let history = ["2026-10-01": day("2026-10-01", counts: ["Cmd+A": 3]),
                       "2026-10-03": day("2026-10-03", counts: ["A": 7, "Shift++": 2])]
        let period = try XCTUnwrap(KeyboardTrackingPeriod(history: history, calendar: calendar, dateKeyFormatter: formatter))
        let presentation = try XCTUnwrap(GrowthKeyboardPresentation(timeline: CumulativeKeyboardTimeline.build(history: history),
            period: period, now: formatter.date(from: "2026-10-03")!, calendar: calendar))
        let layout = layout(), scheduler = StaticRenderScheduler()
        var received: [[GrowthKeyboardKeyUsage]] = []
        let view = GrowthKeyboard3DRenderer(layout: layout, renderFrame: { values, _ in
            received.append(values); return self.fakeFrame(layout)
        }, schedule: scheduler.schedule)
        view.setActive(true)
        for day in 0..<3 { view.apply(presentation.frame(at: day).keyUsages); scheduler.fireAll() }
        XCTAssertEqual(received.count, 2) // Missing calendar date reuses the same cumulative geometry.
        XCTAssertEqual(received[0].first { $0.id == "A" }?.count, 3)
        XCTAssertEqual(received[1].first { $0.id == "A" }?.count, 10)
        XCTAssertEqual(received[1].first { $0.id == "=" }?.count, 2)
        XCTAssertEqual(received[1].first { $0.id == "LeftCmd" }?.count, 3)
        XCTAssertEqual(received[1].first { $0.id == "RightCmd" }?.count, 0)
        XCTAssertEqual(received[1].count, 77)
    }
}
