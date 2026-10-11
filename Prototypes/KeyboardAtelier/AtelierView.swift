import Cocoa
import UniformTypeIdentifiers

enum AtelierFinish: Int, CaseIterable {
    case porcelain, alloy, relief
    var name: String { L(["finish.porcelain", "finish.alloy", "finish.relief"][rawValue]) }
    var dark: Bool { self == .alloy }
    var background: NSColor { dark ? rgb(0x111820) : self == .relief ? rgb(0xEDF1F4) : rgb(0xF3F0E9) }
    var ink: NSColor { dark ? rgb(0xE5ECF2) : rgb(0x202B34) }
    var secondary: NSColor { dark ? rgb(0x91A2AE) : rgb(0x78828A) }
    var plate: NSColor { dark ? rgb(0x34434F) : self == .relief ? rgb(0xD5DFE6) : rgb(0xDCDDD8) }

    func color(_ progress: Double) -> NSColor {
        let stops: [(Double, NSColor)]
        switch self {
        case .porcelain:
            stops = [(0, rgb(0xF0F0EB)), (0.12, rgb(0xB4D3EB)), (0.28, rgb(0x609BC7)),
                     (0.42, rgb(0x347CA9)), (0.53, rgb(0xDDBF75)), (0.68, rgb(0xE6A34D)),
                     (0.84, rgb(0xDA7548)), (1, rgb(0xA64C32))]
        case .alloy:
            stops = [(0, rgb(0x3B4856)), (0.22, rgb(0x365778)), (0.43, rgb(0x508B9D)),
                     (0.60, rgb(0xC5A263)), (0.82, rgb(0xBA724A)), (1, rgb(0xDA9460))]
        case .relief:
            stops = [(0, rgb(0xF9FBFC)), (0.3, rgb(0xD6E2EC)), (0.58, rgb(0x9CB9CF)),
                     (0.80, rgb(0x457AA0)), (1, rgb(0x244F71))]
        }
        for index in 1..<stops.count where progress <= stops[index].0 {
            let (start, a) = stops[index - 1]
            let (end, b) = stops[index]
            return mix(a, b, (progress - start) / (end - start))
        }
        return stops.last!.1
    }
}

func rgb(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}
func mix(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    let t = CGFloat(max(0, min(1, t)))
    return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
        green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
        blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
}

final class AtelierView: NSView {
    static let designSize = NSSize(width: 1280, height: 890)
    var actual: AtelierDataset?
    var loadError: String?
    var dataset: AtelierDataset
    var finish: AtelierFinish = .porcelain
    private var isV2 = true
    private var showsUsageColor = true
    private lazy var spatial = PorcelainSceneRenderer()
    private let neutralButton = NSButton()
    private let sceneRect = CGRect(x: 24, y: 174, width: 1232, height: 548)
    private var hoveredID: String?
    private var pinnedID: String? = "Space"
    private var keyPaths: [(KeyboardKey, CGPath)] = []
    private var tracking: NSTrackingArea?
    private let finishes = NSSegmentedControl()
    private let stages = NSSegmentedControl()
    private let reloadButton = NSButton()
    private let saveButton = NSButton()
    private let pinLabel = NSTextField(labelWithString: "")
    private var viewScale: CGFloat { min(bounds.width / 1280, bounds.height / 890) }
    private let unit: CGFloat = 60
    private let boardWidth: CGFloat = 17.18 * 60
    private let boardHeight: CGFloat = 6.75 * 60
    var selectedKeyID: String { pinnedID ?? hoveredID ?? "Space" }

    init(actual: AtelierDataset?, error: String?) {
        self.actual = actual
        self.loadError = error
        self.dataset = actual ?? AtelierData.simulated(0)
        super.init(frame: NSRect(origin: .zero, size: Self.designSize))
        finishes.segmentCount = 2
        finishes.setLabel(L("version.v1"), forSegment: 0)
        finishes.setLabel(L("version.v2"), forSegment: 1)
        finishes.selectedSegment = 1
        finishes.segmentStyle = .rounded
        finishes.target = self
        finishes.action = #selector(changeFinish)
        stages.segmentCount = 4
        for (index, key) in ["mode.actual", "mode.low", "mode.medium", "mode.mature"].enumerated() {
            stages.setLabel(L(key), forSegment: index)
            stages.setWidth(105, forSegment: index)
        }
        stages.selectedSegment = actual == nil ? 1 : 0
        stages.segmentStyle = .rounded
        stages.target = self
        stages.action = #selector(changeStage)
        for (button, key, selector) in [(reloadButton, "action.reload", #selector(reloadData)),
                                       (saveButton, "action.save", #selector(saveImage))] {
            button.title = L(key)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.target = self
            button.action = selector
        }
        neutralButton.setButtonType(.switch)
        neutralButton.title = L("color.neutral")
        neutralButton.target = self
        neutralButton.action = #selector(changeColor)
        neutralButton.font = .systemFont(ofSize: 11)
        pinLabel.stringValue = L("hint.inspect")
        pinLabel.font = .systemFont(ofSize: 11)
        let controls: [NSView] = [finishes, stages, reloadButton, saveButton, pinLabel, neutralButton]
        for view in controls { addSubview(view) }
        setAccessibilityLabel(L("window.title"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let scale = viewScale
        func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
        }
        if isV2 {
            finishes.frame = frame(48, 121, 250, 29)
            neutralButton.frame = frame(328, 125, 190, 23)
            stages.frame = frame(575, 121, 440, 29)
            reloadButton.frame = frame(1030, 121, 88, 29)
            saveButton.frame = frame(1130, 121, 100, 29)
        } else {
            finishes.frame = frame(48, 213, 250, 31)
            neutralButton.frame = frame(328, 218, 200, 23)
            stages.frame = frame(800, 213, 430, 31)
            reloadButton.frame = frame(1035, 28, 92, 28)
            saveButton.frame = frame(1136, 28, 94, 28)
        }
        pinLabel.frame = frame(820, 727, 410, 22)
        pinLabel.textColor = finish.secondary
        pinLabel.alignment = .right
        for control in [finishes, stages, reloadButton, saveButton, neutralButton] {
            control.appearance = NSAppearance(named: finish.dark ? .darkAqua : .aqua)
        }
    }

    @objc private func changeFinish() {
        isV2 = finishes.selectedSegment == 1
        finish = .porcelain
        hoveredID = nil
        needsLayout = true
        needsDisplay = true
    }
    @objc private func changeColor() {
        showsUsageColor = neutralButton.state != .on
        needsDisplay = true
    }
    @objc private func changeStage() {
        let selection = stages.selectedSegment
        if selection == 0 {
            guard let actual else {
                let alert = NSAlert()
                alert.messageText = L("error.title")
                alert.informativeText = loadError ?? L("source.missing")
                alert.runModal()
                stages.selectedSegment = 1
                return
            }
            dataset = actual
        } else { dataset = AtelierData.simulated(selection - 1) }
        hoveredID = nil
        needsDisplay = true
    }
    @objc private func reloadData() {
        do {
            actual = try AtelierData.load()
            loadError = nil
            if stages.selectedSegment == 0 { dataset = actual! }
        } catch {
            loadError = error.localizedDescription
            let alert = NSAlert()
            alert.messageText = L("error.title")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        needsDisplay = true
    }
    @objc private func saveImage() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Keyboard-\(dataset.snapshot.dayKey).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try renderPNG(to: url) }
        catch { NSAlert(error: error).runModal() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.performClose(nil) }
        else { super.keyDown(with: event) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let designPoint = CGPoint(x: point.x / viewScale, y: point.y / viewScale)
        let id = keyID(at: designPoint)
        guard id != hoveredID else { return }
        hoveredID = id
        if id != nil { pinnedID = nil }
        pinLabel.stringValue = L(id == nil ? "hint.inspect" : "hint.pin")
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        if hoveredID != nil { hoveredID = nil; needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let designPoint = CGPoint(x: point.x / viewScale, y: point.y / viewScale)
        if let id = keyID(at: designPoint) {
            pinnedID = id
            pinLabel.stringValue = L("hint.pinned")
            needsDisplay = true
        }
    }

    private func keyID(at point: CGPoint) -> String? {
        guard isV2 else { return keyPaths.last { $0.1.contains(point) }?.0.id }
        guard sceneRect.contains(point) else { return nil }
        let canvas = PorcelainSceneRenderer.canvasSize
        // SCNRenderer uses a bottom-left viewport; this NSView is flipped.
        return spatial.keyID(at: CGPoint(x: (point.x - sceneRect.minX) / sceneRect.width * canvas.width,
            y: (sceneRect.maxY - point.y) / sceneRect.height * canvas.height))
    }

    /// Prototype visual projection only. Layout IDs, widths and row placement are shared.
    private func project(_ point: CGPoint) -> CGPoint {
        let pitch: CGFloat = 0.86
        let factor = 0.94 + 0.06 * point.y / boardHeight
        let skew: CGFloat = finish == .relief ? 0 : 0.026
        return CGPoint(x: 123 + boardWidth / 2 + (point.x - boardWidth / 2) * factor
                       + (boardHeight - point.y) * skew,
                       y: 316 + point.y * pitch)
    }
    private func projectPath(_ path: CGPath) -> CGPath {
        let result = CGMutablePath()
        path.applyWithBlock { element in
            let e = element.pointee, p = e.points
            switch e.type {
            case .moveToPoint: result.move(to: self.project(p[0]))
            case .addLineToPoint: result.addLine(to: self.project(p[0]))
            case .addQuadCurveToPoint: result.addQuadCurve(to: self.project(p[1]), control: self.project(p[0]))
            case .addCurveToPoint: result.addCurve(to: self.project(p[2]),
                control1: self.project(p[0]), control2: self.project(p[1]))
            case .closeSubpath: result.closeSubpath()
            @unknown default: break
            }
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if isV2 {
            let image = spatial.render(dataset: dataset, neutral: !showsUsageColor)
            spatial.background.setFill()
            bounds.fill()
            context.saveGState()
            context.scaleBy(x: viewScale, y: viewScale)
            // Extend a uniform patch of the same rendered ground. Both draws
            // follow NSImage's color profile, avoiding a visible rectangular mat.
            image.draw(in: CGRect(origin: .zero, size: Self.designSize),
                from: CGRect(x: 0, y: image.size.height / 2, width: 8, height: 8),
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            image.draw(in: sceneRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            drawQuietHeader(context)
            drawQuietInspector(context)
            context.restoreGState()
        } else {
            finish.background.setFill()
            bounds.fill()
            context.saveGState()
            context.scaleBy(x: viewScale, y: viewScale)
            drawHeader(context)
            drawBoard(context)
            drawInspector(context)
            context.restoreGState()
        }
    }

    private func drawQuietHeader(_ c: CGContext) {
        text("Keyboard Atelier", CGRect(x: 48, y: 32, width: 500, height: 28),
             font: .systemFont(ofSize: 19, weight: .medium), color: finish.ink)
        let day = dataset.dayIndex.map { "Day \($0)" } ?? L("day.none")
        let info = "\(dataset.snapshot.dayKey)   /   \(day)   /   " +
            (dataset.isSimulated ? L("badge.simulated") : L("badge.actual"))
        text(info, CGRect(x: 49, y: 70, width: 830, height: 24),
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: finish.secondary)
        text(L("metric.total"), CGRect(x: 950, y: 30, width: 280, height: 18),
             font: .systemFont(ofSize: 10), color: finish.secondary, alignment: .right)
        text(grouped(dataset.snapshot.totalKeyPresses), CGRect(x: 925, y: 52, width: 305, height: 40),
             font: .monospacedDigitSystemFont(ofSize: 28, weight: .regular), color: finish.ink, alignment: .right)
    }

    private func drawQuietInspector(_ c: CGContext) {
        text(dataset.sourceNote, CGRect(x: 50, y: 727, width: 740, height: 23),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        c.setStrokeColor(finish.secondary.withAlphaComponent(0.24).cgColor)
        c.setLineWidth(0.7)
        c.move(to: CGPoint(x: 48, y: 766)); c.addLine(to: CGPoint(x: 1232, y: 766)); c.strokePath()
        let key = KeyboardLayout.macStyle.keys.first { $0.id == selectedKeyID }!
        let count = dataset.count(for: key)
        let progress = KeyboardUsageProgress.progress(for: count)
        text(key.id, CGRect(x: 50, y: 789, width: 160, height: 32),
             font: .systemFont(ofSize: 21, weight: .regular), color: finish.ink)
        text(L("metric.keycount"), CGRect(x: 265, y: 781, width: 235, height: 18),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        text(grouped(count), CGRect(x: 265, y: 804, width: 200, height: 28),
             font: .monospacedDigitSystemFont(ofSize: 19, weight: .regular), color: finish.ink)
        text(L("metric.progress"), CGRect(x: 563, y: 781, width: 245, height: 18),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        text(String(format: "%.3f", progress), CGRect(x: 563, y: 804, width: 100, height: 28),
             font: .monospacedDigitSystemFont(ofSize: 19, weight: .regular), color: finish.ink)
        text(L(showsUsageColor ? "geometry.caption" : "geometry.neutral"),
             CGRect(x: 825, y: 789, width: 405, height: 40),
             font: .systemFont(ofSize: 11), color: finish.secondary)
        text(String(format: L("footer.unsupported"), dataset.physical.unsupported.count),
             CGRect(x: 50, y: 855, width: 920, height: 22),
             font: .systemFont(ofSize: 9), color: finish.secondary)
        text("PORCELAIN / v2", CGRect(x: 1010, y: 855, width: 220, height: 20),
             font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular), color: finish.secondary, alignment: .right)
    }

    private func drawHeader(_ c: CGContext) {
        text("KEYSTATS  /  KEYBOARD ATELIER", CGRect(x: 48, y: 34, width: 500, height: 25),
             font: .systemFont(ofSize: 11, weight: .semibold), color: finish.secondary)
        text(L("headline"), CGRect(x: 48, y: 73, width: 800, height: 65),
             font: .systemFont(ofSize: 44, weight: .semibold), color: finish.ink)
        text(L("subheading"), CGRect(x: 50, y: 143, width: 775, height: 25),
             font: .systemFont(ofSize: 13), color: finish.secondary)
        text(L("metric.total"), CGRect(x: 952, y: 80, width: 278, height: 22),
             font: .systemFont(ofSize: 11, weight: .medium), color: finish.secondary, alignment: .right)
        text(grouped(dataset.snapshot.totalKeyPresses), CGRect(x: 925, y: 105, width: 305, height: 54),
             font: .monospacedDigitSystemFont(ofSize: 39, weight: .medium),
             color: finish.ink, alignment: .right)
        let day = dataset.dayIndex.map { "DAY \($0)" } ?? L("day.none")
        let info = "\(dataset.snapshot.dayKey)     ·     \(day)     ·     " +
            (dataset.isSimulated ? L("badge.simulated") : L("badge.actual"))
        text(info, CGRect(x: 50, y: 176, width: 920, height: 24),
             font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium), color: finish.secondary)
        c.setStrokeColor(finish.secondary.withAlphaComponent(0.18).cgColor)
        c.setLineWidth(1)
        c.move(to: CGPoint(x: 48, y: 265)); c.addLine(to: CGPoint(x: 1232, y: 265)); c.strokePath()
        text(L(["direction.porcelain", "direction.alloy", "direction.relief"][finish.rawValue]),
             CGRect(x: 50, y: 282, width: 770, height: 24),
             font: .systemFont(ofSize: 11), color: finish.secondary)
        text("v1",
             CGRect(x: 1150, y: 282, width: 80, height: 24),
             font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: finish.secondary, alignment: .right)
    }

    private func drawBoard(_ c: CGContext) {
        keyPaths = []
        let baseRect = CGRect(x: -26, y: -20, width: boardWidth + 52, height: boardHeight + 40)
        let top = projectPath(CGPath(roundedRect: baseRect, cornerWidth: 17, cornerHeight: 17, transform: nil))
        var offset = CGAffineTransform(translationX: 0, y: finish == .relief ? 8 : 18)
        let bottom = top.copy(using: &offset)!
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 22), blur: 24,
                    color: NSColor.black.withAlphaComponent(finish.dark ? 0.55 : 0.20).cgColor)
        c.setFillColor(mix(finish.plate, .black, 0.29).cgColor)
        c.addPath(bottom); c.fillPath()
        c.restoreGState()
        gradient(c, path: bottom, from: mix(finish.plate, .white, 0.02),
                 to: mix(finish.plate, .black, 0.22))
        gradient(c, path: top, from: mix(finish.plate, .white, 0.48),
                 to: mix(finish.plate, .black, 0.02))
        c.addPath(top)
        c.setStrokeColor(NSColor.white.withAlphaComponent(finish.dark ? 0.22 : 0.75).cgColor)
        c.setLineWidth(1.3); c.strokePath()

        for row in KeyboardLayout.macStyle.rows {
            var x = row.startXUnits
            for key in row.keys {
                let keyX = key.xUnits.map { row.startXUnits + $0 } ?? x
                let rect = CGRect(x: CGFloat(keyX) * unit, y: CGFloat(row.yUnits + key.yOffsetUnits) * unit,
                                  width: CGFloat(key.widthUnits) * unit, height: CGFloat(key.heightUnits) * unit)
                drawKey(key, rect: rect, context: c)
                x = keyX + key.widthUnits + KeyboardLayout.macStyle.keySpacingUnits
            }
        }
        text("KEYSTATS   •   PERSONAL EDITION", CGRect(x: 137, y: 690, width: 420, height: 18),
             font: .systemFont(ofSize: 8, weight: .medium),
             color: finish.secondary.withAlphaComponent(0.7))
        drawLegend(c)
    }

    private func drawKey(_ key: KeyboardKey, rect: CGRect, context c: CGContext) {
        let count = dataset.count(for: key)
        let progress = KeyboardUsageProgress.progress(for: count)
        let surface = finish.color(showsUsageColor ? progress : 0)
        let radius: CGFloat = finish == .relief ? 4.5 : 7
        let face = projectPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        keyPaths.append((key, face))
        let depth: CGFloat = finish == .relief ? 3.5 : 7.5
        var transform = CGAffineTransform(translationX: 0.6, y: depth)
        let side = face.copy(using: &transform)!
        c.saveGState()
        c.setShadow(offset: CGSize(width: 1, height: 3), blur: 3.5,
                    color: NSColor.black.withAlphaComponent(finish.dark ? 0.75 : 0.24).cgColor)
        c.setFillColor(mix(surface, .black, finish.dark ? 0.42 : 0.28).cgColor)
        c.addPath(side); c.fillPath()
        c.restoreGState()
        gradient(c, path: side, from: mix(surface, .black, 0.14), to: mix(surface, .black, 0.38))
        gradient(c, path: face, from: mix(surface, .white, finish.dark ? 0.13 : 0.27),
                 to: mix(surface, .black, finish == .relief ? 0.015 : 0.045))
        c.addPath(face)
        c.setStrokeColor(mix(surface, .white, 0.48).cgColor)
        c.setLineWidth(0.9); c.strokePath()

        let inset = rect.insetBy(dx: 3, dy: 3)
        let inner = projectPath(CGPath(roundedRect: inset, cornerWidth: radius - 1,
                                      cornerHeight: radius - 1, transform: nil))
        c.saveGState()
        c.addPath(inner); c.clip()
        let start = project(CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY - 15))
        let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [NSColor.white.withAlphaComponent(finish == .porcelain ? 0.32 : 0.08).cgColor,
                     NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 1])!
        c.drawRadialGradient(gloss, startCenter: start, startRadius: 0,
            endCenter: start, endRadius: rect.width * 0.8 + 15, options: [])
        c.restoreGState()

        // Deterministic, faint ceramic grain. Static drawing, never a noise animation.
        if finish == .porcelain {
            c.saveGState()
            c.addPath(inner); c.clip()
            c.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
            for i in 0..<14 {
                let px = rect.minX + CGFloat((i * 17 + key.id.utf8.reduce(0, { $0 + Int($1) })) % 53) / 53 * rect.width
                let py = rect.minY + CGFloat((i * 23) % 47) / 47 * rect.height
                let p = project(CGPoint(x: px, y: py))
                c.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 0.8, height: 0.8))
            }
            c.restoreGState()
        }
        if key.id == selectedKeyID {
            c.addPath(face)
            c.setStrokeColor(finish.dark ? rgb(0xE4BF78).cgColor : rgb(0x426E87).withAlphaComponent(0.7).cgColor)
            c.setLineWidth(1.5); c.strokePath()
        }

        let lightInk = showsUsageColor && (finish.dark || (finish == .porcelain && progress > 0.24 && progress < 0.47)
                        || (finish == .relief && progress > 0.75))
        let ink = lightInk ? rgb(0xFAFCFD) : rgb(0x263642)
        let projected = project(CGPoint(x: rect.minX, y: rect.minY))
        c.saveGState()
        c.translateBy(x: projected.x, y: projected.y)
        let pitch: CGFloat = 0.86
        let factor = 0.94 + 0.06 * rect.midY / boardHeight
        c.scaleBy(x: factor, y: pitch)
        let label = legend(for: key)
        if rect.height < 40 {
            text(label, CGRect(x: 8, y: 4, width: rect.width * 0.44, height: 20),
                 font: .systemFont(ofSize: 11, weight: .medium), color: ink)
            text(compact(count), CGRect(x: rect.width * 0.40, y: 5, width: rect.width * 0.52, height: 18),
                 font: .monospacedDigitSystemFont(ofSize: 8, weight: .medium),
                 color: ink.withAlphaComponent(0.78), alignment: .right)
        } else {
            text(label, CGRect(x: 10, y: 7, width: rect.width - 18, height: 23),
                 font: .systemFont(ofSize: label.count > 6 ? 11 : 15, weight: .medium), color: ink)
            text(compact(count), CGRect(x: 10, y: rect.height - 21, width: rect.width - 19, height: 17),
                 font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
                 color: ink.withAlphaComponent(0.70), alignment: .right)
        }
        c.restoreGState()
    }

    private func legend(for key: KeyboardKey) -> String {
        switch key.symbolName {
        case "command": return "⌘"
        case "option": return "⌥"
        case "shift": return "⇧"
        case "control": return "⌃"
        case "globe": return "fn"
        default:
            if key.id == "Space" { return "space" }
            return key.label.components(separatedBy: "\n").last ?? key.label
        }
    }
    private func drawLegend(_ c: CGContext) {
        guard showsUsageColor else { return }
        let x: CGFloat = 833, y: CGFloat = 687
        for i in 0..<205 {
            c.setFillColor(finish.color(Double(i) / 204).cgColor)
            c.fill(CGRect(x: x + CGFloat(i), y: y, width: 1.2, height: 4))
        }
        text(L("legend.new"), CGRect(x: x, y: y + 11, width: 100, height: 20),
             font: .systemFont(ofSize: 9), color: finish.secondary)
        text(L("legend.worn"), CGRect(x: x + 106, y: y + 11, width: 100, height: 20),
             font: .systemFont(ofSize: 9), color: finish.secondary, alignment: .right)
        text("0 → 1", CGRect(x: 1055, y: y - 5, width: 82, height: 20),
             font: .monospacedDigitSystemFont(ofSize: 10, weight: .regular), color: finish.secondary)
    }

    private func drawInspector(_ c: CGContext) {
        text(dataset.sourceNote, CGRect(x: 50, y: 727, width: 725, height: 23),
             font: .systemFont(ofSize: 11), color: finish.secondary)
        let panel = CGRect(x: 48, y: 764, width: 1184, height: 78)
        let path = CGPath(roundedRect: panel, cornerWidth: 12, cornerHeight: 12, transform: nil)
        c.addPath(path)
        c.setFillColor((finish.dark ? rgb(0x202C36) : NSColor.white.withAlphaComponent(0.53)).cgColor)
        c.fillPath()
        let key = KeyboardLayout.macStyle.keys.first { $0.id == selectedKeyID }!
        let count = dataset.count(for: key)
        let p = KeyboardUsageProgress.progress(for: count)
        text(key.id, CGRect(x: 70, y: 781, width: 175, height: 34),
             font: .systemFont(ofSize: 24, weight: .medium), color: finish.ink)
        text(L("metric.keycount"), CGRect(x: 271, y: 779, width: 230, height: 18),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        text(grouped(count), CGRect(x: 271, y: 800, width: 220, height: 31),
             font: .monospacedDigitSystemFont(ofSize: 21, weight: .medium), color: finish.ink)
        text(L("metric.progress"), CGRect(x: 565, y: 779, width: 270, height: 19),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        text(String(format: "%.3f", p), CGRect(x: 565, y: 801, width: 100, height: 30),
             font: .monospacedDigitSystemFont(ofSize: 21, weight: .medium), color: finish.ink)
        let rail = CGRect(x: 680, y: 810, width: 226, height: 5)
        c.setFillColor(finish.secondary.withAlphaComponent(0.2).cgColor); c.fill(rail)
        c.setFillColor(finish.color(p).cgColor)
        c.fill(CGRect(x: rail.minX, y: rail.minY, width: rail.width * CGFloat(p), height: rail.height))
        text(L("inspector.explanation"), CGRect(x: 960, y: 780, width: 248, height: 49),
             font: .systemFont(ofSize: 10.5), color: finish.secondary)
        let excluded = String(format: L("footer.unsupported"), dataset.physical.unsupported.count)
        text(excluded, CGRect(x: 50, y: 855, width: 920, height: 22),
             font: .systemFont(ofSize: 10), color: finish.secondary)
        text("NATIVE STUDY  /  v0.1", CGRect(x: 985, y: 855, width: 246, height: 22),
             font: .monospacedDigitSystemFont(ofSize: 9, weight: .regular), color: finish.secondary, alignment: .right)
    }

    private func text(_ value: String, _ rect: CGRect, font: NSFont, color: NSColor,
                      alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: rect,
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func gradient(_ c: CGContext, path: CGPath, from: NSColor, to: NSColor) {
        c.saveGState()
        c.addPath(path); c.clip()
        let bounds = path.boundingBoxOfPath
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [from.cgColor, to.cgColor] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.minY),
                             end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
        c.restoreGState()
    }

    func setPreview(version: Int, stage: Int, neutral: Bool = false) {
        self.finish = .porcelain
        isV2 = version == 1
        showsUsageColor = !neutral
        neutralButton.state = neutral ? .on : .off
        finishes.selectedSegment = version
        stages.selectedSegment = stage
        dataset = stage == 0 ? actual ?? AtelierData.simulated(0) : AtelierData.simulated(stage - 1)
        needsLayout = true
        needsDisplay = true
    }
    func renderPNG(to url: URL) throws {
        layoutSubtreeIfNeeded()
        displayIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
