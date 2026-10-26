import Cocoa
import QuartzCore
import CoreText

private func growthLocalized(_ key: String) -> String { NSLocalizedString(key, comment: "Growth Keyboard") }

private func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

/// The outer keyboard page owns one canvas, including the transparent titlebar.
/// Child renderers remain transparent; appearance changes resolve CGColor afresh.
final class KeyboardVisualizationCanvasView: NSView {
    var showsGrowth = true {
        didSet { updateBackground() }
    }

    static func backgroundColor(for appearance: NSAppearance, showsGrowth: Bool) -> NSColor {
        if showsGrowth && appearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua {
            return rgb(0xF2F2EE)
        }
        var color = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor(cgColor: NSColor.windowBackgroundColor.cgColor) ?? .windowBackgroundColor
        }
        return color
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateBackground()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackground()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }
    private func updateBackground() {
        let color = Self.backgroundColor(for: effectiveAppearance, showsGrowth: showsGrowth)
        layer?.backgroundColor = color.cgColor
        if window?.contentView === self { window?.backgroundColor = color }
    }
}

private func blend(_ a: NSColor, _ b: NSColor, _ amount: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * amount,
        green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
        blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount, alpha: 1)
}

/// One continuous material scale, not categories. Warmth starts after 0.72.
private enum EditorialKeyboardMaterial {
    static let stops: [(Double, UInt32)] = [
        (0, 0xF5F5F1), (0.15, 0xE1E8EA), (0.35, 0xB5CCD6),
        (0.50, 0x91B2C3), (0.65, 0x7396AC), (0.72, 0x829B9F),
        (0.80, 0xBDB394), (0.90, 0xD2B477), (1, 0xCFA160)
    ]
    static func color(_ progress: Double) -> NSColor {
        let p = min(1, max(0, progress))
        for i in 1..<stops.count where p <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            return blend(rgb(a.1), rgb(b.1), CGFloat((p - a.0) / (b.0 - a.0)))
        }
        return rgb(stops.last!.1)
    }
}

/// Approved Editorial proportions, derived from the shared keyboard identities.
/// Keep the approved renderer proportions without changing legacy Heatmap geometry.
/// No new key identities, variants or modifier fallback rules.
private enum EditorialKeyboardGeometry {
    static let gap = 0.08
    static let rowWidth = 13.0 + 1.52 + 13 * gap
    static let layout: KeyboardLayout = {
        let arrowStart = rowWidth - (3 + 2 * gap)
        let widths: [String: Double] = [
            "Esc": 1.52, "Delete": 1.52, "Tab": 1.52, "\\": 1,
            "CapsLock": 1.8, "Return": 1.8,
            "LeftShift": 2.34, "RightShift": 2.34,
            "Fn": 1, "Ctrl": 1, "LeftOption": 1, "RightOption": 1,
            "LeftCmd": 1.26, "RightCmd": 1.26,
            // Seven bottom-row keys plus three arrow columns have nine gaps.
            "Space": rowWidth - (1 + 1 + 1 + 1.26 + 1.26 + 1 + 3) - 9 * gap
        ]
        let rows = KeyboardLayout.macStyle.rows.enumerated().map { index, row in
            KeyboardRow(yUnits: Double(index) * (1 + gap), keys: row.keys.map { key in
                let width = index == 0 && key.id != "Esc"
                    ? (rowWidth - widths["Esc"]! - 12 * gap) / 12
                    : widths[key.id] ?? key.widthUnits
                let x: Double?
                switch key.id {
                case "Left": x = arrowStart
                case "Up", "Down": x = arrowStart + 1 + gap
                case "Right": x = arrowStart + 2 * (1 + gap)
                default: x = nil
                }
                return KeyboardKey(id: key.id, label: key.label, widthUnits: width,
                    heightUnits: key.heightUnits, symbolName: key.symbolName,
                    fallbackCountIDs: key.fallbackCountIDs, xUnits: x,
                    yOffsetUnits: key.yOffsetUnits)
            })
        }
        return KeyboardLayout(rows: rows, keySpacingUnits: gap)
    }()
}

/// One board-space projection, sampled once per row. A row uses a uniform scale,
/// so individual tops stay rectangular; labels separately cancel that scale.
private struct EditorialDepthProjection {
    let bounds: CGRect
    var firstRowCenter: CGFloat { bounds.minY + 48 }
    var lastRowCenter: CGFloat { bounds.maxY - 48 }
    func scale(at rowCenterY: CGFloat) -> CGFloat {
        let t = min(1, max(0, (rowCenterY - firstRowCenter) / (lastRowCenter - firstRowCenter)))
        return 0.975 + 0.025 * t
    }
    func point(_ point: CGPoint, rowCenterY: CGFloat? = nil) -> CGPoint {
        let s = scale(at: rowCenterY ?? point.y)
        let referenceY = rowCenterY ?? point.y
        let centerY = bounds.midY + (referenceY - bounds.midY) * 0.965
        return CGPoint(x: bounds.midX + (point.x - bounds.midX) * s,
                       y: centerY + (point.y - referenceY) * s)
    }
    func path(_ path: CGPath) -> CGPath {
        let result = CGMutablePath()
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint: result.move(to: point(e.points[0]))
            case .addLineToPoint: result.addLine(to: point(e.points[0]))
            case .addQuadCurveToPoint:
                result.addQuadCurve(to: point(e.points[1]), control: point(e.points[0]))
            case .addCurveToPoint:
                result.addCurve(to: point(e.points[2]), control1: point(e.points[0]), control2: point(e.points[1]))
            case .closeSubpath: result.closeSubpath()
            @unknown default: preconditionFailure("Unexpected deck path element")
            }
        }
        return result
    }
}

/// One cached, very thin tray; no usage-dependent state or drawing callbacks.
private final class EditorialDeck {
    let root = CALayer()
    let paths: [CGPath]
    let surfaceColor = rgb(0xE2E6E4)
    init(projection: EditorialDepthProjection) {
        let rect = projection.bounds.insetBy(dx: -14, dy: -12)
        let top = projection.path(CGPath(roundedRect: rect, cornerWidth: 19, cornerHeight: 19, transform: nil))
        var extrusion = CGAffineTransform(translationX: 1.6, y: 6.5)
        let base = top.copy(using: &extrusion)!
        let rimRect = rect.insetBy(dx: 1.2, dy: 1.2)
        let rim = projection.path(CGPath(roundedRect: rimRect, cornerWidth: 18, cornerHeight: 18, transform: nil))
        paths = [base, top, rim]
        let edge = CAShapeLayer()
        edge.path = base
        edge.fillColor = rgb(0xBEC7C7).cgColor
        edge.shadowPath = base
        edge.shadowColor = rgb(0x243238).cgColor
        edge.shadowOpacity = 0.16
        edge.shadowOffset = CGSize(width: 2, height: 8)
        edge.shadowRadius = 9
        let surface = CAShapeLayer()
        surface.path = top
        surface.fillColor = surfaceColor.cgColor
        surface.strokeColor = rgb(0xB4BFBD).cgColor
        surface.lineWidth = 0.7
        let lip = CAShapeLayer()
        lip.path = rim
        lip.fillColor = nil
        lip.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        lip.lineWidth = 0.7
        for layer in [edge, surface, lip] { root.addSublayer(layer) }
        root.name = "cached-deck"
        root.isHidden = true
    }
}

/// Cached local geometry: near-overhead parallel projection with thin extrusion.
private struct KeyGeometry {
    let top: CGPath
    let face: CGPath
    let base: CGPath
    let side: CGPath
    let highlight: CGPath
    let front: CGPath

    init(width: CGFloat, height: CGFloat, depth: CGFloat = 5.5, sideOffset: CGFloat = 1) {
        // Each top is a regular rounded rectangle. Space comes from extrusion,
        // bevel and shadow, not a per-key perspective taper.
        // Equal padding on all four sides keeps a 1u key's visible top square.
        let r = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: 3, dy: 3)
        top = CGPath(roundedRect: r, cornerWidth: 7, cornerHeight: 7, transform: nil)
        face = CGPath(roundedRect: r.insetBy(dx: 1.3, dy: 1.3),
                      cornerWidth: 6, cornerHeight: 6, transform: nil)
        var shift = CGAffineTransform(translationX: sideOffset, y: depth)
        base = top.copy(using: &shift)!
        let frontPath = CGMutablePath()
        frontPath.move(to: CGPoint(x: r.minX, y: r.maxY - 7))
        frontPath.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 7))
        frontPath.addLine(to: CGPoint(x: r.maxX + sideOffset, y: r.maxY + depth - 7))
        frontPath.addQuadCurve(to: CGPoint(x: r.maxX + sideOffset - 7, y: r.maxY + depth),
                              control: CGPoint(x: r.maxX + sideOffset, y: r.maxY + depth))
        frontPath.addLine(to: CGPoint(x: r.minX + sideOffset + 7, y: r.maxY + depth))
        frontPath.addQuadCurve(to: CGPoint(x: r.minX + sideOffset, y: r.maxY + depth - 7),
                              control: CGPoint(x: r.minX + sideOffset, y: r.maxY + depth))
        frontPath.closeSubpath()
        front = frontPath
        let sidePath = CGMutablePath()
        sidePath.move(to: CGPoint(x: width - 5, y: r.minY + 7))
        sidePath.addLine(to: CGPoint(x: width - 3 + sideOffset, y: r.maxY - 1))
        sidePath.addQuadCurve(to: CGPoint(x: width - 9 + sideOffset, y: r.maxY + depth),
                             control: CGPoint(x: width - 2 + sideOffset, y: r.maxY + depth))
        sidePath.addLine(to: CGPoint(x: width - 10, y: r.maxY - 1))
        sidePath.closeSubpath()
        side = sidePath
        let light = CGMutablePath()
        light.move(to: CGPoint(x: 5, y: r.maxY - 9))
        light.addLine(to: CGPoint(x: 5, y: r.minY + 8))
        light.addQuadCurve(to: CGPoint(x: 11, y: r.minY + 2),
                          control: CGPoint(x: 5, y: r.minY + 2))
        light.addLine(to: CGPoint(x: width - 13, y: r.minY + 2))
        highlight = light
    }
}

private func textLayer(_ text: String, frame: CGRect, size: CGFloat,
                       weight: NSFont.Weight = .regular, color: NSColor,
                       mono: Bool = false) -> CATextLayer {
    let layer = CATextLayer()
    layer.frame = frame
    layer.contentsScale = 2
    layer.isWrapped = false
    layer.truncationMode = .none
    let font = mono ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                    : NSFont.systemFont(ofSize: size, weight: weight)
    layer.string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    return layer
}

/// One A–Z rule. Measure SF glyph ink once at construction; no per-frame layout.
/// Letters rest at the optical center and lift only while their count is visible.
private enum LetterLegendStyle {
    static let size: CGFloat = 24
    static let font = NSFont.systemFont(ofSize: size, weight: .regular)
    static let tracking: CGFloat = 0
    static let opticalOffsetY: CGFloat = 0
    static let hoverLift: CGFloat = 6

    static func applies(to id: String) -> Bool {
        let bytes = Array(id.utf8)
        return bytes.count == 1 && (65...90).contains(bytes[0])
    }

    static func make(_ letter: String, keySize: CGSize) -> CATextLayer {
        let text = NSAttributedString(string: letter, attributes: [
            .font: font, .kern: tracking, .foregroundColor: rgb(0x26333A)
        ])
        let line = CTLineCreateWithAttributedString(text)
        let ink = CTLineGetImageBounds(line, nil)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        // Ink center, not advance-box center: equal treatment of asymmetric glyphs.
        let frame = CGRect(
            x: keySize.width / 2 - ink.midX,
            y: keySize.height / 2 + opticalOffsetY + ink.midY - font.ascender,
            width: ceil(max(advance, ink.maxX)) + 2,
            height: ceil(font.ascender - font.descender + font.leading)
        )
        let layer = CATextLayer()
        layer.frame = frame
        layer.contentsScale = 2
        layer.isWrapped = false
        layer.alignmentMode = .left
        layer.truncationMode = .none
        layer.string = text
        return layer
    }
}

/// Physical-key legends intentionally retain English modifier names in every locale.
/// Two lines, measured/attributed once; no layout work on hover or data updates.
private enum DualLegendStyle {
    static func make(_ text: String, keySize: CGSize, modifier: Bool) -> CATextLayer {
        let lines = text.components(separatedBy: "\n")
        precondition(lines.count == 2)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = modifier ? .left : .center
        paragraph.lineSpacing = 1
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: rgb(0x26333A), .paragraphStyle: paragraph
        ]
        let content = NSMutableAttributedString(string: text, attributes: attributes)
        let firstLength = (lines[0] as NSString).length
        content.addAttribute(.font, value: NSFont.systemFont(ofSize: modifier ? 24 : 16,
            weight: .regular), range: NSRange(location: 0, length: firstLength + 1))
        content.addAttribute(.font, value: NSFont.systemFont(ofSize: modifier ? 14 : 24,
            weight: .regular), range: NSRange(location: firstLength + 1,
                length: (lines[1] as NSString).length))
        let layer = CATextLayer()
        let inset: CGFloat = modifier ? 14 : 10
        layer.frame = CGRect(x: inset, y: 10, width: keySize.width - 2 * inset, height: 50)
        layer.contentsScale = 2
        layer.isWrapped = false
        layer.truncationMode = .none
        layer.alignmentMode = modifier ? .left : .center
        layer.string = content
        return layer
    }
}

/// One depth treatment for normal, wide and half-height keys.
private enum EditorialDepthStyle {
    static let height: CGFloat = 7
    static let sideOffset: CGFloat = 1.8
    static let shadowOpacity: Float = 0.18
    static let shadowRadius: CGFloat = 2.6
}

private func centeredArrowLegend(_ symbol: String, keySize: CGSize) -> CATextLayer {
    let font = NSFont.systemFont(ofSize: keySize.height < 72 ? 16 : 26, weight: .regular)
    let text = NSAttributedString(string: symbol, attributes: [.font: font, .foregroundColor: rgb(0x26333A)])
    let line = CTLineCreateWithAttributedString(text)
    let ink = CTLineGetImageBounds(line, nil)
    let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let result = textLayer(symbol, frame: CGRect(x: keySize.width / 2 - ink.midX,
        y: keySize.height / 2 + ink.midY - font.ascender,
        width: ceil(max(advance, ink.maxX)) + 2,
        height: ceil(font.ascender - font.descender + font.leading)),
        size: font.pointSize, color: rgb(0x26333A))
    return result
}

private final class EditorialKeycap {
    let root = CALayer()
    let id: String
    private let base = CAShapeLayer()
    private let rightWall = CAShapeLayer()
    private let frontFace = CAShapeLayer()
    private let bevel = CAShapeLayer()
    private let face = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let label: CATextLayer
    private let count: CATextLayer
    private let legendRestPosition: CGPoint
    var sceneKey: EditorialKeyboardSceneKey {
        EditorialKeyboardSceneKey(id: id, size: root.bounds.size, topPath: bevel.path!,
            legend: label.string as! NSAttributedString,
            legendFrame: CGRect(x: legendRestPosition.x - label.frame.width / 2,
                                y: legendRestPosition.y - label.frame.height / 2,
                                width: label.frame.width, height: label.frame.height),
            legendAlignment: label.alignmentMode, rect: root.frame)
    }
    private var lastUsage: GrowthKeyboardKeyUsage?
    private var lastMaterialProgress: Double?
    private(set) var contentUpdates = 0
    private(set) var materialUpdates = 0
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = ","
        return formatter
    }()

    init(key: KeyboardKey, frame: CGRect, projection: EditorialDepthProjection, rowCenterY: CGFloat) {
        id = key.id
        root.frame = frame
        root.contentsScale = 2
        let geometry = KeyGeometry(width: frame.width, height: frame.height,
            depth: EditorialDepthStyle.height, sideOffset: EditorialDepthStyle.sideOffset)
        frontFace.path = geometry.front
        base.addSublayer(frontFace)
        base.path = geometry.base
        base.shadowPath = geometry.base
        base.shadowColor = rgb(0x222D34).cgColor
        base.shadowOpacity = EditorialDepthStyle.shadowOpacity
        base.shadowOffset = CGSize(width: 1.5, height: 3.5)
        base.shadowRadius = EditorialDepthStyle.shadowRadius
        rightWall.path = geometry.side
        bevel.path = geometry.top
        face.path = geometry.face
        face.strokeColor = rgb(0x364047).withAlphaComponent(0.13).cgColor
        face.lineWidth = 0.75
        highlight.path = geometry.highlight
        highlight.fillColor = nil
        highlight.lineWidth = 0.8
        highlight.lineCap = .round
        let labelText: String
        switch key.id {
        case "LeftShift", "RightShift": labelText = "⇧"
        case "Space": labelText = "space"
        case "Return": labelText = "↩"
        case "Left": labelText = "←"
        case "Right": labelText = "→"
        case "Up": labelText = "↑"
        case "Down": labelText = "↓"
        case "LeftCmd", "RightCmd": labelText = "⌘\ncommand"
        case "LeftOption", "RightOption": labelText = "⌥\noption"
        case "Ctrl": labelText = "⌃\ncontrol"
        case "Fn": labelText = "fn"
        case "Tab": labelText = "⇥"
        case "CapsLock": labelText = "⇪"
        case "Delete": labelText = "⌫"
        default: labelText = key.label
        }
        if LetterLegendStyle.applies(to: key.id) {
            label = LetterLegendStyle.make(key.id, keySize: frame.size)
        } else if ["Left", "Right", "Up", "Down"].contains(key.id) {
            label = centeredArrowLegend(labelText, keySize: frame.size)
        } else if labelText.contains("\n") {
            let modifier = ["LeftCmd", "RightCmd", "LeftOption", "RightOption", "Ctrl"].contains(key.id)
            label = DualLegendStyle.make(labelText, keySize: frame.size, modifier: modifier)
        } else {
            let compact = frame.height < 72
            let symbol = ["Left", "Right", "Up", "Down", "Return", "LeftShift", "RightShift",
                          "LeftCmd", "RightCmd", "LeftOption", "RightOption", "Ctrl",
                          "Tab", "CapsLock", "Delete"].contains(key.id)
            label = textLayer(labelText,
                frame: CGRect(x: 17, y: compact ? 5 : 14,
                    width: frame.width - 34, height: compact ? 20 : 34),
                size: compact ? 16 : symbol || key.id.count == 1 ? 26 : 17,
                weight: .regular, color: rgb(0x26333A))
        }
        legendRestPosition = label.position
        let compact = frame.height < 72
        count = textLayer("", frame: CGRect(x: 17, y: frame.height - (compact ? 20 : 31),
            width: frame.width - 28, height: compact ? 16 : 22),
            size: compact ? 11 : 13, color: rgb(0x33454F), mono: true)
        count.opacity = 0
        for layer in [base, rightWall, bevel, face, highlight, label, count] { root.addSublayer(layer) }
        root.name = key.id
        let scale = projection.scale(at: rowCenterY)
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        root.position = projection.point(CGPoint(x: frame.midX, y: frame.midY), rowCenterY: rowCenterY)
        label.setAffineTransform(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        count.setAffineTransform(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }

    func apply(_ sample: GrowthKeyboardKeyUsage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if sample != lastUsage {
            let value = Self.countFormatter.string(from: NSNumber(value: sample.count))!
            count.string = NSAttributedString(string: value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: root.bounds.height < 72 ? 11 : 13, weight: .regular),
                .foregroundColor: rgb(0x33454F)
            ])
            lastUsage = sample
            contentUpdates += 1
        }
        let p = sample.progress
        if lastMaterialProgress != p {
            let surface = EditorialKeyboardMaterial.color(p)
            base.fillColor = blend(surface, rgb(0x46535B), 0.25).cgColor
            frontFace.fillColor = blend(surface, rgb(0x46535B), 0.21).cgColor
            rightWall.fillColor = blend(surface, rgb(0x46535B), 0.30).cgColor
            bevel.fillColor = blend(surface, .white, 0.22).cgColor
            face.fillColor = surface.cgColor
            highlight.strokeColor = NSColor.white.withAlphaComponent(0.60).cgColor
            lastMaterialProgress = p
            materialUpdates += 1
        }
        CATransaction.commit()
    }

    func contains(_ point: CGPoint) -> Bool {
        let local = root.convert(point, from: root.superlayer)
        return bevel.path?.contains(local) ?? false
    }

    func setCountVisible(_ visible: Bool, animated: Bool) {
        let target: Float = visible ? 1 : 0
        guard count.opacity != target else {
            if !animated {
                count.removeAnimation(forKey: "countOpacity")
                label.removeAnimation(forKey: "legendLift")
            }
            return
        }
        let currentOpacity = count.presentation()?.opacity ?? count.opacity
        let currentLegendY = label.presentation()?.position.y ?? label.position.y
        let liftsLegend = LetterLegendStyle.applies(to: id) || ["Left", "Right", "Up", "Down"].contains(id)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        count.opacity = target
        count.removeAnimation(forKey: "countOpacity")
        label.removeAnimation(forKey: "legendLift")
        if liftsLegend {
            label.position.y = legendRestPosition.y - (visible ? LetterLegendStyle.hoverLift : 0)
        }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = currentOpacity
            fade.toValue = target
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            count.add(fade, forKey: "countOpacity")
            if liftsLegend {
                let lift = CABasicAnimation(keyPath: "position.y")
                lift.fromValue = currentLegendY
                lift.toValue = label.position.y
                lift.duration = fade.duration
                lift.timingFunction = fade.timingFunction
                label.add(lift, forKey: "legendLift")
            }
        }
        CATransaction.commit()
    }

}


/// Explicit read-only scene inputs, shared by the production 2.5D and 3D renderers.
/// No layer-index bridge, duplicated layout table or prototype dependency.
struct EditorialKeyboardSceneKey {
    let id: String
    let size: CGSize
    let topPath: CGPath
    let legend: NSAttributedString
    let legendFrame: CGRect
    let legendAlignment: CATextLayerAlignmentMode
    let rect: CGRect
}

struct EditorialKeyboardSceneLayout {
    let keys: [EditorialKeyboardSceneKey]
    let boardSize: CGSize
    let unit: CGFloat
    let deckColor: NSColor

    func usageColor(_ progress: Double) -> NSColor { EditorialKeyboardMaterial.color(progress) }
}

/// Static production renderer. Count/material updates never rebuild the layer tree.
/// The approved light ceramic material is intentional in both system appearances.
final class EditorialKeyboardRenderer: NSView {
    private let keyboard = CALayer()
    private let deck: EditorialDeck
    private let caps: [EditorialKeycap]
    private var usages: [String: GrowthKeyboardKeyUsage] = [:]
    private var pointerTracking: NSTrackingArea?
    private var lastLayoutSize = CGSize.zero
    private var hoveredID: String?
    private(set) var selectedKeyID: String?
    private(set) var geometryBuildCount = 0
    private(set) var dataUpdateCount = 0
    var onSelectionChanged: ((GrowthKeyboardKeyUsage?) -> Void)?

    var staticGeometryPaths: [CGPath] {
        deck.root.sublayers!.compactMap { ($0 as? CAShapeLayer)?.path } +
            caps.flatMap { $0.root.sublayers!.compactMap { ($0 as? CAShapeLayer)?.path } }
    }
    var keyIDs: [String] { caps.map(\.id) }
    var sceneLayout: EditorialKeyboardSceneLayout {
        EditorialKeyboardSceneLayout(keys: caps.map(\.sceneKey), boardSize: keyboard.bounds.size,
            unit: caps.first { $0.id == "A" }!.root.bounds.width, deckColor: deck.surfaceColor)
    }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        let definition = EditorialKeyboardGeometry.layout
        let unit: CGFloat = 96
        let placements: [(KeyboardKey, CGRect, CGFloat)] = definition.rows.flatMap { row in
            var cursor = row.startXUnits
            return row.keys.map { key in
                let x = key.xUnits.map { row.startXUnits + $0 } ?? cursor
                let rect = CGRect(x: CGFloat(x) * unit,
                    y: CGFloat(row.yUnits + key.yOffsetUnits) * unit,
                    width: CGFloat(key.widthUnits) * unit, height: CGFloat(key.heightUnits) * unit)
                cursor = x + key.widthUnits + definition.keySpacingUnits
                return (key, rect, CGFloat(row.yUnits + 0.5) * unit)
            }
        }
        let layoutBounds = placements.reduce(CGRect.null) { $0.union($1.1) }
        let projection = EditorialDepthProjection(bounds: layoutBounds)
        deck = EditorialDeck(projection: projection)
        caps = placements.map { EditorialKeycap(key: $0.0, frame: $0.1, projection: projection, rowCenterY: $0.2) }
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.isGeometryFlipped = true
        // Inherit the native window canvas instead of drawing a separate rectangle.
        root.backgroundColor = nil
        layer = root
        keyboard.bounds = layoutBounds
        keyboard.anchorPoint = .zero
        root.addSublayer(keyboard)
        deck.root.isHidden = false
        keyboard.addSublayer(deck.root)
        for cap in caps { keyboard.addSublayer(cap.root) }
        geometryBuildCount = caps.count + 1
        apply([])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(growthLocalized("growth.keyboard.description"))
        setAccessibilityHelp(growthLocalized("growth.keyboard.help"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let pointerTracking { removeTrackingArea(pointerTracking) } }

    override func layout() {
        super.layout()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        let board = keyboard.bounds
        let scale = max(0.01, min(0.75, (bounds.width - 44) / board.width, (bounds.height - 32) / board.height))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AppKit owns the backing layer frame in the parent view's coordinates.
        // Only position/scale our content layer in local bounds coordinates.
        keyboard.position = CGPoint(x: (bounds.width - board.width * scale) / 2,
                                    y: (bounds.height - board.height * scale) / 2)
        keyboard.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    func apply(_ values: [GrowthKeyboardKeyUsage]) {
        let incoming = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        guard incoming != usages || dataUpdateCount == 0 else { return }
        usages = incoming
        for cap in caps { cap.apply(incoming[cap.id] ?? .init(id: cap.id, count: 0)) }
        dataUpdateCount += 1
        notifySelection()
    }

    func selectKey(_ id: String?) {
        let selected = id.flatMap { keyIDs.contains($0) ? $0 : nil }
        guard selected != selectedKeyID else { return }
        selectedKeyID = selected
        refreshCounts(animated: true)
        notifySelection()
    }

    func clearHover() {
        hoveredID = nil
        refreshCounts(animated: false)
    }

    private func notifySelection() {
        let value = selectedKeyID.map { usages[$0] ?? .init(id: $0, count: 0) }
        onSelectionChanged?(value)
        if let value {
            setAccessibilityValue(String(format: growthLocalized("growth.key.accessibility"),
                value.id, value.count, value.progress * 100))
        } else { setAccessibilityValue(nil) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        pointerTracking = tracking
    }
    private func key(at point: CGPoint) -> String? {
        let local = keyboard.convert(point, from: layer)
        return caps.first { $0.contains(local) }?.id
    }
    private func hover(at point: CGPoint?) {
        let id = point.flatMap { key(at: $0) }
        guard id != hoveredID else { return }
        hoveredID = id
        refreshCounts(animated: true)
    }
    private func refreshCounts(animated: Bool) {
        for cap in caps { cap.setCountVisible(cap.id == hoveredID || cap.id == selectedKeyID, animated: animated) }
    }
    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { clearHover() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectKey(key(at: convert(event.locationInWindow, from: nil)))
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: window?.performClose(nil)
        case 123, 124, 125, 126:
            let current = selectedKeyID.flatMap { id in caps.firstIndex { $0.id == id } } ?? 0
            var target = current
            if event.keyCode == 123 { target = max(0, current - 1) }
            else if event.keyCode == 124 { target = min(caps.count - 1, current + 1) }
            else {
                let origin = caps[current].root.frame
                let candidates = caps.indices.filter {
                    event.keyCode == 125 ? caps[$0].root.frame.midY > origin.midY + 2
                        : caps[$0].root.frame.midY < origin.midY - 2
                }
                target = candidates.min {
                    let a = caps[$0].root.frame, b = caps[$1].root.frame
                    return abs(a.midY - origin.midY) * 100 + abs(a.midX - origin.midX) <
                        abs(b.midY - origin.midY) * 100 + abs(b.midX - origin.midX)
                } ?? current
            }
            selectKey(caps[target].id)
        default: super.keyDown(with: event)
        }
    }
}
