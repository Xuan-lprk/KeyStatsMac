import XCTest
@testable import KeyStatsCore

final class KeyboardUsageProgressTests: XCTestCase {
    func testNonpositiveCountsAreZero() {
        for count in [Int.min, -1_000, -1, 0] {
            XCTAssertEqual(KeyboardUsageProgress.progress(for: count), 0)
        }
        XCTAssertGreaterThan(KeyboardUsageProgress.progress(for: 1), 0)
    }

    func testDefaultScaleIsStableAcrossRepresentativeCounts() {
        // Product-scale regression fixtures, not values derived from the implementation.
        let fixtures: [(Int, Double)] = [
            (10, 0.014212714027),
            (100, 0.098868524255),
            (1_000, 0.302422074055),
            (10_000, 0.5),
            (100_000, 0.645706360219),
            (1_000_000, 0.749255425489)
        ]
        for (count, expected) in fixtures {
            XCTAssertEqual(KeyboardUsageProgress.progress(for: count), expected,
                           accuracy: 1e-9, "count: \(count)")
        }
    }

    func testMonotonicAcrossDenseEarlyCountsAndLongTermExtremes() {
        var previous = 0.0
        for count in 0...100_000 {
            let current = KeyboardUsageProgress.progress(for: count)
            XCTAssertGreaterThanOrEqual(current, previous, "count: \(count)")
            previous = current
        }
        let largeCounts = [100_001, 1_000_000, 10_000_000, 100_000_000,
                           1_000_000_000, Int.max / 2, Int.max - 1, Int.max]
        for count in largeCounts {
            let current = KeyboardUsageProgress.progress(for: count)
            XCTAssertGreaterThanOrEqual(current, previous, "count: \(count)")
            previous = current
        }
    }

    func testExtremeCountsAreFiniteAndBounded() {
        for count in [Int.min, -1, 0, 1, 100, 10_000, 1_000_000, Int.max / 2, Int.max] {
            let progress = KeyboardUsageProgress.progress(for: count)
            XCTAssertTrue(progress.isFinite, "count: \(count)")
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        }
    }

    func testLongTermGrowthDoesNotHardCapOrSaturateEarly() {
        let million = KeyboardUsageProgress.progress(for: 1_000_000)
        let tenMillion = KeyboardUsageProgress.progress(for: 10_000_000)
        let hundredMillion = KeyboardUsageProgress.progress(for: 100_000_000)
        XCTAssertLessThan(KeyboardUsageProgress.progress(for: 1_000), 0.5)
        XCTAssertLessThan(million, 0.8)
        XCTAssertGreaterThan(tenMillion, million)
        XCTAssertGreaterThan(hundredMillion, tenMillion)
        XCTAssertLessThan(hundredMillion, 0.9)
        XCTAssertLessThan(KeyboardUsageProgress.progress(for: Int.max), 1)
    }

    func testSameCountIsIndependentOfOtherKeysAndCallOrder() {
        let initial = KeyboardUsageProgress.progress(for: 10_000)
        let lowSpace = ["A": 10_000, "Space": 20_000].mapValues {
            KeyboardUsageProgress.progress(for: $0)
        }
        let highSpace = ["A": 10_000, "Space": 2_000_000].mapValues {
            KeyboardUsageProgress.progress(for: $0)
        }
        XCTAssertEqual(lowSpace["A"], initial)
        XCTAssertEqual(highSpace["A"], initial)
        _ = KeyboardUsageProgress.progress(for: Int.max)
        _ = KeyboardUsageProgress.progress(for: 0)
        XCTAssertEqual(KeyboardUsageProgress.progress(for: 10_000), initial)
    }

    func testConsumesPhysicalCountWithoutReparsingOrChangingStoredCombinations() {
        let snapshot = CumulativeKeyboardSnapshot(dayKey: "2026-10-01", date: .distantPast,
            totalKeyPresses: 10_000, keyPressCounts: ["LeftCmd+C": 9_000, "C": 1_000],
            detailedKeyPresses: 10_000)
        let physical = PhysicalKeyMapping.map(snapshot.keyPressCounts)
        let progress = physical.counts.mapValues { KeyboardUsageProgress.progress(for: $0) }
        XCTAssertEqual(progress["C"], 0.5)
        XCTAssertEqual(progress["LeftCmd"], KeyboardUsageProgress.progress(for: 9_000))
        XCTAssertEqual(snapshot.keyPressCounts, ["LeftCmd+C": 9_000, "C": 1_000])
    }
}
