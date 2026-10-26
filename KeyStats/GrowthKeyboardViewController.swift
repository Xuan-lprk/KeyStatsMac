import Cocoa

/// Production page: formal StatsManager data, cached renderer and bounded playback.
/// Today refreshes on presentation/activation, Today and explicit Refresh; no event subscription.
final class GrowthKeyboardViewController: NSViewController {
    private let loadPresentation: () -> GrowthKeyboardPresentation?
    private let startsIn3D: Bool
    private let playback = GrowthPlaybackDriver()
    private var presentation: GrowthKeyboardPresentation?
    private var selectionGeneration = 0
    private let renderer = EditorialKeyboardRenderer(frame: .zero)
    private var spatialRenderer: GrowthKeyboard3DRenderer?
    private(set) var usesMechanical = false
    private let rendererHost = NSView()
    private let modeSelector = NSSegmentedControl()
    private var shows3D: Bool { modeSelector.selectedSegment == 1 }
    private var observers: [NSObjectProtocol] = []
    private weak var observedWindow: NSWindow?
    private var isPresented = false
    private let dateLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let coverageLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let datePicker = NSDatePicker()
    private let slider = NSSlider()
    private let keyPicker = NSPopUpButton()
    private let timelineStart = NSTextField(labelWithString: "")
    private let timelineEnd = NSTextField(labelWithString: "")
    private let previous = NSButton()
    private let next = NSButton()
    private let play = NSButton()
    private let today = NSButton()
    private let refresh = NSButton()
    private let numberFormatter: NumberFormatter = {
        let value = NumberFormatter(); value.numberStyle = .decimal; return value
    }()
    private let dateFormatter: DateFormatter = {
        let value = DateFormatter(); value.dateStyle = .medium; value.timeStyle = .none; return value
    }()

    init(manager: StatsManager, startsIn3D: Bool = false) {
        self.startsIn3D = startsIn3D
        loadPresentation = { GrowthKeyboardPresentation.load(from: manager) }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { playback.pause(); observers.forEach { NotificationCenter.default.removeObserver($0) } }

    override func loadView() {
        view = KeyboardVisualizationCanvasView(frame: NSRect(x: 0, y: 0, width: 1160, height: 736))
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2)
        ])

        let metricCaption = caption("growth.metric.caption")
        totalLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        totalLabel.setAccessibilityLabel(text("growth.metric.caption"))
        let metric = column([metricCaption, totalLabel], spacing: 2)
        dateLabel.font = .systemFont(ofSize: 14, weight: .medium)
        let snapshot = column([caption("growth.snapshot.caption"), dateLabel], spacing: 5)
        snapshot.alignment = .trailing
        modeSelector.segmentCount = 2
        modeSelector.setLabel(text("growth.mode.editorial"), forSegment: 0)
        modeSelector.setLabel(text("growth.mode.3d"), forSegment: 1)
        modeSelector.selectedSegment = 0; modeSelector.isHidden = startsIn3D
        modeSelector.segmentStyle = .rounded
        modeSelector.target = self; modeSelector.action = #selector(changeDisplayMode)
        modeSelector.setAccessibilityLabel(text("growth.mode.choose"))
        let header = NSStackView(views: [metric, flexibleSpace(), modeSelector, snapshot])
        header.spacing = 16; header.alignment = .centerY
        add(header, to: stack)

        rendererHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        rendererHost.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        add(rendererHost, to: stack)
        rendererHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        installRenderer(renderer)

        func button(_ value: NSButton, _ title: String, _ action: Selector) -> NSButton {
            value.title = title; value.bezelStyle = .rounded; value.target = self; value.action = action
            value.font = .systemFont(ofSize: 12)
            return value
        }
        button(previous, "‹", #selector(previousDay)).setAccessibilityLabel(text("growth.previous"))
        button(next, "›", #selector(nextDay)).setAccessibilityLabel(text("growth.next"))
        for (control, symbol) in [(previous, "chevron.left"), (next, "chevron.right")] {
            control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            control.imagePosition = .imageOnly
            control.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        datePicker.datePickerStyle = .textField
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.isBordered = false; datePicker.drawsBackground = false
        datePicker.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        datePicker.target = self; datePicker.action = #selector(pickDate)
        datePicker.setAccessibilityLabel(text("growth.date"))
        datePicker.widthAnchor.constraint(equalToConstant: 130).isActive = true
        button(play, text("growth.play"), #selector(togglePlayback))
        play.font = .systemFont(ofSize: 12, weight: .semibold)
        play.imagePosition = .imageLeft
        play.widthAnchor.constraint(greaterThanOrEqualToConstant: 166).isActive = true
        button(today, text("growth.today"), #selector(showToday))
        button(refresh, text("growth.refresh"), #selector(refreshToday))
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        refresh.imagePosition = .imageOnly; refresh.toolTip = text("growth.refresh")
        refresh.setAccessibilityLabel(text("growth.refresh"))
        refresh.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let navigation = NSStackView(views: [play, flexibleSpace(), previous, datePicker, next, today, refresh])
        navigation.spacing = 8; navigation.alignment = .centerY
        slider.target = self; slider.action = #selector(scrub); slider.isContinuous = true
        slider.setAccessibilityLabel(text("growth.timeline"))
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for endpoint in [timelineStart, timelineEnd] {
            endpoint.font = .systemFont(ofSize: 10)
            endpoint.textColor = .secondaryLabelColor
            endpoint.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let timeline = NSStackView(views: [timelineStart, slider, timelineEnd])
        timeline.spacing = 12; timeline.alignment = .centerY
        let transport = column([navigation, timeline], spacing: 8)
        for row in [navigation, timeline] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: transport.widthAnchor).isActive = true
        }
        let playbackCard = card(transport, height: 82)
        add(playbackCard, to: stack)

        keyPicker.addItem(withTitle: text("growth.key.choose"))
        for id in renderer.keyIDs {
            keyPicker.addItem(withTitle: displayName(id)); keyPicker.lastItem?.representedObject = id
        }
        keyPicker.target = self; keyPicker.action = #selector(pickKey)
        keyPicker.controlSize = .small; keyPicker.font = .systemFont(ofSize: 12)
        keyPicker.setAccessibilityLabel(text("growth.key.details"))
        keyPicker.widthAnchor.constraint(equalToConstant: 156).isActive = true
        detailLabel.isSelectable = true
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setAccessibilityLabel(text("growth.key.details"))
        let legend = NSStackView()
        legend.spacing = 5; legend.alignment = .centerY
        let usage = caption("growth.usage.caption")
        legend.addArrangedSubview(usage)
        for progress in [0.0, 0.5, 0.95] {
            let dot = NSBox(); dot.boxType = .custom; dot.borderWidth = 0
            dot.fillColor = renderer.sceneLayout.usageColor(progress); dot.cornerRadius = 3
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true
            legend.addArrangedSubview(dot)
        }
        legend.toolTip = text("growth.usage.help")
        legend.setAccessibilityElement(true); legend.setAccessibilityRole(.image)
        legend.setAccessibilityLabel(text("growth.usage.help"))
        let details = NSStackView(views: [keyPicker, detailLabel, flexibleSpace(), legend])
        details.spacing = 12; details.alignment = .centerY
        add(card(details, height: 52), to: stack)
        coverageLabel.font = .systemFont(ofSize: 10)
        coverageLabel.textColor = .secondaryLabelColor; coverageLabel.maximumNumberOfLines = 2
        add(coverageLabel, to: stack)
        renderer.onSelectionChanged = { [weak self] in self?.showKeyDetail($0) }
        playback.onChange = { [weak self] _ in self?.renderSelection() }
        updateControls(); showKeyDetail(nil)
        if startsIn3D { modeSelector.selectedSegment = 1; changeDisplayMode() }
    }

    private func caption(_ key: String) -> NSTextField {
        let label = NSTextField(labelWithString: text(key))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }
    private func column(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    private func flexibleSpace() -> NSView {
        let space = NSView()
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return space
    }
    private func card(_ content: NSView, height: CGFloat) -> NSBox {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.fillColor = .controlBackgroundColor.withAlphaComponent(0.58)
        box.borderColor = .separatorColor.withAlphaComponent(0.25)
        box.borderWidth = 0.5; box.cornerRadius = 12
        box.contentViewMargins = NSSize(width: 14, height: 10)
        content.translatesAutoresizingMaskIntoConstraints = false
        box.contentView!.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            content.centerYAnchor.constraint(equalTo: box.contentView!.centerYAnchor),
            box.heightAnchor.constraint(equalToConstant: height)
        ])
        return box
    }

    private func add(_ child: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func installRenderer(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        rendererHost.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: rendererHost.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: rendererHost.trailingAnchor),
            child.topAnchor.constraint(equalTo: rendererHost.topAnchor),
            child.bottomAnchor.constraint(equalTo: rendererHost.bottomAnchor)
        ])
    }

    @objc private func changeDisplayMode() {
        playback.pause()
        let selected = shows3D ? renderer.selectedKeyID : spatialRenderer?.selectedKeyID
        if shows3D && spatialRenderer == nil {
            let spatial: GrowthKeyboard3DRenderer
            if usesMechanical {
                do {
                    let model = try MechanicalKeyboardScene()
                    try model.configureFullModel()
                    spatial = GrowthKeyboard3DRenderer(layout: renderer.sceneLayout,
                        renderFrame: { model.renderGrowth($0, background: $1) },
                        imageSize: MechanicalKeyboardScene.size, bakesLegends: true)
                } catch {
                    usesMechanical = false
                    NSAlert(error: error).runModal()
                    changeDisplayMode()
                    return
                }
            } else {
                spatial = GrowthKeyboard3DRenderer(layout: renderer.sceneLayout)
            }
            spatial.onSelectionChanged = { [weak self] in self?.showKeyDetail($0) }
            installRenderer(spatial)
            spatialRenderer = spatial
        }
        renderer.clearHover()
        spatialRenderer?.clearHover()
        renderer.isHidden = shows3D
        spatialRenderer?.isHidden = !shows3D
        slider.isContinuous = !shows3D
        play.toolTip = shows3D ? text("growth.mode.3d.help") : nil
        renderSelection()
        if shows3D { spatialRenderer?.selectKey(selected) }
        else { renderer.selectKey(selected) }
        updateActive()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setPresented(true)
        if presentation == nil { refreshData(resetToToday: true) }
    }

    func setMechanical(_ enabled: Bool) {
        _ = view
        guard enabled != usesMechanical else { return }
        playback.pause()
        let selected = spatialRenderer?.selectedKeyID ?? renderer.selectedKeyID
        spatialRenderer?.setActive(false)
        spatialRenderer?.removeFromSuperview()
        spatialRenderer = nil
        usesMechanical = enabled
        modeSelector.selectedSegment = 1
        changeDisplayMode()
        spatialRenderer?.selectKey(selected)
        updateControls()
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        setPresented(false)
    }

    func setPresented(_ presented: Bool) {
        isPresented = presented
        if !isViewLoaded { return }
        bindWindow()
        updateActive()
        if !presented { renderer.clearHover() }
    }

    private var isWindowActive: Bool {
        guard isPresented, let window = view.window else { return false }
        return window.isVisible && window.isKeyWindow && !window.isMiniaturized
            && window.occlusionState.contains(.visible) && NSApp.isActive
    }

    private func updateActive() {
        playback.waitsForPresentation = shows3D
        playback.stepInterval = shows3D ? 0.35 : 0.15
        playback.setActive(isWindowActive)
        spatialRenderer?.setActive(isWindowActive && shows3D)
        if !isWindowActive { renderer.clearHover(); spatialRenderer?.clearHover() }
        updateControls()
    }

    private func bindWindow() {
        guard let window = view.window, observedWindow !== window else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        observedWindow = window
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                guard let self else { return }
                if name == NSWindow.didBecomeKeyNotification && self.isPresented {
                    self.refreshData(resetToToday: false)
                }
                if name == NSWindow.didResignKeyNotification || name == NSWindow.willCloseNotification {
                    self.playback.setActive(false); self.spatialRenderer?.setActive(false)
                    self.renderer.clearHover(); self.updateControls()
                } else { self.updateActive() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                guard let self else { return }
                if name == NSApplication.didBecomeActiveNotification {
                    self.updateActive()
                    if self.shows3D { self.renderSelection() }
                } else {
                    self.playback.setActive(false); self.spatialRenderer?.setActive(false)
                    self.renderer.clearHover(); self.updateControls()
                }
            })
        }
    }

    func refreshData(resetToToday: Bool = false) {
        _ = view
        let selectedDate = presentation.map { $0.date(at: playback.state.offset) }
        let wasToday = presentation.map { playback.state.offset == $0.dayCount - 1 } ?? true
        playback.pause()
        presentation = loadPresentation()
        guard let presentation else {
            renderer.apply([]); renderer.selectKey(nil)
            spatialRenderer?.apply([]); spatialRenderer?.selectKey(nil)
            dateLabel.stringValue = text("growth.empty")
            totalLabel.stringValue = ""
            coverageLabel.stringValue = text("growth.empty.detail")
            updateControls()
            return
        }
        datePicker.calendar = presentation.calendar
        datePicker.timeZone = presentation.calendar.timeZone
        datePicker.minDate = presentation.period.firstTrackedDate
        datePicker.maxDate = presentation.today
        dateFormatter.calendar = presentation.calendar; dateFormatter.timeZone = presentation.calendar.timeZone
        timelineStart.stringValue = dateFormatter.string(from: presentation.period.firstTrackedDate)
        timelineEnd.stringValue = text("growth.today")
        slider.minValue = 0; slider.maxValue = Double(max(1, presentation.dayCount - 1))
        let offset = resetToToday || wasToday ? presentation.dayCount - 1
            : selectedDate.map { presentation.offset(for: $0) } ?? presentation.dayCount - 1
        playback.reset(dayCount: presentation.dayCount, selectedOffset: offset)
        updateActive()
    }

    private func renderSelection() {
        guard let presentation else { updateControls(); return }
        selectionGeneration &+= 1
        let selectionToken = selectionGeneration
        let frame = presentation.frame(at: playback.state.offset)
        if shows3D {
            let offset = playback.state.offset, generation = playback.presentationGeneration
            spatialRenderer?.apply(frame.keyUsages, animated: playback.isPresentingPlaybackFrame) { [weak self] in
                guard let self, self.shows3D, self.playback.state.offset == offset,
                      self.selectionGeneration == selectionToken else { return }
                self.updateLabels(for: frame)
                self.playback.framePresented(at: offset, generation: generation)
            }
            updateControls()
        } else {
            renderer.apply(frame.keyUsages)
            updateLabels(for: frame)
        }
    }

    private func updateLabels(for frame: GrowthKeyboardFrame) {
        set(dateLabel, String(format: text("growth.date.summary"), dateFormatter.string(from: frame.date), frame.dayIndex))
        set(totalLabel, grouped(frame.snapshot.totalKeyPresses))
        var note = frame.hasPartialDetails
            ? String(format: text("growth.coverage"), grouped(frame.snapshot.detailedKeyPresses), grouped(frame.snapshot.totalKeyPresses))
            : text("growth.participation")
        if frame.dayKey != frame.snapshot.dayKey { note += "  " + text("growth.noDailyRecord") }
        set(coverageLabel, note)
        datePicker.dateValue = frame.date
        slider.integerValue = playback.state.offset
        updateControls()
    }

    private func updateControls() {
        let available = presentation != nil
        previous.isEnabled = available && playback.state.offset > 0
        next.isEnabled = available && playback.state.offset < playback.state.lastOffset
        datePicker.isEnabled = available
        slider.isEnabled = available && (presentation?.dayCount ?? 0) > 1
        play.isEnabled = available && (presentation?.dayCount ?? 0) > 1
        today.isEnabled = available
        keyPicker.isEnabled = available
        play.title = text(playback.state.isPlaying ? "growth.pause" : "growth.play")
        play.image = NSImage(systemSymbolName: playback.state.isPlaying ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        play.setAccessibilityLabel(play.title)
    }
    private func select(_ offset: Int) {
        if let presentation, offset >= presentation.dayCount - 1,
           playback.state.offset < presentation.dayCount - 1 {
            refreshData(resetToToday: true)
        } else { playback.select(offset) }
    }
    @objc private func previousDay() { select(playback.state.offset - 1) }
    @objc private func nextDay() { select(playback.state.offset + 1) }
    @objc private func showToday() { refreshData(resetToToday: true) }
    @objc private func refreshToday() { refreshData() }
    @objc private func pickDate() {
        guard let presentation else { return }
        select(presentation.offset(for: datePicker.dateValue))
    }
    @objc private func scrub() { select(slider.integerValue) }
    @objc private func togglePlayback() {
        if playback.state.isPlaying { playback.pause(); renderSelection() }
        else { updateActive(); playback.start() }
    }
    @objc private func pickKey() {
        let id = keyPicker.selectedItem?.representedObject as? String
        if shows3D { spatialRenderer?.selectKey(id) }
        else { renderer.selectKey(id) }
    }

    private func showKeyDetail(_ value: GrowthKeyboardKeyUsage?) {
        guard let value else {
            keyPicker.selectItem(at: 0); set(detailLabel, text("growth.key.prompt")); return
        }
        if let index = renderer.keyIDs.firstIndex(of: value.id) { keyPicker.selectItem(at: index + 1) }
        set(detailLabel, String(format: text("growth.key.summary"), displayName(value.id),
                               grouped(value.count), value.progress * 100))
    }
    private func displayName(_ id: String) -> String {
        let names = ["LeftCmd", "RightCmd", "LeftShift", "RightShift", "LeftOption", "RightOption", "Ctrl",
                     "Return", "Delete", "Space", "CapsLock", "Tab", "Esc", "Fn", "Left", "Right", "Up", "Down"]
        return names.contains(id) ? text("growth.key." + id) : id
    }
    private func grouped(_ count: Int) -> String { numberFormatter.string(from: NSNumber(value: count)) ?? "\(count)" }
    private func set(_ label: NSTextField, _ value: String) { if label.stringValue != value { label.stringValue = value } }
    private func text(_ key: String) -> String { NSLocalizedString(key, comment: "Growth Keyboard") }
}
