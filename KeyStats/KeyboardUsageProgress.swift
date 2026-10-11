import Foundation

/// Lifetime physical-key participation, not relative heat or percentile rank.
/// Fixed v0 anchors: 100 counts shape early growth; 10,000 counts give 0.5.
/// Changing these anchors changes the product scale and needs deliberate review.
/// Existing heatmaps keep their separate relative normalization.
enum KeyboardUsageProgress {
    private static let earlyGrowthCountScale = 100.0
    private static let halfProgressCount = 10_000.0

    /// Pure count-only mapping. No other keys, dates or user state affect it.
    /// Nonpositive counts are zero; positive counts approach 1 without a hard cap.
    static func progress(for count: Int) -> Double {
        guard count > 0 else { return 0 }
        // Convert before arithmetic to avoid Int overflow, including at Int.max.
        let logUsage = log1p(Double(count) / earlyGrowthCountScale)
        let logHalfProgress = log1p(halfProgressCount / earlyGrowthCountScale)
        // Equivalent to 1 - exp(-log(2) * logUsage / logHalfProgress).
        // expm1 avoids cancellation for small counts; log1p preserves early growth.
        let progress = -expm1(-log(2.0) * logUsage / logHalfProgress)
        return min(1, max(0, progress))
    }
}
