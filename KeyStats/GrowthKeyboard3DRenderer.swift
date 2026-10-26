import Cocoa
import QuartzCore

/// Static SceneKit images with a three-frame LRU. Hover/count layers never invoke
/// SceneKit. Date scrubbing is coalesced; hiding cancels work before it can render.
final class GrowthKeyboard3DRenderer: NSView {
    typealias RenderFrame = ([GrowthKeyboardKeyUsage], NSColor) -> GrowthKeyboard3DFrame
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private struct CacheKey: Equatable {
        let values: [GrowthKeyboardKeyUsage]
        let background: NSColor
    }
    private struct CachedFrame {
        let key: CacheKey
        let frame: GrowthKeyboard3DFrame
    }
    let sceneLayout: EditorialKeyboardSceneLayout
    private let renderFrame: RenderFrame?
    private let schedule: Schedule
    private let imageSize: CGSize
    private let bakesLegends: Bool
    private var scene: GrowthKeyboard3DScene?
    private var cache: [CachedFrame] = []
    private var currentKey: CacheKey?
    private var values: [GrowthKeyboardKeyUsage] = []
    private var requestedValues: [GrowthKeyboardKeyUsage] = []
    private var onPresented: (() -> Void)?
    private var animatesPresentation = false
    private var cancelPending: (() -> Void)?
    private var generation = 0
    private let overlay = CALayer()
    private var legends: [String: CATextLayer] = [:]
    private var counts: [String: CATextLayer] = [:]
    private var tracking: NSTrackingArea?
    private var hoveredID: String?
    private(set) var selectedKeyID: String?
    private(set) var displayedFrame: GrowthKeyboard3DFrame?
    private(set) var isActive = false
    private(set) var renderCount = 0
    var cachedFrameCount: Int { cache.count }
    var hasScheduledRender: Bool { cancelPending != nil }
    var onSelectionChanged: ((GrowthKeyboardKeyUsage?) -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(layout: EditorialKeyboardSceneLayout, renderFrame: RenderFrame? = nil,
         imageSize: CGSize = GrowthKeyboard3DScene.size, bakesLegends: Bool = false,
         schedule: @escaping Schedule = GrowthKeyboard3DRenderer.scheduleOnMain) {
        sceneLayout = layout
        self.renderFrame = renderFrame
        self.schedule = schedule
        self.imageSize = imageSize
        self.bakesLegends = bakesLegends
        super.init(frame: .zero)
        wantsLayer = true
        layer?.isGeometryFlipped = true
        overlay.anchorPoint = .zero
        overlay.isHidden = true
        overlay.bounds = CGRect(origin: .zero, size: imageSize)
        layer?.addSublayer(overlay)
        for key in layout.keys {
            let legend = CATextLayer()
            legend.string = key.legend
            legend.isHidden = bakesLegends
            legend.contentsScale = 2
            legend.alignmentMode = key.legendAlignment
            legend.bounds = CGRect(origin: .zero, size: key.legendFrame.size)
            overlay.addSublayer(legend); legends[key.id] = legend
            let count = CATextLayer()
            count.contentsScale = 2; count.alignmentMode = .center
            count.opacity = 0
            overlay.addSublayer(count); counts[key.id] = count
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(NSLocalizedString("growth.mode.3d.description", comment: "3D Growth"))
        setAccessibilityHelp(NSLocalizedString("growth.keyboard.help", comment: "Growth Keyboard"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { cancelPending?() }

    func apply(_ incoming: [GrowthKeyboardKeyUsage], animated: Bool = false, onPresented: (() -> Void)? = nil) {
        let byID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
        requestedValues = sceneLayout.keys.map { byID[$0.id] ?? .init(id: $0.id, count: 0) }
        self.onPresented = onPresented
        animatesPresentation = animated
        requestFrame()
        if displayedFrame == nil { notifySelection() }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active { requestFrame() }
        else {
            // Keep the latest snapshot acknowledgement for reactivation. Cancelling
            // work must not leave its date/details behind when that image resumes.
            cancelRender()
            layer?.removeAnimation(forKey: "growthReplayFrame")
            clearHover()
        }
    }

    private func cancelRender() {
        generation &+= 1
        cancelPending?(); cancelPending = nil
    }

    private func requestFrame() {
        guard isActive, !requestedValues.isEmpty else { return }
        let background = KeyboardVisualizationCanvasView.backgroundColor(for: effectiveAppearance, showsGrowth: true)
        let key = CacheKey(values: requestedValues, background: background)
        cancelRender()
        guard key != currentKey else { completePresentation(); return }
        if let index = cache.firstIndex(where: { $0.key == key }) {
            let cached = cache.remove(at: index)
            cache.append(cached)
            present(cached.frame, key: key)
            return
        }
        // Replay keeps the previous image/counts until the next frame is ready;
        // the controller commits its date label in the same presentation callback.
        let token = generation
        cancelPending = schedule(0.08) { [weak self] in
            guard let self, self.isActive, self.generation == token else { return }
            self.cancelPending = nil
            let frame: GrowthKeyboard3DFrame
            if let renderFrame = self.renderFrame { frame = renderFrame(key.values, key.background) }
            else {
                if self.scene == nil { self.scene = GrowthKeyboard3DScene(self.sceneLayout) }
                frame = self.scene!.render(values: key.values, backgroundColor: key.background)
            }
            self.renderCount += 1
            self.cache.append(CachedFrame(key: key, frame: frame))
            if self.cache.count > 3 { self.cache.removeFirst() }
            self.present(frame, key: key)
        }
    }

    private func present(_ frame: GrowthKeyboard3DFrame, key: CacheKey) {
        if animatesPresentation && displayedFrame != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CATransition()
            transition.type = .fade; transition.duration = 0.12
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "growthReplayFrame")
        }
        values = key.values
        displayedFrame = frame; currentKey = key
        overlay.isHidden = false
        hoveredID = nil
        updateOverlay()
        notifySelection()
        needsDisplay = true
        completePresentation()
    }

    private func completePresentation() {
        let completion = onPresented
        onPresented = nil
        completion?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        requestFrame()
    }

    private var imageRect: CGRect {
        let size = imageSize
        let scale = max(0.01, min((bounds.width - 24) / size.width, (bounds.height - 16) / size.height))
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }
    override func layout() {
        super.layout()
        let rect = imageRect, scale = rect.width / imageSize.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        overlay.position = rect.origin
        overlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
    override func draw(_ dirtyRect: NSRect) {
        displayedFrame?.image.draw(in: imageRect, from: .zero, operation: .sourceOver,
            fraction: 1, respectFlipped: true, hints: nil)
    }

    private func updateOverlay() {
        guard let frame = displayedFrame else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (key, usage) in zip(sceneLayout.keys, values) {
            guard let rect = frame.rects[key.id], let legend = legends[key.id], let count = counts[key.id] else { continue }
            legend.isHidden = bakesLegends
            let scale = rect.width / key.size.width
            let showCount = key.id == hoveredID || key.id == selectedKeyID
            legend.position = CGPoint(x: rect.minX + key.legendFrame.midX * scale,
                y: rect.midY + (key.legendFrame.midY - key.size.height / 2) * scale - (showCount ? 6 * scale : 0))
            let legendScale = scale * key.size.width / key.rect.width
            legend.setAffineTransform(CGAffineTransform(scaleX: legendScale, y: legendScale))
            count.frame = CGRect(x: rect.minX, y: rect.maxY - (key.size.height < 72 ? 15 : 23) * scale,
                width: rect.width, height: (key.size.height < 72 ? 13 : 19) * scale)
            count.string = NSAttributedString(string: NumberFormatter.localizedString(from: NSNumber(value: usage.count), number: .decimal),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: (key.size.height < 72 ? 11 : 13) * scale, weight: .regular),
                             .foregroundColor: NSColor(srgbRed: 51/255, green: 69/255, blue: 79/255, alpha: 1)])
            count.opacity = showCount ? 1 : 0
        }
        CATransaction.commit()
    }

    func selectKey(_ id: String?) {
        selectedKeyID = id.flatMap { candidate in sceneLayout.keys.contains { $0.id == candidate } ? candidate : nil }
        updateOverlay(); notifySelection()
    }
    func clearHover() { hoveredID = nil; updateOverlay() }
    private func notifySelection() {
        let detailValues = displayedFrame == nil ? requestedValues : values
        let selected = selectedKeyID.flatMap { id in detailValues.first { $0.id == id } }
        onSelectionChanged?(selected)
        setAccessibilityValue(selected.map { String(format: NSLocalizedString("growth.key.accessibility", comment: "Growth Keyboard"),
            $0.id, $0.count, $0.progress * 100) })
    }
    func keyID(at point: CGPoint) -> String? {
        guard let frame = displayedFrame, imageRect.contains(point) else { return nil }
        let scale = imageRect.width / imageSize.width
        let local = CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
        return sceneLayout.keys.reversed().first { frame.rects[$0.id]?.contains(local) == true }?.id
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseMoved(with event: NSEvent) {
        let id = keyID(at: convert(event.locationInWindow, from: nil))
        if id != hoveredID { hoveredID = id; updateOverlay() }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { clearHover() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selectKey(keyID(at: convert(event.locationInWindow, from: nil)))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.performClose(nil) }
        else if [123, 124, 125, 126].contains(event.keyCode) {
            let keys = sceneLayout.keys
            let index = selectedKeyID.flatMap { id in keys.firstIndex { $0.id == id } } ?? 0
            let origin = keys[index].rect
            let target: Int
            if event.keyCode == 123 { target = max(0, index - 1) }
            else if event.keyCode == 124 { target = min(keys.count - 1, index + 1) }
            else {
                let candidates = keys.indices.filter {
                    event.keyCode == 125 ? keys[$0].rect.midY > origin.midY + 2 : keys[$0].rect.midY < origin.midY - 2
                }
                target = candidates.min {
                    let a = keys[$0].rect, b = keys[$1].rect
                    return abs(a.midY - origin.midY) * 100 + abs(a.midX - origin.midX) <
                        abs(b.midY - origin.midY) * 100 + abs(b.midX - origin.midX)
                } ?? index
            }
            selectKey(keys[target].id)
        } else { super.keyDown(with: event) }
    }
    private static func scheduleOnMain(_ delay: TimeInterval, _ action: @escaping () -> Void) -> (() -> Void) {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}
