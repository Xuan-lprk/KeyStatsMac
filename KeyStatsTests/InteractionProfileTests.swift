import XCTest
@testable import KeyStatsCore

final class InteractionProfileTests: XCTestCase {
    private func app(_ id: String, keys: Int = 0, clicks: Int = 0,
                     distance: Double = 0, sessions: Int = 0, name: String = "") -> AppStats {
        var result = AppStats(bundleId: id, displayName: name)
        result.keyPresses = keys
        result.leftClicks = clicks
        result.scrollDistance = distance
        result.scrollSessions = sessions
        return result
    }

    private func day(_ index: Int, _ apps: [AppStats]) -> DailyStats {
        var result = DailyStats(date: Date(timeIntervalSinceReferenceDate: 0))
        // Assign exact dates: fixtures must not depend on the machine's current calendar.
        result.date = Date(timeIntervalSinceReferenceDate: Double(index) * 86_400)
        result.appStats = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleId, $0) })
        return result
    }

    func testRanksAndTiesIgnoreZeroCohort() {
        let zeros = (0..<50).map { app("zero\($0)") }
        let profiles = InteractionProfileCalculator.calculate(days: [day(0, [
            app("a", keys: 10), app("b", keys: 20), app("c", keys: 20), app("d", keys: 40)
        ] + zeros)])
        XCTAssertEqual(Array(profiles.prefix(4)).map { $0.keyboard.score }, [0.125, 0.5, 0.5, 0.875])
        XCTAssertTrue(profiles.allSatisfy { $0.keyboard.cohortSize == 4 })
        XCTAssertTrue(profiles.dropFirst(4).allSatisfy { $0.keyboard.score == 0 })
        XCTAssertTrue(profiles.allSatisfy { $0.keyboard.comparability == .ranked })
    }

    func testEmptyAllZeroAndSinglePositive() {
        XCTAssertEqual(InteractionProfileCalculator.calculate(days: []), [])
        let zero = InteractionProfileCalculator.calculate(days: [day(0, [app("zero")])])[0]
        XCTAssertEqual(zero.keyboard.score, 0)
        XCTAssertEqual(zero.keyboard.comparability, .none)
        XCTAssertEqual(zero.scroll.comparability, .none)
        let single = InteractionProfileCalculator.calculate(days: [day(0, [app("a", keys: 1), app("b")])])
        XCTAssertEqual(single[0].keyboard.score, 0.5)
        XCTAssertEqual(single[0].keyboard.comparability, .unrankable)
        XCTAssertEqual(single[1].keyboard.score, 0)
        XCTAssertEqual(single[1].keyboard.cohortSize, 1)
    }

    func testOutlierDoesNotCompressOtherRanks() {
        func scores(_ highest: Int) -> [Double] {
            InteractionProfileCalculator.calculate(days: [day(0, [
                app("a", keys: 10), app("b", keys: 20), app("c", keys: highest)
            ])]).map { $0.keyboard.score }
        }
        XCTAssertEqual(scores(30), scores(Int.max))
        XCTAssertEqual(scores(30)[1], 0.5)
    }

    func testPointerUsesAllFourClickTypesOnly() {
        var first = app("a", keys: 100_000, clicks: 1)
        first.rightClicks = 2
        first.sideBackClicks = 3
        first.sideForwardClicks = 4
        first.keyPressCounts = ["A": 999_999]
        var input = day(0, [first, app("b", clicks: 20)])
        input.mouseDistance = 999_999
        input.middleClicks = 999_999
        let result = InteractionProfileCalculator.calculate(days: [input])
        XCTAssertEqual(result[0].pointer.rawValue, 10)
        XCTAssertEqual(result.map { $0.pointer.score }, [0.25, 0.75])
        XCTAssertEqual(input.appStats["a"]?.keyPressCounts, ["A": 999_999])
    }

    func testScrollAveragesComponentRanksNotRawValues() {
        let result = InteractionProfileCalculator.calculate(days: [day(0, [
            app("a", distance: 100_000, sessions: 1),
            app("b", distance: 10, sessions: 100)
        ])])
        XCTAssertEqual(result[0].scroll.distance.score, 0.75)
        XCTAssertEqual(result[0].scroll.sessions.score, 0.25)
        XCTAssertEqual(result.map { $0.scroll.score }, [0.5, 0.5])
        XCTAssertEqual(result[0].scroll.comparability, .ranked)
    }

    func testScrollUsesOnlyPositiveComponentsAndConservativeComparability() {
        let result = InteractionProfileCalculator.calculate(days: [day(0, [
            app("a", distance: 100), app("b", sessions: 10), app("c", distance: 200), app("d")
        ])])
        XCTAssertEqual(result[0].scroll.score, 0.25)
        XCTAssertEqual(result[0].scroll.comparability, .ranked)
        XCTAssertEqual(result[1].scroll.score, 0.5)
        XCTAssertEqual(result[1].scroll.comparability, .unrankable)
        XCTAssertEqual(result[3].scroll.score, 0)
        XCTAssertEqual(result[3].scroll.comparability, .none)
        let mixed = InteractionProfileCalculator.calculate(days: [day(0, [
            app("a", distance: 100, sessions: 2), app("b", distance: 200)
        ])])[0]
        XCTAssertEqual(mixed.scroll.score, 0.375)
        XCTAssertEqual(mixed.scroll.comparability, .unrankable)
    }

    func testMultipleDaysMissingAppAndStableNames() {
        let inputs = [
            day(0, [app("a", keys: 10, distance: 100, name: "Old"), app("b", clicks: 1)]),
            day(1, [app("b", clicks: 2)]),
            day(2, [app("a", keys: 20, clicks: 2, sessions: 4, name: "New")]),
            day(3, [app("a", name: "")])
        ]
        let result = InteractionProfileCalculator.calculate(days: inputs)
        XCTAssertEqual(result, InteractionProfileCalculator.calculate(days: inputs.reversed()))
        XCTAssertEqual(result.map(\.bundleId), ["a", "b"])
        let a = result[0]
        XCTAssertEqual(a.displayName, "New")
        XCTAssertEqual(a.observedDays, 4)
        XCTAssertEqual(a.activeDays, 2)
        XCTAssertEqual(a.keyboard.rawValue, 30)
        XCTAssertEqual(a.keyboard.activeDays, 2)
        XCTAssertEqual(a.pointer.activeDays, 1)
        XCTAssertEqual(a.scroll.activeDays, 2)
        XCTAssertEqual(a.scroll.distance.activeDays, 1)
        XCTAssertEqual(a.scroll.sessions.activeDays, 1)
        XCTAssertEqual(result[1].pointer.rawValue, 3)
        XCTAssertEqual(result[1].displayName, "b")
    }

    func testBundleIdentityUsesTrimmedValueThenDictionaryKey() {
        var input = day(0, [])
        input.appStats = ["fallback": app("", keys: 1), "alias": app(" canonical ", clicks: 1)]
        let result = InteractionProfileCalculator.calculate(days: [input])
        XCTAssertEqual(result.map(\.bundleId), ["canonical", "fallback"])
    }

    func testInvalidValuesDoNotCreateActivityOrNonfiniteScores() {
        var invalid = app("a", keys: -1, clicks: -1, distance: .infinity, sessions: -1)
        invalid.rightClicks = -5
        let result = InteractionProfileCalculator.calculate(days: [day(0, [invalid])])[0]
        XCTAssertEqual(result.activeDays, 0)
        XCTAssertEqual(result.keyboard.rawValue, 0)
        XCTAssertEqual(result.pointer.rawValue, 0)
        XCTAssertEqual(result.scroll.score, 0)
        XCTAssertEqual(result.scroll.distance.rawValue, 0)
    }
}
