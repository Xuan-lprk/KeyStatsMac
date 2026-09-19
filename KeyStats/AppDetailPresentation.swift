import Foundation

/// Immutable, localized snapshot prepared before the sheet and its animations exist.
struct AppDetailPresentation {
    struct Card {
        let title: String
        let symbol: String
        let score: Double?
        let rankText: String
        let caption: String
        let evidence: String
        let reference: String
        var accessibilityText: String {
            [title, rankText, caption, evidence, reference].joined(separator: ". ")
        }
    }
    struct Row: Identifiable {
        let id: String
        let label: String
        let count: String
        let usage: Double
    }

    let appName: String
    let rangeTitle: String
    let metadata: String
    let cards: [Card]
    let rows: [Row]
    let breakdownSummary: String
    let breakdownNotice: String?

    static func usage(count: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, Double(count) / Double(maximum)))
    }

    init(app: AppStats, profiles: [InteractionProfile], rangeTitle: String,
         bundle: Bundle = .main, locale: Locale = .current) {
        func text(_ key: String) -> String { NSLocalizedString(key, bundle: bundle, comment: "") }
        func format(_ key: String, _ args: String...) -> String {
            String(format: text(key), arguments: args)
        }
        let numbers = NumberFormatter()
        numbers.numberStyle = .decimal
        numbers.locale = locale
        numbers.maximumFractionDigits = 1
        func number(_ value: Double) -> String {
            numbers.string(from: NSNumber(value: value)) ?? "0"
        }
        let ordinal = NumberFormatter()
        ordinal.locale = locale
        ordinal.numberStyle = .ordinal
        let profile = profiles.first { $0.bundleId == app.bundleId }
        appName = app.displayName.isEmpty ? app.bundleId : app.displayName
        self.rangeTitle = rangeTitle
        metadata = [
            format("appStats.breakdown.total", number(Double(app.keyPresses))),
            format("appDetail.clickCount", number(Double(app.totalClicks))),
            format("appDetail.distance", number(app.scrollDistance))
        ].joined(separator: " · ")

        func card(title: String, symbol: String, score: Double, active: Bool,
                  comparability: InteractionComparability, evidence: String, reference: String) -> Card {
            let ranked = active && comparability == .ranked
            let percentile = Int((min(1, max(0, score)) * 100).rounded())
            let rank = ordinal.string(from: NSNumber(value: percentile)) ?? "\(percentile)"
            return Card(
                title: text(title), symbol: symbol, score: ranked ? score : nil,
                rankText: ranked ? rank : "—",
                caption: ranked ? text("appDetail.percentile")
                    : text(active ? "appDetail.insufficient" : "appDetail.noActivity"),
                evidence: evidence, reference: reference
            )
        }
        func metric(_ dimension: InteractionDimension?, title: String, symbol: String,
                    countKey: String) -> Card {
            let value = dimension?.rawValue ?? 0
            return card(title: title, symbol: symbol, score: dimension?.score ?? 0,
                        active: value > 0, comparability: dimension?.comparability ?? .none,
                        evidence: format(countKey, number(value)) + " · "
                            + format("appDetail.days", number(Double(dimension?.activeDays ?? 0))),
                        reference: format("appDetail.cohort", number(Double(dimension?.cohortSize ?? 0))))
        }
        let scroll = profile?.scroll
        cards = [
            metric(profile?.keyboard, title: "appDetail.keyboard", symbol: "keyboard",
                   countKey: "appStats.breakdown.total"),
            metric(profile?.pointer, title: "appDetail.clicks", symbol: "cursorarrow.click",
                   countKey: "appDetail.clickCount"),
            card(title: "appDetail.scroll", symbol: "arrow.up.arrow.down",
                 score: scroll?.score ?? 0,
                 active: (scroll?.distance.rawValue ?? 0) > 0 || (scroll?.sessions.rawValue ?? 0) > 0,
                 comparability: scroll?.comparability ?? .none,
                 evidence: format("appDetail.distance", number(scroll?.distance.rawValue ?? 0)) + " · "
                    + format("appDetail.sessions", number(scroll?.sessions.rawValue ?? 0)) + "\n"
                    + format("appDetail.days", number(Double(scroll?.activeDays ?? 0))),
                 reference: format("appDetail.scrollCohorts",
                                   number(Double(scroll?.distance.cohortSize ?? 0)),
                                   number(Double(scroll?.sessions.cohortSize ?? 0))))
        ]
        let breakdown = AppKeyBreakdown(appStats: app)
        let maximum = breakdown.entries.first?.count ?? 0
        rows = breakdown.entries.map {
            Row(id: $0.key, label: AppKeyBreakdown.displayKey($0.key, bundle: bundle),
                count: number(Double($0.count)), usage: Self.usage(count: $0.count, maximum: maximum))
        }
        breakdownSummary = breakdown.summaryText(bundle: bundle, locale: locale)
        breakdownNotice = breakdown.noticeLocalizationKey.map(text)
    }
}
