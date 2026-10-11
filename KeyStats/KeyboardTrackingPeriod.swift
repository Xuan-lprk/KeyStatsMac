import Foundation

/// Calendar-day numbering from the earliest keyboard-active day in normalized
/// display history. No storage, UI or physical-key/layout data is involved.
struct KeyboardTrackingPeriod {
    let firstTrackedDayKey: String
    let firstTrackedDate: Date

    private let calendar: Calendar
    private let dateKeyFormatter: DateFormatter

    /// Uses the history provider's calendar and formatter configuration, rather
    /// than defining a second historical-date format or normalization policy.
    init?(
        history: [String: DailyStats],
        calendar: Calendar,
        dateKeyFormatter: DateFormatter
    ) {
        guard let first = history.lazy.filter({ $0.value.keyPresses > 0 })
            .min(by: { $0.key < $1.key }),
              let formatter = dateKeyFormatter.copy() as? DateFormatter,
              let date = formatter.date(from: first.key),
              formatter.string(from: date) == first.key else { return nil }
        firstTrackedDayKey = first.key
        firstTrackedDate = calendar.startOfDay(for: date)
        self.calendar = calendar
        // Own the query's formatting context so external formatter changes do not
        // change an already derived period. The live provider's formatter is untouched.
        self.dateKeyFormatter = formatter
    }

    /// Targets may have no daily record. Earlier or invalid dates have no index.
    func dayIndex(for dayKey: String) -> Int? {
        guard let date = dateKeyFormatter.date(from: dayKey),
              dateKeyFormatter.string(from: date) == dayKey,
              let days = calendar.dateComponents(
                [.day], from: firstTrackedDate, to: calendar.startOfDay(for: date)
              ).day,
              days >= 0 else { return nil }
        let (index, overflow) = days.addingReportingOverflow(1)
        return overflow ? nil : index
    }

    /// The saved local-date identity is authoritative, not a reformatting of Date
    /// in a potentially different timezone.
    func dayIndex(for snapshot: CumulativeKeyboardSnapshot) -> Int? {
        dayIndex(for: snapshot.dayKey)
    }
}
