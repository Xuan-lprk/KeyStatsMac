import Cocoa
import MetalKit

/// Only currently animating virtual clicks. No statistics or input history.
struct MechanicalFullPressState {
    private struct Impulse { let began: Double; let initial: Double }
    let supported: Set<String>
    private var active: [String: Impulse] = [:]
    var activeCount: Int { active.count }
    var profile = MechanicalPressProfile.deep
    mutating func press(_ id: String, at time: Double) {
        guard supported.contains(id) else { return }
        let initial = active[id].map { profile.weight(time - $0.began, initial: $0.initial) } ?? 0
        active[id] = Impulse(began: time, initial: initial)
    }
    mutating func offsets(at time: Double, reduceMotion: Bool = false) -> [String: CGFloat] {
        active = active.filter { time - $0.value.began < profile.duration }
        return active.mapValues { profile.travel * (reduceMotion ? 0.5 : 1) * profile.weight(time - $0.began, initial: $0.initial) }
    }
    mutating func cancel() { active.removeAll() }
}

final class KeyboardLegendOverlay: NSView {
    let model: MechanicalKeyboardScene
    var pixelScale: CGFloat = 1
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    init(model: MechanicalKeyboardScene) {
        self.model = model
        super.init(frame: CGRect(origin: .zero, size: MechanicalKeyboardScene.size))
    }
    required init?(coder: NSCoder) { fatalError() }
    private static let functionSymbols = ["sun.min", "sun.max", "rectangle.3.group", "magnifyingglass",
        "mic", "moon", "backward.fill", "playpause.fill", "forward.fill", "speaker.slash.fill",
        "speaker.wave.1.fill", "speaker.wave.3.fill"]
    private static let symbols: [String: NSImage] = Dictionary(uniqueKeysWithValues:
        (functionSymbols + ["globe"]).compactMap { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil).map { (name, $0) }
        })

    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor(srgbRed: 0.20, green: 0.27, blue: 0.31, alpha: 1)
        func text(_ value: String, at point: CGPoint, size: CGFloat, alignment: NSTextAlignment = .center) {
            let label = NSAttributedString(string: value, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .regular), .foregroundColor: ink])
            let measured = label.size()
            let x = alignment == .left ? point.x : alignment == .right ? point.x - measured.width : point.x - measured.width / 2
            label.draw(at: CGPoint(x: x, y: point.y - measured.height / 2))
        }
        func symbol(_ name: String, in rect: CGRect) {
            Self.symbols[name]?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85,
                                     respectFlipped: true, hints: nil)
        }
        for key in model.keys {
            guard key.id != "Space" else { continue }
            let rect = model.legendRect(for: key, pixelScale: pixelScale)
            let unit = min(rect.width, rect.height)
            let font = min(18, unit * (["Up", "Down"].contains(key.id) ? 0.60 : 0.34))
            let padding = max(3, unit * 0.10)
            let bottom = rect.maxY - padding - font * 0.4
            if key.id.hasPrefix("F"), let index = Int(key.id.dropFirst()), (1...12).contains(index) {
                let side = min(16, unit * 0.30)
                symbol(Self.functionSymbols[index - 1],
                       in: CGRect(x: rect.midX - side / 2, y: rect.midY - side * 0.9, width: side, height: side))
                text(key.id, at: CGPoint(x: rect.midX, y: bottom), size: min(9, unit * 0.19))
            } else if let glyph = ["Esc": "esc", "Tab": "⇥", "CapsLock": "⇪", "LeftShift": "⇧",
                                    "Delete": "⌫", "Return": "↩", "RightShift": "⇧"][key.id] {
                let right = ["Delete", "Return", "RightShift"].contains(key.id)
                text(glyph, at: CGPoint(x: right ? rect.maxX - padding : rect.minX + padding, y: bottom),
                     size: key.id == "Esc" ? min(11, unit * 0.23) : font,
                     alignment: right ? .right : .left)
                if key.id == "CapsLock" {
                    ink.withAlphaComponent(0.45).setFill()
                    NSBezierPath(ovalIn: CGRect(x: rect.minX + padding, y: rect.minY + padding, width: 2.5, height: 2.5)).fill()
                }
            } else if key.id == "Fn" {
                let side = min(13, unit * 0.25)
                symbol("globe", in: CGRect(x: rect.minX + padding, y: bottom - side / 2, width: side, height: side))
                text("fn", at: CGPoint(x: rect.maxX - padding, y: bottom), size: min(10, unit * 0.22), alignment: .right)
            } else if let pair = ["Ctrl": ("⌃", "control"), "LeftOption": ("⌥", "option"),
                                  "RightOption": ("⌥", "option"), "LeftCmd": ("⌘", "command"),
                                  "RightCmd": ("⌘", "command")][key.id] {
                let right = key.id.hasPrefix("Right")
                text(pair.0, at: CGPoint(x: right ? rect.maxX - padding : rect.minX + padding,
                                        y: rect.minY + padding + font / 2),
                     size: font * 0.85, alignment: right ? .right : .left)
                text(pair.1, at: CGPoint(x: rect.midX, y: bottom), size: min(10, unit * 0.21))
            } else {
                let lines = key.legend.string.components(separatedBy: "\n")
                if lines.count == 2 {
                    text(lines[0], at: CGPoint(x: rect.midX, y: rect.midY - unit * 0.18), size: font * 0.76)
                    text(lines[1], at: CGPoint(x: rect.midX, y: rect.midY + unit * 0.17), size: font * 0.90)
                } else {
                    text(key.legend.string, at: CGPoint(x: rect.midX, y: rect.midY), size: font)
                    if key.id == "F" || key.id == "J" {
                        ink.withAlphaComponent(0.45).setFill()
                        NSBezierPath(roundedRect: CGRect(x: rect.midX - 3, y: rect.maxY - padding, width: 6, height: 1),
                                     xRadius: 0.5, yRadius: 0.5).fill()
                    }
                }
            }
        }
    }
}

private final class MechanicalClickView: MTKView {
    var clicked: ((NSEvent) -> Void)?
    override func mouseDown(with event: NSEvent) { clicked?(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// MTKView stays paused between finite keyboard and mouse press impulses.
final class MechanicalKeyboardView: NSView, MTKViewDelegate {
    static let size = CGSize(width: 1320, height: 820)
    let model: MechanicalKeyboardScene
    private let metal: MechanicalClickView
    private let legends: KeyboardLegendOverlay
    private let queue: MTLCommandQueue
    private var state: MechanicalFullPressState
    private let selection = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private(set) var drawCount = 0
    var hasScheduledFrame: Bool { pending != nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private static let physicalKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "Delete", 53: "Esc", 54: "RightCmd", 55: "LeftCmd", 56: "LeftShift", 57: "CapsLock",
        58: "LeftOption", 59: "Ctrl", 60: "RightShift", 61: "RightOption", 62: "Ctrl", 63: "Fn",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10",
        111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            press("Tab")
            let destination = event.modifierFlags.contains(.shift) ? previousKeyView : nextKeyView
            window?.makeFirstResponder(destination)
            return
        }
        guard !event.isARepeat, !event.modifierFlags.contains(.command),
              let id = Self.physicalKeys[event.keyCode] else { super.keyDown(with: event); return }
        press(id)
    }
    override func flagsChanged(with event: NSEvent) {
        let flags: [UInt16: NSEvent.ModifierFlags] = [54: .command, 55: .command, 56: .shift,
            57: .capsLock, 58: .option, 59: .control, 60: .shift, 61: .option, 62: .control, 63: .function]
        if let flag = flags[event.keyCode], event.modifierFlags.contains(flag),
           let id = Self.physicalKeys[event.keyCode] { press(id) }
    }
    private var eligible: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && !isHiddenOrHasHiddenAncestor && !NSApp.isHidden
    }
    init(model: MechanicalKeyboardScene, embedded: Bool = false) {
        self.model = model
        state = MechanicalFullPressState(supported: Set(model.keys.map(\.id)))
        state.profile = model.isMacModel ? .light : .deep
        legends = KeyboardLegendOverlay(model: model)
        metal = MechanicalClickView(frame: CGRect(origin: .zero, size: MechanicalKeyboardScene.size), device: model.metalDevice)
        queue = model.metalDevice.makeCommandQueue()!
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        wantsLayer = true; layer?.backgroundColor = MechanicalKeyboardScene.canvas.cgColor
        appearance = NSAppearance(named: .aqua)
        let title = NSTextField(labelWithString: NSLocalizedString("Mechanical Keyboard · Click to press", comment: "Mechanical Keyboard"))
        title.font = .systemFont(ofSize: 23, weight: .medium)
        title.frame = CGRect(x: 20, y: 12, width: 1280, height: 32); addSubview(title)
        title.isHidden = embedded
        let note = NSTextField(labelWithString: NSLocalizedString("77 keys · mouse only · 160 ms press · fixed height", comment: "Mechanical Keyboard"))
        if embedded {
            note.stringValue = NSLocalizedString("keyboard.interaction.hint", comment: "Keyboard interaction")
        }
        note.font = .systemFont(ofSize: 13); note.textColor = .secondaryLabelColor
        note.frame = CGRect(x: 20, y: 49, width: 1280, height: 24); addSubview(note)
        metal.frame.origin = CGPoint(x: 20, y: 77)
        metal.isPaused = true; metal.enableSetNeedsDisplay = false
        metal.colorPixelFormat = .bgra8Unorm_srgb; metal.depthStencilPixelFormat = .depth32Float_stencil8
        metal.sampleCount = 4; metal.delegate = self
        addSubview(metal)
        legends.frame = metal.frame
        addSubview(legends)
        selection.stringValue = NSLocalizedString("Click a keycap to test its press and return.", comment: "Mechanical Keyboard")
        selection.font = .systemFont(ofSize: 12); selection.textColor = .secondaryLabelColor
        selection.frame = CGRect(x: 20, y: 795, width: 1280, height: 22); addSubview(selection)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(NSLocalizedString("keyboard.interaction.description", comment: "Keyboard interaction"))
        setAccessibilityHelp(NSLocalizedString("keyboard.interaction.help", comment: "Keyboard interaction"))
        metal.setAccessibilityElement(false)
        metal.clicked = { [weak self] event in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            let point = self.convert(event.locationInWindow, from: nil)
            let topPoint = CGPoint(x: point.x - self.metal.frame.minX, y: point.y - self.metal.frame.minY)
            if let id = self.model.fullKey(at: topPoint, pixelScale: self.metal.drawableSize.width / MechanicalKeyboardScene.size.width) {
                self.press(id)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { pending?.cancel(); observers.forEach(NotificationCenter.default.removeObserver) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancel(); observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.willCloseNotification] {
            if let window { observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.cancel() }) }
        }
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        }
        if window != nil { DispatchQueue.main.async { [weak self] in self?.drawOnce() } }
    }
    override func viewDidHide() { super.viewDidHide(); cancel() }
    override func viewDidUnhide() { super.viewDidUnhide(); drawOnce() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { drawOnce() }
    func draw(in view: MTKView) {
        guard eligible else { return }
        model.drawFullModel(in: view, queue: queue); drawCount += 1
        legends.pixelScale = metal.drawableSize.width / MechanicalKeyboardScene.size.width
        legends.needsDisplay = true
    }
    private func drawOnce() { if eligible { metal.draw() } }
    func press(_ id: String) {
        guard eligible, state.supported.contains(id) else { return }
        state.press(id, at: ProcessInfo.processInfo.systemUptime)
        selection.stringValue = String(format: NSLocalizedString("Selected key: %@", comment: "Mechanical Keyboard"), id)
        setAccessibilityValue(selection.stringValue)
        if pending == nil { tick() }
    }
    private func tick() {
        pending = nil
        guard eligible else { cancel(); return }
        let next = DispatchTime.now() + 1.0 / 60
        model.applyFullPress(state.offsets(at: ProcessInfo.processInfo.systemUptime,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        drawOnce()
        guard state.activeCount > 0 else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.tick()
        }
        pending = work; DispatchQueue.main.asyncAfter(deadline: next, execute: work)
    }
    func cancel() {
        generation += 1; pending?.cancel(); pending = nil; state.cancel()
        model.applyFullPress([:]); drawOnce()
    }

}
