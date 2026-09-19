import Foundation

/// Presentation-only snapshot of an AppStats returned by appStatsSummary(range:).
struct AppKeyBreakdown {
    struct Entry: Equatable {
        let key: String
        let count: Int
    }

    enum Coverage: Equatable {
        case noActivity
        case unavailable
        case partial
        case complete
    }

    let entries: [Entry]
    let totalKeyPresses: Int
    let namedKeyPresses: Int
    let coverage: Coverage

    /// Translate labels only after sorting; canonical entry keys remain untouched.
    static func displayKey(_ key: String, bundle: Bundle = .main) -> String {
        key.split(separator: "+", omittingEmptySubsequences: false).map { part in
            switch part {
            case "Left", "Right", "Up", "Down":
                return NSLocalizedString("appStats.breakdown.arrow.\(part)", bundle: bundle, comment: "")
            default:
                return String(part)
            }
        }.joined(separator: "+")
    }

    func summaryText(bundle: Bundle = .main, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        func number(_ value: Int) -> String {
            formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        switch coverage {
        case .complete, .noActivity:
            return String(format: NSLocalizedString("appStats.breakdown.total", bundle: bundle, comment: ""),
                          number(totalKeyPresses))
        case .partial, .unavailable:
            return String(format: NSLocalizedString("appStats.breakdown.coverage", bundle: bundle, comment: ""),
                          number(namedKeyPresses), number(totalKeyPresses))
        }
    }

    var noticeLocalizationKey: String? {
        switch coverage {
        case .noActivity: return "appStats.breakdown.noActivity"
        case .unavailable: return "appStats.breakdown.unavailable"
        case .partial: return "appStats.breakdown.incomplete"
        case .complete: return nil
        }
    }

    init(appStats: AppStats) {
        let counts = keyBreakdownDisplayCounts(from: appStats.keyPressCounts)
        entries = counts.map { Entry(key: $0.key, count: $0.value) }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            // Locale-independent tie break keeps ordering deterministic.
            return $0.key < $1.key
        }
        totalKeyPresses = max(0, appStats.keyPresses)
        namedKeyPresses = entries.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(entry.count)
            return overflow ? Int.max : sum
        }
        if entries.isEmpty {
            coverage = totalKeyPresses > 0 ? .unavailable : .noActivity
        } else {
            coverage = namedKeyPresses < totalKeyPresses ? .partial : .complete
        }
    }
}
