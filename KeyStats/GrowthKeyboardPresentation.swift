import Foundation

struct GrowthKeyboardKeyUsage: Equatable {
    let id: String
    let count: Int
    var progress: Double { KeyboardUsageProgress.progress(for: count) }
}

struct GrowthKeyboardFrame {
    let dayKey: String
    let date: Date
    let dayIndex: Int
    let snapshot: CumulativeKeyboardSnapshot
    let physical: PhysicalKeyMappingResult

    var hasPartialDetails: Bool { snapshot.detailedKeyPresses < snapshot.totalKeyPresses }

    var keyUsages: [GrowthKeyboardKeyUsage] {
        KeyboardLayout.macStyle.keys.map { key in
            let count = physical.counts[key.id] ?? key.fallbackCountIDs
                .compactMap { physical.counts[$0] }.first ?? 0
            return GrowthKeyboardKeyUsage(id: key.id, count: count)
        }
    }
}

/// A session's display-aggregated snapshots. No files, defaults, schema or input monitoring.
struct GrowthKeyboardPresentation {
    let snapshots: [CumulativeKeyboardSnapshot]
    let period: KeyboardTrackingPeriod
    let today: Date
    let dayCount: Int
    let calendar: Calendar
    private let formatter: DateFormatter

    /// The production page and tests use this exact adapter, including unsaved
    /// currentStats, established history normalization and Sync display aggregation.
    static func load(from manager: StatsManager, now: Date = Date(),
                     calendar: Calendar = .current) -> GrowthKeyboardPresentation? {
        let timeline = manager.cumulativeKeyboardTimeline()
        guard let period = manager.keyboardTrackingPeriod() else { return nil }
        return GrowthKeyboardPresentation(timeline: timeline, period: period, now: now, calendar: calendar)
    }

    init?(timeline: [CumulativeKeyboardSnapshot], period: KeyboardTrackingPeriod,
          now: Date, calendar: Calendar) {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        let todayKey = formatter.string(from: today)
        let bounded = timeline.filter { $0.dayKey <= todayKey }.sorted { $0.dayKey < $1.dayKey }
        guard let count = period.dayIndex(for: todayKey), count > 0,
              bounded.contains(where: { $0.dayKey == period.firstTrackedDayKey }) else { return nil }
        self.snapshots = bounded
        self.period = period
        self.today = today
        self.dayCount = count
        self.calendar = calendar
        self.formatter = formatter
    }

    func date(at offset: Int) -> Date {
        calendar.date(byAdding: .day, value: min(dayCount - 1, max(0, offset)), to: period.firstTrackedDate)!
    }

    func offset(for date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: period.firstTrackedDate,
                                          to: calendar.startOfDay(for: date)).day ?? 0
        return min(dayCount - 1, max(0, days))
    }

    /// Calendar gaps reuse the latest snapshot, but display the requested date / Day N.
    /// Cached binary search: date scrubbing never rebuilds history.
    func frame(at offset: Int) -> GrowthKeyboardFrame {
        let date = date(at: offset)
        let dayKey = formatter.string(from: date)
        var lower = 0, upper = snapshots.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if snapshots[middle].dayKey <= dayKey { lower = middle + 1 }
            else { upper = middle }
        }
        let snapshot = snapshots[lower - 1]
        return GrowthKeyboardFrame(dayKey: dayKey, date: date,
            dayIndex: period.dayIndex(for: dayKey)!, snapshot: snapshot,
            physical: PhysicalKeyMapping.map(snapshot.keyPressCounts))
    }
}
