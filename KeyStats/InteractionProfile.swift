import Foundation

enum InteractionComparability: Equatable {
    case none
    case unrankable
    case ranked
}

struct InteractionDimension: Equatable {
    let score: Double
    let rawValue: Double
    let activeDays: Int
    let cohortSize: Int
    let comparability: InteractionComparability
}

struct InteractionScrollDimension: Equatable {
    let score: Double
    let activeDays: Int
    let comparability: InteractionComparability
    let distance: InteractionDimension
    let sessions: InteractionDimension
}

/// Independent relative activity ranks, not interaction proportions or labels.
struct InteractionProfile: Equatable {
    let bundleId: String
    let displayName: String
    let keyboard: InteractionDimension
    let pointer: InteractionDimension
    let scroll: InteractionScrollDimension
    /// Number of supplied daily snapshots, including days this App is absent.
    let observedDays: Int
    let activeDays: Int
}

enum InteractionProfileCalculator {
    /// Supply one complete local snapshot per day in the selected range.
    /// Does not infer missing dates, consult a clock, or reinterpret date identities.
    /// Output is sorted by bundle ID. Latest nonempty name wins.
    static func calculate(days: [DailyStats]) -> [InteractionProfile] {
        var totals: [String: Total] = [:]
        for day in days.sorted(by: { $0.date < $1.date }) {
            for key in day.appStats.keys.sorted() {
                guard let app = day.appStats[key] else { continue }
                let id = app.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                let bundleId = id.isEmpty ? key.trimmingCharacters(in: .whitespacesAndNewlines) : id
                guard !bundleId.isEmpty else { continue }
                var total = totals[bundleId] ?? Total()
                let name = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { total.name = name }
                let keys = Double(max(0, app.keyPresses))
                // Same four buttons as AppStats.totalClicks; Double avoids Int sum overflow.
                let clicks = [app.leftClicks, app.rightClicks, app.sideBackClicks, app.sideForwardClicks]
                    .reduce(0.0) { $0 + Double(max(0, $1)) }
                let distance = app.scrollDistance.isFinite ? max(0, app.scrollDistance) : 0
                let sessions = Double(max(0, app.scrollSessions))
                total.keys += keys
                total.clicks += clicks
                total.distance = min(Double.greatestFiniteMagnitude, total.distance + distance)
                total.sessions += sessions
                if keys > 0 { total.keyDays.insert(day.date) }
                if clicks > 0 { total.clickDays.insert(day.date) }
                if distance > 0 { total.distanceDays.insert(day.date) }
                if sessions > 0 { total.sessionDays.insert(day.date) }
                totals[bundleId] = total
            }
        }

        let values = Array(totals.values)
        let keys = ranks(values.map(\.keys))
        let clicks = ranks(values.map(\.clicks))
        let distances = ranks(values.map(\.distance))
        let sessions = ranks(values.map(\.sessions))

        return totals.keys.sorted().map { id in
            let total = totals[id]!
            let distance = dimension(total.distance, days: total.distanceDays.count, ranks: distances)
            let session = dimension(total.sessions, days: total.sessionDays.count, ranks: sessions)
            let components = [distance, session].filter { $0.rawValue > 0 }
            let scrollDays = total.distanceDays.union(total.sessionDays)
            let scroll = InteractionScrollDimension(
                score: components.isEmpty ? 0 : components.reduce(0) { $0 + $1.score } / Double(components.count),
                activeDays: scrollDays.count,
                comparability: components.isEmpty ? .none
                    : (components.allSatisfy { $0.comparability == .ranked } ? .ranked : .unrankable),
                distance: distance,
                sessions: session
            )
            return InteractionProfile(
                bundleId: id,
                displayName: total.name.isEmpty ? id : total.name,
                keyboard: dimension(total.keys, days: total.keyDays.count, ranks: keys),
                pointer: dimension(total.clicks, days: total.clickDays.count, ranks: clicks),
                scroll: scroll,
                observedDays: days.count,
                activeDays: total.keyDays.union(total.clickDays).union(scrollDays).count
            )
        }
    }

    private struct Total {
        var name = ""
        var keys = 0.0
        var clicks = 0.0
        var distance = 0.0
        var sessions = 0.0
        var keyDays: Set<Date> = []
        var clickDays: Set<Date> = []
        var distanceDays: Set<Date> = []
        var sessionDays: Set<Date> = []
    }

    private static func ranks(_ values: [Double]) -> (scores: [Double: Double], count: Int) {
        let positive = values.filter { $0 > 0 }.sorted()
        var scores: [Double: Double] = [:]
        var start = 0
        while start < positive.count {
            var end = start + 1
            while end < positive.count && positive[end] == positive[start] { end += 1 }
            scores[positive[start]] = (Double(start) + 0.5 * Double(end - start)) / Double(positive.count)
            start = end
        }
        return (scores, positive.count)
    }

    private static func dimension(
        _ value: Double, days: Int, ranks: (scores: [Double: Double], count: Int)
    ) -> InteractionDimension {
        InteractionDimension(
            score: ranks.scores[value] ?? 0,
            rawValue: value,
            activeDays: days,
            cohortSize: ranks.count,
            // Comparability describes the reference cohort even when this App has zero activity.
            comparability: ranks.count == 0 ? .none : (ranks.count == 1 ? .unrankable : .ranked)
        )
    }
}
