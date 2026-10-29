import Cocoa

/// A visible-only, aggregate-rate instrument. It never receives key identities,
/// event timestamps or input sequences; its short sample history is memory-only.
final class TypingPulseView: NSView {
    private struct Sample {
        let keyboard: Double
        let pointer: Double
    }

    private let maximumSampleCount = 40
    private var samples: [Sample] = []
    private var acceptsSamples = false
    private var generation = 0
    private var impulseCounter = 0
    private var lastImpulseTime: TimeInterval = 0
    private var particles: [CALayer] = []

    private let waveHost = NSView()
    private let keyboardFill = CAShapeLayer()
    private let keyboardLine = CAShapeLayer()
    private let pointerLine = CAShapeLayer()
    private let terminalDot = CALayer()
    private var gridLines: [CALayer] = []

    private let kpsValueLabel = NSTextField(labelWithString: "0")
    private let cpsValueLabel = NSTextField(labelWithString: "0")
    private let liveDot = NSView()
    private let hintLabel = NSTextField(labelWithString: NSLocalizedString("pulse.idleHint", comment: ""))

    private let keyboardColor = NSColor(srgbRed: 0.22, green: 0.84, blue: 1.0, alpha: 1)
    private let pointerColor = NSColor(srgbRed: 1.0, green: 0.67, blue: 0.28, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        setupWaveLayers()
        updateLabels()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stop()
    }

    override func layout() {
        super.layout()
        layoutGrid()
        updateWaveform(animated: false)
    }

    func start() {
        guard !acceptsSamples else { return }
        acceptsSamples = true
        generation += 1
        samples.removeAll()
        lastImpulseTime = 0
        hintLabel.stringValue = NSLocalizedString("pulse.idleHint", comment: "")
        updateLabels()
        updateWaveform(animated: false)
    }

    func stop() {
        acceptsSamples = false
        generation += 1
        samples.removeAll()
        particles.forEach {
            $0.removeAllAnimations()
            $0.removeFromSuperlayer()
        }
        particles.removeAll()
        for layer in [keyboardFill, keyboardLine, pointerLine, terminalDot] {
            layer.removeAllAnimations()
        }
    }

    func append(currentKPS: Int, currentCPS: Int) {
        guard acceptsSamples else { return }
        if samples.isEmpty && currentKPS == 0 && currentCPS == 0 { return }
        samples.append(Sample(keyboard: Double(max(0, currentKPS)), pointer: Double(max(0, currentCPS))))
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
        guard samples.contains(where: { $0.keyboard > 0 || $0.pointer > 0 }) else {
            samples.removeAll()
            hintLabel.stringValue = NSLocalizedString("pulse.idleHint", comment: "")
            updateLabels()
            updateWaveform(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            return
        }
        hintLabel.stringValue = NSLocalizedString("pulse.activeHint", comment: "")
        updateLabels()
        updateWaveform(animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// A bounded decorative response to an existing aggregate stats update.
    /// It carries no information about which key or button produced the update.
    func emitImpulse() {
        guard acceptsSamples,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              bounds.width > 40 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastImpulseTime >= 0.18 else { return }
        lastImpulseTime = now
        impulseCounter += 1
        spawnParticle(color: impulseCounter.isMultiple(of: 4) ? pointerColor : keyboardColor)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.055, blue: 0.082, alpha: 0.97).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(NSLocalizedString("pulse.title", comment: ""))
        setAccessibilityHelp(NSLocalizedString("pulse.accessibilityHelp", comment: ""))
        toolTip = NSLocalizedString("pulse.accessibilityHelp", comment: "")

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("pulse.title", comment: ""))
        titleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        liveDot.wantsLayer = true
        liveDot.layer?.cornerRadius = 3
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveDot.setAccessibilityElement(false)
        let liveLabel = NSTextField(labelWithString: NSLocalizedString("pulse.live", comment: ""))
        liveLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        liveLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        liveLabel.setAccessibilityElement(false)
        let liveStack = NSStackView(views: [liveDot, liveLabel])
        liveStack.orientation = .horizontal
        liveStack.alignment = .centerY
        liveStack.spacing = 5
        liveStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liveStack)

        kpsValueLabel.font = .monospacedDigitSystemFont(ofSize: 27, weight: .bold)
        kpsValueLabel.textColor = .white
        kpsValueLabel.setAccessibilityElement(false)
        let kpsUnit = NSTextField(labelWithString: "KPS")
        kpsUnit.font = .systemFont(ofSize: 9, weight: .bold)
        kpsUnit.textColor = keyboardColor.withAlphaComponent(0.82)
        kpsUnit.setAccessibilityElement(false)
        let kpsStack = NSStackView(views: [kpsValueLabel, kpsUnit])
        kpsStack.orientation = .horizontal
        kpsStack.alignment = .lastBaseline
        kpsStack.spacing = 5
        kpsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(kpsStack)

        cpsValueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        cpsValueLabel.textColor = pointerColor
        cpsValueLabel.setAccessibilityElement(false)
        let cpsUnit = NSTextField(labelWithString: "CPS")
        cpsUnit.font = .systemFont(ofSize: 9, weight: .bold)
        cpsUnit.textColor = pointerColor.withAlphaComponent(0.75)
        cpsUnit.setAccessibilityElement(false)
        let cpsStack = NSStackView(views: [cpsValueLabel, cpsUnit])
        cpsStack.orientation = .horizontal
        cpsStack.alignment = .lastBaseline
        cpsStack.spacing = 5
        cpsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cpsStack)

        waveHost.wantsLayer = true
        waveHost.translatesAutoresizingMaskIntoConstraints = false
        waveHost.setAccessibilityElement(false)
        addSubview(waveHost)

        hintLabel.font = .systemFont(ofSize: 9, weight: .medium)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.setAccessibilityElement(false)
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            liveStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            liveStack.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            liveDot.widthAnchor.constraint(equalToConstant: 6),
            liveDot.heightAnchor.constraint(equalToConstant: 6),
            kpsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            kpsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            cpsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            cpsStack.centerYAnchor.constraint(equalTo: kpsStack.centerYAnchor, constant: 3),
            waveHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            waveHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            waveHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),
            waveHost.heightAnchor.constraint(equalToConstant: 50),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    private func setupWaveLayers() {
        keyboardFill.fillColor = keyboardColor.withAlphaComponent(0.09).cgColor
        keyboardFill.strokeColor = nil
        keyboardLine.fillColor = nil
        keyboardLine.strokeColor = keyboardColor.cgColor
        keyboardLine.lineWidth = 2
        keyboardLine.lineJoin = .round
        keyboardLine.lineCap = .round
        keyboardLine.shadowColor = keyboardColor.cgColor
        keyboardLine.shadowOpacity = 0.55
        keyboardLine.shadowRadius = 4
        keyboardLine.shadowOffset = .zero
        pointerLine.fillColor = nil
        pointerLine.strokeColor = pointerColor.withAlphaComponent(0.9).cgColor
        pointerLine.lineWidth = 1.5
        pointerLine.lineJoin = .round
        pointerLine.lineCap = .round
        terminalDot.backgroundColor = keyboardColor.cgColor
        terminalDot.cornerRadius = 2.5
        terminalDot.shadowColor = keyboardColor.cgColor
        terminalDot.shadowOpacity = 0.9
        terminalDot.shadowRadius = 5
        terminalDot.shadowOffset = .zero
        for layer in [keyboardFill, keyboardLine, pointerLine, terminalDot] {
            layer.actions = ["path": NSNull(), "position": NSNull(), "opacity": NSNull()]
            waveHost.layer?.addSublayer(layer)
        }
    }

    private func layoutGrid() {
        guard let hostLayer = waveHost.layer else { return }
        if gridLines.isEmpty {
            for _ in 0..<3 {
                let line = CALayer()
                line.backgroundColor = NSColor.white.withAlphaComponent(0.055).cgColor
                hostLayer.addSublayer(line)
                gridLines.append(line)
            }
            hostLayer.insertSublayer(keyboardFill, above: gridLines.last)
            hostLayer.insertSublayer(keyboardLine, above: keyboardFill)
            hostLayer.insertSublayer(pointerLine, above: keyboardLine)
            hostLayer.insertSublayer(terminalDot, above: pointerLine)
        }
        for (index, line) in gridLines.enumerated() {
            line.frame = CGRect(x: 0, y: waveHost.bounds.height * CGFloat(index + 1) / 4,
                                width: waveHost.bounds.width, height: 0.5)
        }
    }

    private func updateLabels() {
        let latest = samples.last ?? Sample(keyboard: 0, pointer: 0)
        kpsValueLabel.stringValue = latest.keyboard > 0 ? String(format: "%.1f", latest.keyboard) : "0"
        cpsValueLabel.stringValue = latest.pointer > 0 ? String(format: "%.1f", latest.pointer) : "0"
        let isActive = latest.keyboard > 0 || latest.pointer > 0
        liveDot.layer?.backgroundColor = (isActive ? keyboardColor : NSColor.systemGray).withAlphaComponent(isActive ? 1 : 0.5).cgColor
        setAccessibilityValue(String(format: NSLocalizedString("pulse.accessibilityValue", comment: ""), latest.keyboard, latest.pointer))
    }

    private func updateWaveform(animated: Bool) {
        guard waveHost.bounds.width > 1, waveHost.bounds.height > 1 else { return }
        let first = samples.first ?? Sample(keyboard: 0, pointer: 0)
        let padded = Array(repeating: first, count: max(0, maximumSampleCount - samples.count)) + samples
        let maximum = max(6, padded.map { max($0.keyboard, $0.pointer) }.max() ?? 0) * 1.12
        let keyboardPoints = points(for: padded.map(\.keyboard), maximum: maximum)
        let pointerPoints = points(for: padded.map(\.pointer), maximum: maximum)
        let keyboardPath = smoothPath(points: keyboardPoints, closeToBaseline: false)
        let fillPath = smoothPath(points: keyboardPoints, closeToBaseline: true)
        let pointerPath = smoothPath(points: pointerPoints, closeToBaseline: false)
        assign(path: fillPath, to: keyboardFill, animated: animated)
        assign(path: keyboardPath, to: keyboardLine, animated: animated)
        assign(path: pointerPath, to: pointerLine, animated: animated)
        if let last = keyboardPoints.last {
            terminalDot.frame = CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)
        }
    }

    private func points(for values: [Double], maximum: Double) -> [CGPoint] {
        let rect = waveHost.bounds.insetBy(dx: 2, dy: 4)
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            CGPoint(x: rect.minX + CGFloat(index) / CGFloat(values.count - 1) * rect.width,
                    y: rect.minY + CGFloat(min(1, value / maximum)) * rect.height)
        }
    }

    private func smoothPath(points: [CGPoint], closeToBaseline: Bool) -> CGPath {
        guard let first = points.first, points.count > 1 else { return CGPath(rect: .zero, transform: nil) }
        let path = CGMutablePath()
        path.move(to: first)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(0, index - 1)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(points.count - 1, index + 2)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        if closeToBaseline, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: 0))
            path.addLine(to: CGPoint(x: first.x, y: 0))
            path.closeSubpath()
        }
        return path
    }

    private func assign(path: CGPath, to layer: CAShapeLayer, animated: Bool) {
        let previous = layer.path
        layer.path = path
        guard animated, let previous else { return }
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = previous
        animation.toValue = path
        animation.duration = 0.28
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "pulsePath")
    }

    private func spawnParticle(color: NSColor) {
        if particles.count >= 10, let oldest = particles.first {
            oldest.removeAllAnimations()
            oldest.removeFromSuperlayer()
            particles.removeFirst()
        }
        let particle = CALayer()
        particle.frame = CGRect(x: bounds.width - 34 + CGFloat.random(in: -22...4), y: 28,
                                width: 4, height: 6)
        particle.cornerRadius = 1.5
        particle.backgroundColor = color.withAlphaComponent(0.9).cgColor
        particle.shadowColor = color.cgColor
        particle.shadowOpacity = 0.8
        particle.shadowRadius = 4
        particle.shadowOffset = .zero
        layer?.addSublayer(particle)
        particles.append(particle)

        let endPosition = CGPoint(x: particle.position.x + CGFloat.random(in: -12...12),
                                  y: particle.position.y + CGFloat.random(in: 18...34))
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: particle.position)
        move.toValue = NSValue(point: endPosition)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.45
        let group = CAAnimationGroup()
        group.animations = [move, fade, scale]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true
        particle.add(group, forKey: "pulseImpulse")

        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) { [weak self, weak particle] in
            guard let self, self.generation == token, let particle else { return }
            particle.removeFromSuperlayer()
            self.particles.removeAll { $0 === particle }
        }
    }
}
