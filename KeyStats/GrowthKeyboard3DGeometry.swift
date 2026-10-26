import Foundation

/// Geometry v2 from the 77-key Editorial prototype, unchanged. This is presentation
/// mapping only; KeyboardUsageProgress remains the authoritative count → progress curve.
enum GrowthKeyboard3DGeometry {
    static let minimumHeight: CGFloat = 0.012
    static let maximumHeight: CGFloat = 0.476
    static func formation(_ p: Double) -> Double {
        let p = min(1, max(0, p))
        return -expm1(-pow(p / 0.32, 1.6)) / -expm1(-pow(1 / 0.32, 1.6))
    }
    static func height(_ p: Double, maximumHeight: CGFloat = maximumHeight) -> CGFloat {
        minimumHeight + (maximumHeight - minimumHeight) * formation(p)
    }
    static func bevel(_ p: Double) -> CGFloat { 0.0025 + 0.0445 * formation(p) }
}
