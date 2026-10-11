import Foundation

/// Cumulative whole-event counts through an existing historical day, inclusive.
/// dayKey retains the historical local-date identity; date is its normalized representation.
/// Counts retain canonical combinations and are not expanded into physical keys.
struct CumulativeKeyboardSnapshot: Equatable {
    let dayKey: String
    let date: Date
    let totalKeyPresses: Int
    let keyPressCounts: [String: Int]
    /// Sum of available whole-event details, independent of totalKeyPresses.
    /// This is evidence of available data, not an inferred count for missing history.
    let detailedKeyPresses: Int
}

enum CumulativeKeyboardTimeline {
    /// Input must be normalized history, with one complete DailyStats per canonical dayKey.
    /// Date parsing, collision resolution, today replacement and sync aggregation belong
    /// to the existing history provider. This layer never reinterprets date identities.
    ///
    /// Accumulation scans daily entries once. Materializing every cumulative dictionary
    /// additionally costs the sum of cumulative key counts; use snapshot for one cutoff.
    static func build(history: [String: DailyStats]) -> [CumulativeKeyboardSnapshot] {
        var running = Accumulation()
        return history.keys.sorted().map { dayKey in
            let day = history[dayKey]!
            running.include(day)
            return running.snapshot(dayKey: dayKey, date: day.date)
        }
    }

    /// Returns the latest existing day at or before the inclusive cutoff.
    /// Missing days are not synthesized; before the first record the result is nil.
    /// Only one cumulative dictionary is retained in the returned value.
    static func snapshot(
        asOf dayKey: String,
        history: [String: DailyStats]
    ) -> CumulativeKeyboardSnapshot? {
        var running = Accumulation()
        var latest: (dayKey: String, date: Date)?
        for key in history.keys.sorted() {
            guard key <= dayKey else { break }
            let day = history[key]!
            running.include(day)
            latest = (key, day.date)
        }
        guard let latest else { return nil }
        return running.snapshot(dayKey: latest.dayKey, date: latest.date)
    }

    private struct Accumulation {
        var totalKeyPresses = 0
        var keyPressCounts: [String: Int] = [:]
        var detailedKeyPresses = 0

        mutating func include(_ day: DailyStats) {
            totalKeyPresses = add(totalKeyPresses, max(0, day.keyPresses))
            for (key, count) in day.keyPressCounts where count > 0 {
                keyPressCounts[key] = add(keyPressCounts[key] ?? 0, count)
                detailedKeyPresses = add(detailedKeyPresses, count)
            }
        }

        func snapshot(dayKey: String, date: Date) -> CumulativeKeyboardSnapshot {
            CumulativeKeyboardSnapshot(dayKey: dayKey, date: date,
                totalKeyPresses: totalKeyPresses, keyPressCounts: keyPressCounts,
                detailedKeyPresses: detailedKeyPresses)
        }

        private func add(_ lhs: Int, _ rhs: Int) -> Int {
            let (sum, overflow) = lhs.addingReportingOverflow(rhs)
            return overflow ? Int.max : sum
        }
    }
}
