import Cocoa

private func resolvedCGColor(_ color: NSColor, for view: NSView) -> CGColor {
    var resolved: CGColor = color.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
        resolved = color.cgColor
    }
    return resolved
}

private func resolvedCGColor(_ color: NSColor, alpha: CGFloat, for view: NSView) -> CGColor {
    var resolved: CGColor = color.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
        resolved = color.withAlphaComponent(alpha).cgColor
    }
    return resolved
}

private func applyCardShadow(_ layer: CALayer?, for view: NSView) {
    guard let layer = layer else { return }
    layer.masksToBounds = false
    layer.shadowColor = resolvedCGColor(NSColor.black, alpha: 0.07, for: view)
    layer.shadowOpacity = 1
    layer.shadowRadius = 8
    layer.shadowOffset = NSSize(width: 0, height: -1)
    layer.borderWidth = 0.5
    layer.borderColor = resolvedCGColor(NSColor.separatorColor, alpha: 0.16, for: view)
}

final class KeyboardHeatmapViewController: NSViewController {
    private enum DaySlideDirection {
        case left
        case right

        func incomingOffset(distance: CGFloat) -> CGFloat {
            switch self {
            case .left: return -distance
            case .right: return distance
            }
        }

        func outgoingOffset(distance: CGFloat) -> CGFloat {
            -incomingOffset(distance: distance)
        }
    }

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var previousDayButton: NSButton!
    private var nextDayButton: NSButton!
    private var backToTodayButton: NSButton!
    private var datePickerButton: NSButton!
    private var summaryLabel: NSTextField!
    private var heatmapContainer: NSView!
    private var keyboardHeatmapView: KeyboardHeatmapView!
    private var keyboardEmptyOverlayView: NSView!
    private var emptyStateBadgeView: EmptyStateBadgeView!

    private var selectedDate = Calendar.current.startOfDay(for: Date())
    private var dateBounds: (start: Date, end: Date) = {
        let today = Calendar.current.startOfDay(for: Date())
        return (today, today)
    }()

    private var statsUpdateToken: UUID?
    private var pendingRefresh = false
    private var isDayTransitionAnimating = false
    private var appearanceObservation: NSKeyValueObservation?
    private lazy var datePickerPopover: NSPopover = makeDatePickerPopover()
    private lazy var datePickerViewController: HeatmapDatePickerPopoverViewController = {
        let viewController = HeatmapDatePickerPopoverViewController()
        viewController.onDateSelected = { [weak self] date in
            self?.handleDateSelection(date)
        }
        return viewController
    }()

    private lazy var dateFormatterWithoutYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()

    private lazy var dateFormatterWithYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMd")
        return formatter
    }()

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    override func loadView() {
        let trackingView = AppearanceTrackingView(frame: NSRect(x: 0, y: 0, width: 980, height: 520))
        trackingView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        trackingView.wantsLayer = true
        trackingView.layer?.backgroundColor = resolvedCGColor(NSColor.windowBackgroundColor, for: trackingView)
        self.view = trackingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refreshData()
        updateAppearance()

        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAppearance()
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshData()
        startLiveUpdates()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopLiveUpdates()
    }

    deinit {
        stopLiveUpdates()
        appearanceObservation = nil
    }

    private func setupUI() {
        let containerStack = NSStackView()
        containerStack.orientation = .vertical
        containerStack.alignment = .leading
        containerStack.spacing = 16
        containerStack.edgeInsets = NSEdgeInsets(top: 24, left: 30, bottom: 24, right: 30)
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerStack)

        let preferredContentWidth = containerStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40)
        preferredContentWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            preferredContentWidth,
            containerStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1450)
        ])

        titleLabel = NSTextField(labelWithString: NSLocalizedString("keyboardHeatmap.title", comment: ""))
        titleLabel.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left

        subtitleLabel = NSTextField(labelWithString: NSLocalizedString("keyboardHeatmap.subtitle", comment: ""))
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .left

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.addArrangedSubview(headerStack)
        headerStack.widthAnchor.constraint(equalTo: containerStack.widthAnchor).isActive = true

        previousDayButton = makeIconControlButton(
            systemName: "chevron.left",
            accessibilityLabel: NSLocalizedString("keyboardHeatmap.prevDay", comment: ""),
            action: #selector(showPreviousDay)
        )
        nextDayButton = makeIconControlButton(
            systemName: "chevron.right",
            accessibilityLabel: NSLocalizedString("keyboardHeatmap.nextDay", comment: ""),
            action: #selector(showNextDay)
        )
        backToTodayButton = makeControlButton(title: NSLocalizedString("keyboardHeatmap.backToToday", comment: ""), action: #selector(backToToday))
        backToTodayButton.isHidden = true

        datePickerButton = makeDatePickerButton()

        summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1

        let navigationStack = NSStackView()
        navigationStack.orientation = .horizontal
        navigationStack.alignment = .centerY
        navigationStack.spacing = 10
        navigationStack.translatesAutoresizingMaskIntoConstraints = false

        let dayNavigationStack = NSStackView(views: [previousDayButton, datePickerButton, nextDayButton])
        dayNavigationStack.orientation = .horizontal
        dayNavigationStack.alignment = .centerY
        dayNavigationStack.spacing = 8
        dayNavigationStack.setContentHuggingPriority(.required, for: .horizontal)
        dayNavigationStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        navigationStack.addArrangedSubview(dayNavigationStack)
        navigationStack.addArrangedSubview(backToTodayButton)
        navigationStack.addArrangedSubview(spacer)
        navigationStack.addArrangedSubview(summaryLabel)

        containerStack.addArrangedSubview(navigationStack)
        navigationStack.widthAnchor.constraint(equalTo: containerStack.widthAnchor).isActive = true

        heatmapContainer = NSView()
        heatmapContainer.translatesAutoresizingMaskIntoConstraints = false
        heatmapContainer.wantsLayer = true
        heatmapContainer.layer?.cornerRadius = 16
        heatmapContainer.layer?.borderWidth = 0.5

        keyboardHeatmapView = KeyboardHeatmapView()
        keyboardHeatmapView.wantsLayer = true
        keyboardHeatmapView.translatesAutoresizingMaskIntoConstraints = false

        keyboardEmptyOverlayView = NSView()
        keyboardEmptyOverlayView.wantsLayer = true
        keyboardEmptyOverlayView.translatesAutoresizingMaskIntoConstraints = false
        keyboardEmptyOverlayView.layer?.cornerRadius = 12
        keyboardEmptyOverlayView.isHidden = true

        emptyStateBadgeView = EmptyStateBadgeView(text: NSLocalizedString("keyboardHeatmap.noData", comment: ""))
        emptyStateBadgeView.isHidden = true
        emptyStateBadgeView.translatesAutoresizingMaskIntoConstraints = false

        heatmapContainer.addSubview(keyboardHeatmapView)
        heatmapContainer.addSubview(keyboardEmptyOverlayView)
        heatmapContainer.addSubview(emptyStateBadgeView)

        NSLayoutConstraint.activate([
            keyboardHeatmapView.leadingAnchor.constraint(equalTo: heatmapContainer.leadingAnchor, constant: 12),
            keyboardHeatmapView.trailingAnchor.constraint(equalTo: heatmapContainer.trailingAnchor, constant: -12),
            keyboardHeatmapView.topAnchor.constraint(equalTo: heatmapContainer.topAnchor, constant: 10),
            keyboardHeatmapView.bottomAnchor.constraint(equalTo: heatmapContainer.bottomAnchor, constant: -10),
            keyboardHeatmapView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),

            keyboardEmptyOverlayView.leadingAnchor.constraint(equalTo: keyboardHeatmapView.leadingAnchor),
            keyboardEmptyOverlayView.trailingAnchor.constraint(equalTo: keyboardHeatmapView.trailingAnchor),
            keyboardEmptyOverlayView.topAnchor.constraint(equalTo: keyboardHeatmapView.topAnchor),
            keyboardEmptyOverlayView.bottomAnchor.constraint(equalTo: keyboardHeatmapView.bottomAnchor),

            emptyStateBadgeView.centerXAnchor.constraint(equalTo: heatmapContainer.centerXAnchor),
            emptyStateBadgeView.centerYAnchor.constraint(equalTo: heatmapContainer.centerYAnchor)
        ])

        containerStack.addArrangedSubview(heatmapContainer)
        heatmapContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor).isActive = true
    }

    private func makeControlButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func makeIconControlButton(systemName: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.setButtonType(.momentaryPushIn)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func makeDatePickerButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(toggleDatePickerPopover))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        button.contentTintColor = .labelColor
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 78).isActive = true
        return button
    }

    private func updateDatePickerButtonTitle(_ title: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        datePickerButton.attributedTitle = attributedTitle
        datePickerButton.attributedAlternateTitle = attributedTitle
    }

    private func makeDatePickerPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = HeatmapDatePickerPopoverViewController.contentSize
        popover.contentViewController = datePickerViewController
        return popover
    }

    func resetToTodayAndRefresh() {
        selectedDate = clampedDate(Calendar.current.startOfDay(for: Date()))
        refreshData()
    }

    func refreshData() {
        let statsManager = StatsManager.shared
        dateBounds = statsManager.keyboardHeatmapDateBounds()
        selectedDate = clampedDate(selectedDate)

        let dayData = statsManager.keyboardHeatmapDay(for: selectedDate)
        let visibleCounts = dayData.keyCounts.filter { KeyboardHeatmapView.supportedKeyIDs.contains($0.key) }

        keyboardHeatmapView.apply(keyCounts: visibleCounts)

        let totalFormatted = numberFormatter.string(from: NSNumber(value: dayData.totalKeyPresses)) ?? "\(dayData.totalKeyPresses)"
        let activeKeys = visibleCounts.values.filter { $0 > 0 }.count
        let activeFormatted = numberFormatter.string(from: NSNumber(value: activeKeys)) ?? "\(activeKeys)"
        summaryLabel.stringValue = String(format: NSLocalizedString("keyboardHeatmap.summary", comment: ""), totalFormatted, activeFormatted)

        let hasActivity = dayData.totalKeyPresses > 0
        updateDatePickerButtonTitle(displayDateString(for: selectedDate))
        emptyStateBadgeView.isHidden = hasActivity
        keyboardEmptyOverlayView.isHidden = hasActivity
        keyboardHeatmapView.alphaValue = 1
        updateDateNavigationState()
        syncDatePickerState()
    }

    private func displayDateString(for date: Date) -> String {
        let calendar = Calendar.current
        let preferredLocalization = Bundle.main.preferredLocalizations.first ?? ""
        let preferredLanguage = Locale.preferredLanguages.first ?? ""
        let selectedYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: Date())
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        if preferredLocalization.hasPrefix("zh") || preferredLanguage.hasPrefix("zh") {
            if selectedYear == currentYear {
                return "\(month)月\(day)日"
            }
            return "\(selectedYear)年\(month)月\(day)日"
        }

        if selectedYear == currentYear {
            return dateFormatterWithoutYear.string(from: date)
        }
        return dateFormatterWithYear.string(from: date)
    }

    @objc private func showPreviousDay() {
        let calendar = Calendar.current
        guard let previous = calendar.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        guard previous >= dateBounds.start else { return }
        transitionToDate(previous)
    }

    @objc private func showNextDay() {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        guard next <= dateBounds.end else { return }
        transitionToDate(next)
    }

    @objc private func backToToday() {
        transitionToDate(Calendar.current.startOfDay(for: Date()))
    }

    @objc private func toggleDatePickerPopover() {
        if datePickerPopover.isShown {
            datePickerPopover.performClose(nil)
            return
        }

        syncDatePickerState()
        datePickerViewController.prepareForPresentation()
        datePickerPopover.contentSize = datePickerViewController.preferredContentSize
        datePickerPopover.show(relativeTo: datePickerButton.bounds, of: datePickerButton, preferredEdge: .maxY)
    }

    private func clampedDate(_ date: Date) -> Date {
        let normalized = Calendar.current.startOfDay(for: date)
        if normalized < dateBounds.start {
            return dateBounds.start
        }
        if normalized > dateBounds.end {
            return dateBounds.end
        }
        return normalized
    }

    private func updateDateNavigationState() {
        let today = Calendar.current.startOfDay(for: Date())
        previousDayButton.isEnabled = selectedDate > dateBounds.start
        nextDayButton.isEnabled = selectedDate < dateBounds.end
        backToTodayButton.isHidden = Calendar.current.isDate(selectedDate, inSameDayAs: today)
    }

    private func startLiveUpdates() {
        statsUpdateToken = StatsManager.shared.addStatsUpdateHandler { [weak self] in
            self?.scheduleRefresh()
        }
    }

    private func stopLiveUpdates() {
        if let token = statsUpdateToken {
            StatsManager.shared.removeStatsUpdateHandler(token)
        }
        statsUpdateToken = nil
        pendingRefresh = false
    }

    private func scheduleRefresh() {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshData()
            self.pendingRefresh = false
        }
    }

    private func transitionToDate(_ date: Date) {
        let targetDate = Calendar.current.startOfDay(for: date)
        guard targetDate != selectedDate else { return }

        let direction: DaySlideDirection = targetDate < selectedDate ? .left : .right
        let previousSnapshot = makeHeatmapSnapshot()
        selectedDate = targetDate
        refreshData()
        animateDayTransition(direction: direction, previousSnapshot: previousSnapshot)
    }

    private func syncDatePickerState() {
        datePickerViewController.update(selectedDate: selectedDate, bounds: dateBounds)
    }

    private func handleDateSelection(_ date: Date) {
        let targetDate = clampedDate(date)
        datePickerPopover.performClose(nil)
        guard targetDate != selectedDate else { return }
        transitionToDate(targetDate)
    }

    private func makeHeatmapSnapshot() -> NSImageView? {
        guard heatmapContainer.bounds.width > 0, heatmapContainer.bounds.height > 0 else { return nil }
        heatmapContainer.layoutSubtreeIfNeeded()

        let bounds = heatmapContainer.bounds
        guard let bitmap = heatmapContainer.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        heatmapContainer.cacheDisplay(in: bounds, to: bitmap)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)

        let imageView = NSImageView(image: image)
        imageView.frame = bounds
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        return imageView
    }

    private func animateDayTransition(direction: DaySlideDirection, previousSnapshot: NSImageView?) {
        guard !isDayTransitionAnimating else {
            previousSnapshot?.removeFromSuperview()
            return
        }
        guard let containerLayer = heatmapContainer.layer else {
            previousSnapshot?.removeFromSuperview()
            return
        }

        isDayTransitionAnimating = true
        let duration: CFTimeInterval = 0.16
        let slideDistance = max(260, heatmapContainer.bounds.width * 0.88)
        let timingFunction = CAMediaTimingFunction(name: .easeOut)

        if let previousSnapshot {
            heatmapContainer.addSubview(previousSnapshot, positioned: .above, relativeTo: nil)
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(timingFunction)
        CATransaction.setCompletionBlock { [weak self] in
            previousSnapshot?.removeFromSuperview()
            self?.isDayTransitionAnimating = false
        }

        if let previousLayer = previousSnapshot?.layer {
            let outgoingAnimation = CAAnimationGroup()
            outgoingAnimation.animations = [
                basicAnimation(keyPath: "transform.translation.x", from: 0, to: direction.outgoingOffset(distance: slideDistance)),
                basicAnimation(keyPath: "opacity", from: 1, to: 0)
            ]
            outgoingAnimation.duration = duration
            outgoingAnimation.timingFunction = timingFunction
            previousLayer.add(outgoingAnimation, forKey: "day-slide-out")
            previousLayer.opacity = 0
        }

        let incomingTargets: [NSView] = [keyboardHeatmapView, keyboardEmptyOverlayView, emptyStateBadgeView]
            .filter { !$0.isHidden }
        for view in incomingTargets {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            let targetOpacity = max(0, min(1, view.alphaValue))
            layer.removeAnimation(forKey: "day-slide-in")
            let incomingAnimation = CAAnimationGroup()
            incomingAnimation.animations = [
                basicAnimation(keyPath: "transform.translation.x", from: direction.incomingOffset(distance: slideDistance), to: 0),
                basicAnimation(keyPath: "opacity", from: 0, to: targetOpacity)
            ]
            incomingAnimation.duration = duration
            incomingAnimation.timingFunction = timingFunction
            layer.add(incomingAnimation, forKey: "day-slide-in")
        }

        containerLayer.layoutIfNeeded()
        CATransaction.commit()
    }

    private func basicAnimation(keyPath: String, from: CGFloat, to: CGFloat) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    private func updateAppearance() {
        view.layer?.backgroundColor = resolvedCGColor(NSColor.windowBackgroundColor, for: view)
        // The shared keyboard window's canvas owns its background across pages.
        heatmapContainer.layer?.backgroundColor = resolvedCGColor(NSColor.controlBackgroundColor, alpha: 0.92, for: view)
        heatmapContainer.layer?.borderColor = resolvedCGColor(NSColor.separatorColor, alpha: 0.18, for: view)
        applyCardShadow(heatmapContainer.layer, for: view)
        keyboardEmptyOverlayView.layer?.backgroundColor = resolvedCGColor(NSColor.windowBackgroundColor, alpha: 0.62, for: view)
        keyboardEmptyOverlayView.layer?.borderWidth = 0.5
        keyboardEmptyOverlayView.layer?.borderColor = resolvedCGColor(NSColor.separatorColor, alpha: 0.22, for: view)
        emptyStateBadgeView.updateAppearance(for: view)
        keyboardHeatmapView.needsDisplay = true
    }
}

private final class EmptyStateBadgeView: NSVisualEffectView {
    private let iconView: NSImageView
    private let messageLabel: NSTextField
    private let borderLayer = CAShapeLayer()

    init(text: String) {
        let iconImage = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        iconView = NSImageView(image: iconImage ?? NSImage())
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel = NSTextField(labelWithString: text)
        messageLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1
        layer?.addSublayer(borderLayer)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, messageLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        borderLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        borderLayer.frame = bounds
        let inset = borderLayer.lineWidth / 2
        let corner = max(0, 14 - inset)
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: corner,
            cornerHeight: corner,
            transform: nil
        )
    }

    func updateAppearance(for hostView: NSView) {
        let isDarkMode = hostView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let surfaceColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.controlBackgroundColor
        let neutralColor = surfaceColor.blended(withFraction: isDarkMode ? 0.22 : 0.10, of: .separatorColor)
            ?? (isDarkMode
                ? NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.25, alpha: 1)
                : NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))
        let accentColor = NSColor.controlAccentColor
        let accentBase = neutralColor.blended(withFraction: isDarkMode ? 0.34 : 0.24, of: accentColor) ?? accentColor

        let backgroundColor = neutralColor.blended(withFraction: isDarkMode ? 0.56 : 0.46, of: accentBase) ?? accentBase
        let borderColor = accentBase.blended(withFraction: isDarkMode ? 0.42 : 0.30, of: accentColor) ?? accentColor
        let textColor: NSColor = isDarkMode
            ? NSColor.white.withAlphaComponent(0.96)
            : NSColor.black

        layer?.backgroundColor = resolvedCGColor(backgroundColor, for: hostView)
        borderLayer.strokeColor = resolvedCGColor(borderColor, for: hostView)
        layer?.shadowOpacity = 0
        iconView.contentTintColor = textColor
        messageLabel.textColor = textColor
    }
}

private final class HeatmapDatePickerPopoverViewController: NSViewController {
    private static let contentInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    static let contentSize = NSSize(width: 220, height: 200)

    var onDateSelected: ((Date) -> Void)?
    private var didConfigureConstraints = false

    private lazy var datePicker: NSDatePicker = {
        let picker = NSDatePicker()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.focusRingType = .none
        picker.drawsBackground = false
        picker.backgroundColor = .clear
        picker.isBordered = false
        picker.isBezeled = false
        picker.target = self
        picker.action = #selector(datePicked(_:))
        return picker
    }()

    override func loadView() {
        view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(datePicker)
        configureConstraintsIfNeeded()
    }

    func update(selectedDate: Date, bounds: (start: Date, end: Date)) {
        datePicker.minDate = bounds.start
        datePicker.maxDate = bounds.end
        datePicker.dateValue = selectedDate
    }

    func prepareForPresentation() {
        _ = view
        configureConstraintsIfNeeded()
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    @objc private func datePicked(_ sender: NSDatePicker) {
        onDateSelected?(Calendar.current.startOfDay(for: sender.dateValue))
    }

    private func configureConstraintsIfNeeded() {
        guard !didConfigureConstraints else { return }
        didConfigureConstraints = true

        NSLayoutConstraint.activate([
            datePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            datePicker.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            datePicker.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Self.contentInset.left),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: datePicker.trailingAnchor, constant: Self.contentInset.right),
            datePicker.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: Self.contentInset.top),
            view.bottomAnchor.constraint(greaterThanOrEqualTo: datePicker.bottomAnchor, constant: Self.contentInset.bottom)
        ])
    }
}
