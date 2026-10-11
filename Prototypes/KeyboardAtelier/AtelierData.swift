import Foundation

func L(_ key: String) -> String { NSLocalizedString(key, comment: "Keyboard Atelier prototype") }

struct AtelierDataset {
    let snapshot: CumulativeKeyboardSnapshot
    let firstDay: String?
    let dayIndex: Int?
    let physical: PhysicalKeyMappingResult
    let isSimulated: Bool
    let sourceNote: String

    func count(for key: KeyboardKey) -> Int {
        if let count = physical.counts[key.id] { return count }
        // Intentionally the same direct-then-generic fallback as the existing heatmap.
        for alias in key.fallbackCountIDs {
            if let count = physical.counts[alias] { return count }
        }
        return 0
    }
}

/// Prototype-only read adapter. Never constructs StatsManager (its init saves data),
/// never uses standard UserDefaults, Helper, SyncCoordinator or a network client.
enum AtelierData {
    static let preferenceURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.xuanlprk.KeyStatsMac.plist")

    static func load() throws -> AtelierDataset {
        let bytes = try Data(contentsOf: preferenceURL)
        guard let plist = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        let decoder = JSONDecoder()
        // Decode failures are explicit, not silently replaced by a synthetic dataset.
        var raw: [String: DailyStats] = [:]
        if let history = plist["dailyStatsHistory"] as? Data {
            raw = try decoder.decode([String: DailyStats].self, from: history)
        }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var history: [String: DailyStats] = [:]
        var fallback: [(String, DailyStats)] = []
        for (key, var day) in raw.sorted(by: { $0.key < $1.key }) {
            if let date = formatter.date(from: key), formatter.string(from: date) == key {
                day.date = calendar.startOfDay(for: date)
                history[key] = day
            } else {
                day.date = calendar.startOfDay(for: day.date)
                fallback.append((formatter.string(from: day.date), day))
            }
        }
        for (key, day) in fallback where history[key] == nil { history[key] = day }
        if let data = plist["dailyStats"] as? Data {
            var current = try decoder.decode(DailyStats.self, from: data)
            current.date = calendar.startOfDay(for: current.date)
            history[formatter.string(from: current.date)] = current
        }
        guard let latestKey = history.keys.max(),
              let snapshot = CumulativeKeyboardTimeline.snapshot(asOf: latestKey, history: history)
        else { throw CocoaError(.fileReadCorruptFile) }
        let period = KeyboardTrackingPeriod(history: history, calendar: calendar, dateKeyFormatter: formatter)
        return AtelierDataset(snapshot: snapshot, firstDay: period?.firstTrackedDayKey,
            dayIndex: period?.dayIndex(for: snapshot), physical: PhysicalKeyMapping.map(snapshot.keyPressCounts),
            isSimulated: false, sourceNote: L("source.local"))
    }

    /// Fixed fixture, not the user's data extrapolated into a claim about the future.
    /// One dictionary of aggregate whole events is scaled for visual comparison only.
    static func simulated(_ stage: Int) -> AtelierDataset {
        let base: [String: Int] = [
            "A": 320, "S": 280, "D": 195, "F": 80, "G": 145, "H": 210, "J": 70, "K": 190,
            "L": 245, "Q": 45, "W": 120, "E": 510, "R": 270, "T": 460, "Y": 125, "U": 180,
            "I": 365, "O": 290, "P": 90, "Z": 12, "X": 18, "C": 170, "V": 50, "B": 85,
            "N": 400, "M": 155, "Space": 1_800, "Return": 450, "Delete": 850, "Tab": 80,
            "Esc": 30, "Left": 110, "Right": 85, "Up": 32, "Down": 70, "1": 45, "2": 20,
            "3": 10, "4": 8, "5": 6, "0": 20, ";": 13, "'": 30, ",": 90, ".": 140,
            "/": 45, "=": 12, "[": 6, "]": 6, "\u{005C}": 5, "\u{0060}": 3, "-": 20,
            "LeftCmd+C": 165, "LeftCmd+V": 140, "LeftCmd+S": 60, "LeftCmd+Z": 35,
            "LeftShift+A": 30, "LeftShift+T": 45, "LeftShift+Return": 22,
            "RightShift+P": 5, "RightCmd+W": 8, "LeftOption+Left": 25,
            "Ctrl+C": 28, "Fn": 8, "F1": 2, "F2": 4, "F5": 3, "F7": 1, "F12": 1
        ]
        let scales = [0.12, 12.0, 320.0]
        let keys = base.mapValues { max(0, Int((Double($0) * scales[stage]).rounded())) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let firstDate = formatter.date(from: "2024-01-01")!
        let dayNumbers = [7, 180, 1_095]
        let date = calendar.date(byAdding: .day, value: dayNumbers[stage] - 1, to: firstDate)!
        let key = formatter.string(from: date)
        var first = DailyStats(date: firstDate)
        first.date = firstDate
        first.keyPresses = 1
        var last = DailyStats(date: date)
        last.date = date
        last.keyPressCounts = keys
        last.keyPresses = keys.values.reduce(0, +)
        let history = ["2024-01-01": first, key: last]
        let snapshot = CumulativeKeyboardTimeline.snapshot(asOf: key, history: history)!
        let period = KeyboardTrackingPeriod(history: history, calendar: calendar, dateKeyFormatter: formatter)!
        return AtelierDataset(snapshot: snapshot, firstDay: period.firstTrackedDayKey,
            dayIndex: period.dayIndex(for: snapshot), physical: PhysicalKeyMapping.map(snapshot.keyPressCounts),
            isSimulated: true, sourceNote: L("source.simulated"))
    }
}

func grouped(_ count: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
}

func compact(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.1fk", Double(count) / 1_000) }
    return "\(count)"
}
