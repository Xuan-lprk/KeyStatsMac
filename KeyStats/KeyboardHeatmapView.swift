import Cocoa

final class KeyboardHeatmapView: NSView {
    private struct RenderMetrics {
        let scale: CGFloat
        let origin: CGPoint
        let layoutBounds: CGRect
    }

    struct KeySpec {
        let id: String
        let label: String
        let frameUnits: CGRect
        let symbolName: String?
        let fallbackCountIDs: [String]
    }

    static let supportedKeyIDs: Set<String> = KeyboardLayout.macStyle.supportedKeyIDs
    private static let numberKeyIDs: Set<String> = Set((0...9).map(String.init))
    private static let layoutContentInset: CGFloat = 8
    private static let maximumKeyboardScale: CGFloat = 58

    private static let layout: [KeySpec] = {
        let definition = KeyboardLayout.macStyle
        return definition.rows.flatMap { row in
            var x = row.startXUnits
            return row.keys.map { key in
                let keyX = key.xUnits.map { row.startXUnits + $0 } ?? x
                let spec = KeySpec(
                    id: key.id,
                    label: key.label,
                    frameUnits: CGRect(x: keyX, y: row.yUnits + key.yOffsetUnits,
                                       width: key.widthUnits, height: key.heightUnits),
                    symbolName: key.symbolName,
                    fallbackCountIDs: key.fallbackCountIDs
                )
                x = keyX + key.widthUnits + definition.keySpacingUnits
                return spec
            }
        }
    }()

    private var keyCounts: [String: Int] = [:]
    private var maxCount: Int = 0

    private lazy var toolTipCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    override var isFlipped: Bool {
        true
    }

    func apply(keyCounts: [String: Int]) {
        self.keyCounts = keyCounts
        self.maxCount = keyCounts.values.max() ?? 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let metrics = renderMetrics() else { return }

        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let labelColor: NSColor = isDarkMode ? .white : .labelColor
        for key in Self.layout {
            let frame = keyFrame(for: key, metrics: metrics)

            let count = count(for: key)
            let fillColor = color(for: count, isDarkMode: isDarkMode)

            let keyPath = NSBezierPath(roundedRect: frame, xRadius: max(4, metrics.scale * 0.14), yRadius: max(4, metrics.scale * 0.14))
            fillColor.setFill()
            keyPath.fill()

            let borderColor = isDarkMode ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.09)
            borderColor.setStroke()
            keyPath.lineWidth = 0.8
            keyPath.stroke()

            drawKeyLegend(
                for: key,
                in: frame,
                scale: metrics.scale,
                textColor: labelColor
            )
            drawCountBadge(for: count, in: frame, scale: metrics.scale, isDarkMode: isDarkMode)
        }
    }

    private static func layoutBounds() -> CGRect {
        Self.layout.reduce(into: CGRect.null) { partialResult, key in
            partialResult = partialResult.union(key.frameUnits)
        }
    }

    private func renderMetrics() -> RenderMetrics? {
        guard !Self.layout.isEmpty else { return nil }

        let availableBounds = bounds.insetBy(dx: Self.layoutContentInset, dy: Self.layoutContentInset)
        guard availableBounds.width > 0, availableBounds.height > 0 else { return nil }

        let layoutBounds = Self.layoutBounds()
        let scaleX = availableBounds.width / layoutBounds.width
        let scaleY = availableBounds.height / layoutBounds.height
        let scale = min(scaleX, scaleY, Self.maximumKeyboardScale)
        let actualSize = CGSize(width: layoutBounds.width * scale, height: layoutBounds.height * scale)
        let origin = CGPoint(
            x: availableBounds.midX - actualSize.width / 2 - layoutBounds.minX * scale,
            y: availableBounds.midY - actualSize.height / 2 - layoutBounds.minY * scale
        )
        return RenderMetrics(scale: scale, origin: origin, layoutBounds: layoutBounds)
    }

    private func keyFrame(for key: KeySpec, metrics: RenderMetrics) -> CGRect {
        CGRect(
            x: metrics.origin.x + key.frameUnits.minX * metrics.scale,
            y: metrics.origin.y + key.frameUnits.minY * metrics.scale,
            width: key.frameUnits.width * metrics.scale,
            height: key.frameUnits.height * metrics.scale
        )
    }

    private func drawKeyLegend(for key: KeySpec, in frame: CGRect, scale: CGFloat, textColor: NSColor) {
        if let symbolName = key.symbolName {
            drawSymbolLegend(for: key, symbolName: symbolName, in: frame, scale: scale, textColor: textColor)
            return
        }

        guard !key.label.isEmpty else { return }

        if key.label.contains("\n") {
            drawDualLineLegend(for: key, in: frame, scale: scale, textColor: textColor)
            return
        }

        let font = NSFont.systemFont(ofSize: max(9, min(13, scale * 0.28)), weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let size = key.label.size(withAttributes: attributes)

        let horizontalInset = max(4, scale * 0.16)
        let verticalInset = max(3, scale * 0.14)
        let point = CGPoint(
            x: frame.maxX - size.width - horizontalInset,
            y: frame.maxY - size.height - verticalInset
        )

        key.label.draw(at: point, withAttributes: attributes)
    }

    private func drawSymbolLegend(for key: KeySpec, symbolName: String, in frame: CGRect, scale: CGFloat, textColor: NSColor) {
        let symbolPointSize = max(10, min(15, scale * 0.30))
        let symbolWeight: NSFont.Weight = key.id.contains("Shift") ? .semibold : .medium
        let horizontalInset = max(4, scale * 0.14)
        let bottomInset = max(3, scale * 0.12)
        let symbolRect = CGRect(
            x: frame.maxX - symbolPointSize * 1.04 - horizontalInset,
            y: frame.maxY - symbolPointSize * 1.04 - bottomInset,
            width: symbolPointSize * 1.04,
            height: symbolPointSize * 1.04
        )

        if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: symbolWeight)) {
            symbolImage.draw(in: symbolRect)
        }

        guard !key.label.isEmpty else { return }

        let labelFont = NSFont.systemFont(ofSize: max(7.5, min(9.5, scale * 0.19)), weight: .medium)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: textColor.withAlphaComponent(0.86)
        ]
        let labelSize = key.label.size(withAttributes: labelAttributes)
        let labelBottomGap = max(2, scale * 0.08)
        let labelPoint = CGPoint(
            x: frame.maxX - labelSize.width - horizontalInset,
            y: max(frame.minY + 2, symbolRect.minY - labelSize.height - labelBottomGap)
        )
        key.label.draw(at: labelPoint, withAttributes: labelAttributes)
    }

    private func drawDualLineLegend(for key: KeySpec, in frame: CGRect, scale: CGFloat, textColor: NSColor) {
        let components = key.label
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard components.count == 2 else { return }

        let upper = components[0]
        let lower = components[1]

        let upperFont = NSFont.systemFont(ofSize: max(8, min(11, scale * 0.23)), weight: .regular)
        let lowerFont = NSFont.systemFont(ofSize: max(9.5, min(13, scale * 0.28)), weight: .medium)
        let upperAttributes: [NSAttributedString.Key: Any] = [
            .font: upperFont,
            .foregroundColor: textColor.withAlphaComponent(0.84)
        ]
        let lowerAttributes: [NSAttributedString.Key: Any] = [
            .font: lowerFont,
            .foregroundColor: textColor
        ]

        let upperSize = upper.size(withAttributes: upperAttributes)
        let lowerSize = lower.size(withAttributes: lowerAttributes)
        let horizontalInset = max(4, scale * 0.16)
        let bottomInset = max(2.5, scale * 0.11)
        let lineSpacing = max(1.5, scale * 0.05)

        let lowerPoint = CGPoint(
            x: frame.maxX - lowerSize.width - horizontalInset,
            y: frame.maxY - lowerSize.height - bottomInset
        )

        if Self.numberKeyIDs.contains(key.id) {
            lower.draw(at: lowerPoint, withAttributes: lowerAttributes)
            return
        }

        let upperPoint = CGPoint(
            x: frame.maxX - upperSize.width - horizontalInset,
            y: max(frame.minY + 2, lowerPoint.y - upperSize.height - lineSpacing)
        )

        upper.draw(at: upperPoint, withAttributes: upperAttributes)
        lower.draw(at: lowerPoint, withAttributes: lowerAttributes)
    }

    private func count(for key: KeySpec) -> Int {
        if let direct = keyCounts[key.id] {
            return direct
        }

        for fallbackID in key.fallbackCountIDs {
            if let fallbackCount = keyCounts[fallbackID] {
                return fallbackCount
            }
        }

        return 0
    }

    private func drawCountBadge(for count: Int, in frame: CGRect, scale: CGFloat, isDarkMode: Bool) {
        guard count > 0 else { return }

        let inset = max(3, scale * 0.08)
        let horizontalPadding = max(4, scale * 0.10)
        let verticalPadding = max(1.5, scale * 0.05)
        let maxBadgeWidth = max(14, frame.width - inset * 2)
        guard maxBadgeWidth > 10 else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: max(7, min(10.5, scale * 0.20)), weight: .semibold)
        let textColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.95)
            : NSColor(calibratedWhite: 0.12, alpha: 0.95)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        var text = toolTipCountFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        let fullTextWidth = text.size(withAttributes: attributes).width + horizontalPadding * 2
        if fullTextWidth > maxBadgeWidth {
            text = compactCountText(for: count)
        }

        var textSize = text.size(withAttributes: attributes)
        let badgeHeight = max(max(12, scale * 0.30), textSize.height + verticalPadding * 2)
        var badgeWidth = max(badgeHeight, textSize.width + horizontalPadding * 2)
        if badgeWidth > maxBadgeWidth {
            badgeWidth = maxBadgeWidth
            text = compactCountText(for: count, maximumLength: 3)
            textSize = text.size(withAttributes: attributes)
        }

        let badgeRect = CGRect(
            x: frame.minX + inset,
            y: frame.minY + inset,
            width: badgeWidth,
            height: badgeHeight
        )

        let badgePath = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: badgeHeight * 0.5,
            yRadius: badgeHeight * 0.5
        )
        let backgroundColor = isDarkMode
            ? NSColor.black.withAlphaComponent(0.38)
            : NSColor.white.withAlphaComponent(0.84)
        backgroundColor.setFill()
        badgePath.fill()

        let borderColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.black.withAlphaComponent(0.14)
        borderColor.setStroke()
        badgePath.lineWidth = 0.7
        badgePath.stroke()

        let textPoint = CGPoint(
            x: badgeRect.minX + (badgeRect.width - textSize.width) / 2,
            y: badgeRect.minY + (badgeRect.height - textSize.height) / 2 + font.descender * 0.45
        )
        text.draw(at: textPoint, withAttributes: attributes)
    }

    private func compactCountText(for count: Int, maximumLength: Int = 4) -> String {
        let compact: String
        if count >= 1_000_000_000 {
            compact = compactUnit(Double(count) / 1_000_000_000, suffix: "B")
        } else if count >= 1_000_000 {
            compact = compactUnit(Double(count) / 1_000_000, suffix: "M")
        } else if count >= 1_000 {
            compact = compactUnit(Double(count) / 1_000, suffix: "K")
        } else {
            compact = "\(count)"
        }

        if compact.count <= maximumLength {
            return compact
        }

        if count >= 1_000_000_000 {
            return "\(Int(round(Double(count) / 1_000_000_000)))B"
        }
        if count >= 1_000_000 {
            return "\(Int(round(Double(count) / 1_000_000)))M"
        }
        if count >= 1_000 {
            return "\(Int(round(Double(count) / 1_000)))K"
        }
        return compact
    }

    private func compactUnit(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        let numberText: String
        if abs(rounded.rounded() - rounded) < 0.05 {
            numberText = "\(Int(rounded.rounded()))"
        } else {
            numberText = String(format: "%.1f", rounded)
        }
        return "\(numberText)\(suffix)"
    }

    private func color(for count: Int, isDarkMode: Bool) -> NSColor {
        let surfaceColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor
        let neutralColor = surfaceColor.blended(withFraction: isDarkMode ? 0.22 : 0.10, of: .separatorColor)
            ?? (isDarkMode
                ? NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.25, alpha: 1)
                : NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))

        if count <= 0 {
            return neutralColor
        }

        let normalized = maxCount > 0
            ? CGFloat(log(Double(count) + 1) / log(Double(maxCount) + 1))
            : 0
        let eased = pow(normalized, 0.82)

        let accentColor = NSColor.controlAccentColor
        let lowColor = neutralColor.blended(withFraction: isDarkMode ? 0.34 : 0.24, of: accentColor)
            ?? blendColor(from: neutralColor, to: accentColor, t: isDarkMode ? 0.34 : 0.24)
        let highColor = accentColor.blended(withFraction: isDarkMode ? 0.18 : 0.10, of: isDarkMode ? .white : .black)
            ?? blendColor(from: accentColor, to: isDarkMode ? .white : .black, t: isDarkMode ? 0.18 : 0.10)

        return blendColor(from: lowColor, to: highColor, t: eased)
    }

    private func blendColor(from: NSColor, to: NSColor, t: CGFloat) -> NSColor {
        let progress = max(0, min(1, t))
        let fromRGB = from.usingColorSpace(.deviceRGB) ?? from
        let toRGB = to.usingColorSpace(.deviceRGB) ?? to

        let red = fromRGB.redComponent + (toRGB.redComponent - fromRGB.redComponent) * progress
        let green = fromRGB.greenComponent + (toRGB.greenComponent - fromRGB.greenComponent) * progress
        let blue = fromRGB.blueComponent + (toRGB.blueComponent - fromRGB.blueComponent) * progress
        let alpha = fromRGB.alphaComponent + (toRGB.alphaComponent - fromRGB.alphaComponent) * progress

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}
