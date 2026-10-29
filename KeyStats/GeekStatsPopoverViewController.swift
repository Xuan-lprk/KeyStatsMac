import Cocoa
import SwiftUI

enum GeekPalette {
    static let background = NSColor(srgbRed: 0.030, green: 0.043, blue: 0.070, alpha: 1)
    static let panel = NSColor(srgbRed: 0.055, green: 0.078, blue: 0.115, alpha: 1)
    static let text = NSColor(srgbRed: 0.86, green: 0.94, blue: 0.97, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.43, green: 0.55, blue: 0.63, alpha: 1)
    static let cyan = NSColor(srgbRed: 0.20, green: 0.82, blue: 1.00, alpha: 1)
    static let amber = NSColor(srgbRed: 1.00, green: 0.64, blue: 0.24, alpha: 1)
    static let grid = NSColor(srgbRed: 0.20, green: 0.31, blue: 0.39, alpha: 1)
}

final class GeekBackdropView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        GeekPalette.background.setFill()
        bounds.fill()

        GeekPalette.cyan.withAlphaComponent(0.035).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        stride(from: CGFloat(12), through: bounds.width, by: 24).forEach { x in
            grid.move(to: CGPoint(x: x, y: 0))
            grid.line(to: CGPoint(x: x, y: bounds.height))
        }
        stride(from: CGFloat(0), through: bounds.height, by: 24).forEach { y in
            grid.move(to: CGPoint(x: 0, y: y))
            grid.line(to: CGPoint(x: bounds.width, y: y))
        }
        grid.stroke()

        GeekPalette.cyan.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: bounds.height - 2, width: 72, height: 2).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}

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

/// 统计详情弹出视图控制器
class GeekStatsPopoverViewController: NSViewController {
    var preferredSizeDidChange: ((NSSize) -> Void)?

    private let updatePermissionNoticeSuppressedKey = "update.permissionNoticeSuppressed"
    private let popoverContentWidth: CGFloat = 384
    private var keyBreakdownGridHeight: CGFloat { expandsKeys ? 106 : 32 }
    private let chartHeight: CGFloat = 96

    // MARK: - UI 组件
    private var containerView: NSView!
    private var titleLabel: NSTextField!
    private var statsStackView: NSStackView!
    private var keyBreakdownTitleLabel: NSTextField!
    private var keyBreakdownGridStack: NSStackView!
    private var keyPreviewStack: NSStackView!
    private var keyBreakdownArea: NSView!
    private var keyBreakdownHeight: NSLayoutConstraint!
    private var expandsKeys = false
    private var bottomSeparator: NSBox!
    private var keyPreviewCache: [String: GeekKeyCountRowView] = [:]
    private var keyBreakdownColumns: [NSStackView] = []
    private var keyBreakdownRowCache: [String: GeekKeyCountRowView] = [:]
    private var keyBreakdownDisplayedKeys: [String] = []
    private var historyTitleLabel: NSTextField!
    private var rangeControl: NSSegmentedControl!
    private var metricControl: NSSegmentedControl!
    private var chartStyleControl: NSSegmentedControl!
    private var chartView: GeekStatsChartView!
    private var historySummaryLabel: NSTextField!
    private var settingsButton: NSButton!
    private var appStatsButton: NSButton!
    private var allTimeStatsButton: NSButton!
    private var keyboardHeatmapButton: NSButton!
    private var pulseView: GeekTypingPulseView!
    private var pendingStatsRefresh = false
    private var statsUpdateToken: UUID?
    private var updateAvailabilityToken: UUID?
    private var appearanceObservation: NSKeyValueObservation?

    // 统计项视图
    private var keyPressView: GeekStatItemView!
    private var totalClickView: GeekStatItemView!
    private var kpsBadge: GeekKPSBadgeView!

    private var kpsRefreshTimer: Timer?
    private var kpsPopover: NSPopover?
    private var leftClickView: GeekStatItemView!
    private var rightClickView: GeekStatItemView!
    private var middleClickView: GeekStatItemView!
    private var sideBackClickView: GeekStatItemView!
    private var sideForwardClickView: GeekStatItemView!
    private var pointerDetailsStack: NSStackView!
    private var sideClickRow: NSStackView!
    private var mouseDistanceView: GeekStatItemView!
    private var scrollDistanceView: GeekStatItemView!


    // 底部按钮
    private var quitButton: NSButton!
    private var checkUpdatesButton: NSButton!
    private var permissionButton: NSButton!
    private var lastRangeSegment = 0
    private var lastMetricSegment = 0
    private var lastChartStyleSegment = 0

    // MARK: - 生命周期

    override func loadView() {
        // 创建主视图
        let mainView = GeekBackdropView(frame: NSRect(x: 0, y: 0, width: popoverContentWidth, height: 640))
        mainView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        mainView.appearance = NSAppearance(named: .darkAqua)
        mainView.wantsLayer = true
        self.view = mainView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateStats()
        updateAppearance()
        updatePreferredPopoverSizeIfNeeded()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAppearance()
            }
        }
        HelperXPCClient.shared.addStateObserver { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePermissionButtonVisibility()
            }
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        pulseView.start()
        updateStats()
        startLiveUpdates()
        startUpdateAvailabilityUpdates()
        startKPSRefreshTimer()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusPrimaryControl()
        updateAppearance()
        updatePreferredPopoverSizeIfNeeded()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopLiveUpdates()
        stopUpdateAvailabilityUpdates()
        stopKPSRefreshTimer()
        closeKPSPopover()
        pulseView.stop()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreferredPopoverSizeIfNeeded(layoutIfNeeded: false)
    }

    deinit {
        stopLiveUpdates()
        stopUpdateAvailabilityUpdates()
        appearanceObservation = nil
    }

    // MARK: - UI 设置

    private func setupUI() {
        containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 标题
        titleLabel = createLabel(text: "01  " + NSLocalizedString("geek.today", comment: ""), fontSize: 10, weight: .bold)
        titleLabel.textColor = GeekPalette.secondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18).isActive = true
        containerView.addSubview(titleLabel)

        // KPS 徽章（放在标题右侧，单行显示 KPS|CPS）
        kpsBadge = GeekKPSBadgeView()
        kpsBadge.onTap = { [weak self] in self?.toggleKPSPopover() }
        kpsBadge.translatesAutoresizingMaskIntoConstraints = false
        updateKPSBadge()
        containerView.addSubview(kpsBadge)

        permissionButton = NSButton(title: NSLocalizedString("button.permission", comment: ""), target: self, action: #selector(requestPermission))
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .regular
        permissionButton.contentTintColor = GeekPalette.amber
        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(permissionButton)
        let todayActions = NSStackView(views: [kpsBadge, permissionButton])
        todayActions.spacing = 8
        todayActions.alignment = .centerY
        todayActions.detachesHiddenViews = true
        todayActions.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(todayActions)

        // 两个主指标保持一眼可读；鼠标明细使用紧凑数据行。
        keyPressView = GeekStatItemView(icon: "keyboard", title: NSLocalizedString("stats.keyPresses", comment: ""), value: "0", prominent: true, accentColor: GeekPalette.cyan)
        totalClickView = GeekStatItemView(icon: "computermouse", title: NSLocalizedString("stats.totalClicks", comment: ""), value: "0", prominent: true, accentColor: GeekPalette.amber)

        func pointerItem(_ shortKey: String, _ fullKey: String) -> GeekStatItemView {
            GeekStatItemView(icon: "", title: NSLocalizedString(shortKey, comment: ""), value: "0", compact: true,
                         fullTitle: NSLocalizedString(fullKey, comment: ""))
        }
        leftClickView = pointerItem("popover.mouse.left", "stats.leftClicks")
        rightClickView = pointerItem("popover.mouse.right", "stats.rightClicks")
        middleClickView = pointerItem("popover.mouse.middle", "stats.middleClicks")
        sideBackClickView = pointerItem("popover.mouse.back", "stats.sideBackClicks")
        sideForwardClickView = pointerItem("popover.mouse.forward", "stats.sideForwardClicks")
        mouseDistanceView = pointerItem("popover.mouse.movement", "stats.mouseDistance")
        scrollDistanceView = pointerItem("popover.mouse.scroll", "stats.scrollDistance")

        let summaryRow = NSStackView(views: [keyPressView, totalClickView])
        summaryRow.orientation = .horizontal
        summaryRow.spacing = 20
        summaryRow.distribution = .fillEqually
        summaryRow.alignment = .centerY
        summaryRow.heightAnchor.constraint(equalTo: keyPressView.heightAnchor).isActive = true
        summaryRow.translatesAutoresizingMaskIntoConstraints = false
        summaryRow.widthAnchor.constraint(equalToConstant: popoverContentWidth - 36).isActive = true

        statsStackView = NSStackView(views: [summaryRow])
        statsStackView.orientation = .vertical
        statsStackView.alignment = .leading
        statsStackView.distribution = .fill
        statsStackView.spacing = 0
        statsStackView.detachesHiddenViews = true
        statsStackView.setContentHuggingPriority(.required, for: .vertical)
        statsStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statsStackView)

        pulseView = GeekTypingPulseView()
        pulseView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pulseView)

        func makePointerRow(_ views: [GeekStatItemView]) -> NSStackView {
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 12
            row.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return row
        }

        sideClickRow = makePointerRow([sideBackClickView, sideForwardClickView])
        pointerDetailsStack = NSStackView(views: [makePointerRow([leftClickView, middleClickView, rightClickView]),
                                                sideClickRow, makePointerRow([mouseDistanceView, scrollDistanceView])])
        pointerDetailsStack.orientation = .vertical
        pointerDetailsStack.alignment = .leading
        pointerDetailsStack.distribution = .fill
        pointerDetailsStack.spacing = 2
        pointerDetailsStack.detachesHiddenViews = true
        for row in pointerDetailsStack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: pointerDetailsStack.widthAnchor).isActive = true
        }
        pointerDetailsStack.setContentHuggingPriority(.required, for: .vertical)
        pointerDetailsStack.setContentCompressionResistancePriority(.required, for: .vertical)
        pointerDetailsStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pointerDetailsStack)

        // 键位统计标题
        keyBreakdownTitleLabel = createLabel(text: "02  " + NSLocalizedString("geek.topKeys", comment: ""), fontSize: 10, weight: .bold)
        keyBreakdownTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        keyBreakdownTitleLabel.textColor = GeekPalette.secondary
        keyBreakdownTitleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        containerView.addSubview(keyBreakdownTitleLabel)

        keyboardHeatmapButton = NSButton(title: NSLocalizedString("popover.growthKeyboard", comment: ""), target: self, action: #selector(showKeyboardHeatmap))
        keyboardHeatmapButton.bezelStyle = .recessed
        keyboardHeatmapButton.showsBorderOnlyWhileMouseInside = true
        keyboardHeatmapButton.controlSize = .small
        keyboardHeatmapButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        keyboardHeatmapButton.contentTintColor = GeekPalette.cyan
        keyboardHeatmapButton.toolTip = NSLocalizedString("keyboardVisualization.title", comment: "")
        keyboardHeatmapButton.setAccessibilityLabel(NSLocalizedString("popover.growthKeyboardHint", comment: ""))
        keyboardHeatmapButton.translatesAutoresizingMaskIntoConstraints = false
        keyboardHeatmapButton.setContentHuggingPriority(.required, for: .horizontal)
        keyboardHeatmapButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        containerView.addSubview(keyboardHeatmapButton)
        keyBreakdownTitleLabel.heightAnchor.constraint(greaterThanOrEqualTo: keyboardHeatmapButton.heightAnchor).isActive = true

        // 五列、按行排名；少量键位也保持同一格宽。
        keyBreakdownArea = NSView()
        keyBreakdownArea.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(keyBreakdownArea)
        keyPreviewStack = NSStackView()
        keyPreviewStack.orientation = .horizontal
        keyPreviewStack.distribution = .fillEqually
        keyPreviewStack.spacing = 8
        keyPreviewStack.translatesAutoresizingMaskIntoConstraints = false
        keyBreakdownArea.addSubview(keyPreviewStack)
        keyBreakdownGridStack = NSStackView()
        keyBreakdownGridStack.orientation = .horizontal
        keyBreakdownGridStack.spacing = 8
        keyBreakdownGridStack.distribution = .fillEqually
        keyBreakdownGridStack.alignment = .top
        keyBreakdownGridStack.translatesAutoresizingMaskIntoConstraints = false
        keyBreakdownArea.addSubview(keyBreakdownGridStack)
        for body in [keyPreviewStack!, keyBreakdownGridStack!] {
            NSLayoutConstraint.activate([
                body.topAnchor.constraint(equalTo: keyBreakdownArea.topAnchor),
                body.leadingAnchor.constraint(equalTo: keyBreakdownArea.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: keyBreakdownArea.trailingAnchor),
                body.heightAnchor.constraint(equalToConstant: body === keyPreviewStack ? 32 : 106)
            ])
        }
        keyBreakdownHeight = keyBreakdownArea.heightAnchor.constraint(equalToConstant: keyBreakdownGridHeight)
        keyBreakdownHeight.isActive = true

        keyBreakdownColumns = (0..<5).map { _ in
            let column = NSStackView()
            column.orientation = .vertical
            column.spacing = 5
            column.alignment = .leading
            column.distribution = .fill
            column.translatesAutoresizingMaskIntoConstraints = false
            keyBreakdownGridStack.addArrangedSubview(column)
            return column
        }

        // 历史趋势标题
        historyTitleLabel = createLabel(text: "03  " + NSLocalizedString("geek.history", comment: ""), fontSize: 10, weight: .bold)
        historyTitleLabel.textColor = GeekPalette.secondary
        historyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(historyTitleLabel)

        // 时间范围
        rangeControl = NSSegmentedControl(labels: [
            NSLocalizedString("history.range.week", comment: ""),
            NSLocalizedString("history.range.month", comment: "")
        ],
                                          trackingMode: .selectOne,
                                          target: self,
                                          action: #selector(historyControlsChanged))
        rangeControl.selectedSegment = 0
        rangeControl.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(rangeControl)

        // 指标选择
        metricControl = NSSegmentedControl(labels: [
            NSLocalizedString("history.metric.keys", comment: ""),
            NSLocalizedString("history.metric.clicks", comment: ""),
            NSLocalizedString("history.metric.move", comment: ""),
            NSLocalizedString("history.metric.scroll", comment: "")
        ],
                                           trackingMode: .selectOne,
                                           target: self,
                                           action: #selector(historyControlsChanged))
        metricControl.selectedSegment = 0
        metricControl.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(metricControl)

        // 图表样式
        chartStyleControl = NSSegmentedControl(labels: [
            NSLocalizedString("history.chart.line", comment: ""),
            NSLocalizedString("history.chart.bar", comment: "")
        ],
                                               trackingMode: .selectOne,
                                               target: self,
                                               action: #selector(historyControlsChanged))
        chartStyleControl.selectedSegment = 0
        chartStyleControl.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(chartStyleControl)
        for control in [rangeControl!, metricControl!, chartStyleControl!] {
            control.controlSize = .small
            control.segmentStyle = .texturedRounded
            control.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            control.selectedSegmentBezelColor = GeekPalette.cyan.withAlphaComponent(0.28)
        }
        historyTitleLabel.heightAnchor.constraint(greaterThanOrEqualTo: rangeControl.heightAnchor).isActive = true
        for (index, symbol) in ["chart.xyaxis.line", "chart.bar"].enumerated() {
            let label = chartStyleControl.label(forSegment: index) ?? ""
            chartStyleControl.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            chartStyleControl.setLabel("", forSegment: index)
            chartStyleControl.setToolTip(label, forSegment: index)
            chartStyleControl.setWidth(28, forSegment: index)
        }
        rangeControl.setAccessibilityLabel(NSLocalizedString("popover.historyRange", comment: ""))
        metricControl.setAccessibilityLabel(NSLocalizedString("popover.historyMetric", comment: ""))
        chartStyleControl.setAccessibilityLabel(NSLocalizedString("popover.chartStyle", comment: ""))

        // 图表视图
        chartView = GeekStatsChartView()
        chartView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(chartView)
        lastRangeSegment = rangeControl.selectedSegment
        lastMetricSegment = metricControl.selectedSegment
        lastChartStyleSegment = chartStyleControl.selectedSegment

        // 汇总
        historySummaryLabel = createLabel(
            text: String(format: NSLocalizedString("history.total", comment: ""), "0"),
            fontSize: 11,
            weight: .regular
        )
        historySummaryLabel.textColor = GeekPalette.secondary
        historySummaryLabel.alignment = .right
        historySummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(historySummaryLabel)

        // 底部分隔线
        bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator
        bottomSeparator.borderColor = GeekPalette.grid
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bottomSeparator)

        // 按钮容器
        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false


        checkUpdatesButton = NSButton(title: NSLocalizedString("button.checkUpdates", comment: ""), target: self, action: #selector(checkForUpdates))
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.controlSize = .regular
        checkUpdatesButton.isHidden = true

        // 退出按钮
        quitButton = NSButton(title: NSLocalizedString("button.quit", comment: ""), target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.bezelStyle = .recessed
        quitButton.showsBorderOnlyWhileMouseInside = true
        quitButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        quitButton.contentTintColor = GeekPalette.secondary
        checkUpdatesButton.controlSize = .small
        checkUpdatesButton.bezelStyle = .recessed
        checkUpdatesButton.showsBorderOnlyWhileMouseInside = true
        checkUpdatesButton.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        checkUpdatesButton.contentTintColor = GeekPalette.cyan

        buttonStack.addArrangedSubview(checkUpdatesButton)
        buttonStack.addArrangedSubview(quitButton)

        settingsButton = makeSymbolButton(systemName: "gearshape",
                                          fallbackTitle: NSLocalizedString("settings.title", comment: ""),
                                          pointSize: 14,
                                          weight: .regular,
                                          action: #selector(openSettings))
        settingsButton.toolTip = NSLocalizedString("settings.title", comment: "")
        settingsButton.setAccessibilityLabel(NSLocalizedString("settings.title", comment: ""))
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)
        settingsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        appStatsButton = makeSymbolButton(systemName: "square.grid.2x2",
                                          fallbackTitle: NSLocalizedString("appStats.button", comment: ""),
                                          pointSize: 14,
                                          weight: .regular,
                                          action: #selector(showAppStats))
        appStatsButton.toolTip = NSLocalizedString("appStats.button", comment: "")
        appStatsButton.setAccessibilityLabel(NSLocalizedString("appStats.button", comment: ""))
        appStatsButton.imageScaling = .scaleProportionallyDown
        appStatsButton.setContentHuggingPriority(.required, for: .horizontal)
        appStatsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            appStatsButton.widthAnchor.constraint(equalToConstant: 28),
            appStatsButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        allTimeStatsButton = makeSymbolButton(systemName: "chart.bar.xaxis",
                                              fallbackTitle: NSLocalizedString("allTimeStats.button", comment: ""),
                                              pointSize: 14,
                                              weight: .regular,
                                              action: #selector(showAllTimeStats))
        allTimeStatsButton.toolTip = NSLocalizedString("allTimeStats.button", comment: "")
        allTimeStatsButton.setAccessibilityLabel(NSLocalizedString("allTimeStats.button", comment: ""))
        allTimeStatsButton.imageScaling = .scaleProportionallyDown
        allTimeStatsButton.setContentHuggingPriority(.required, for: .horizontal)
        allTimeStatsButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            allTimeStatsButton.widthAnchor.constraint(equalToConstant: 28),
            allTimeStatsButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 12
        footerStack.translatesAutoresizingMaskIntoConstraints = false

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        buttonStack.setContentHuggingPriority(.required, for: .horizontal)
        buttonStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        footerStack.addArrangedSubview(settingsButton)
        footerStack.addArrangedSubview(appStatsButton)
        footerStack.addArrangedSubview(allTimeStatsButton)
        footerStack.setCustomSpacing(6, after: settingsButton)
        footerStack.setCustomSpacing(6, after: appStatsButton)
        footerStack.setCustomSpacing(6, after: allTimeStatsButton)
        footerStack.addArrangedSubview(footerSpacer)
        footerStack.addArrangedSubview(buttonStack)

        containerView.addSubview(footerStack)

        NSLayoutConstraint.activate([
            pulseView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            pulseView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            pulseView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            pulseView.heightAnchor.constraint(equalToConstant: 132),

            titleLabel.heightAnchor.constraint(greaterThanOrEqualTo: todayActions.heightAnchor),
            titleLabel.topAnchor.constraint(equalTo: pulseView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            todayActions.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            todayActions.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            todayActions.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),

            statsStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            statsStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            statsStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),

            keyBreakdownTitleLabel.topAnchor.constraint(equalTo: statsStackView.bottomAnchor, constant: 12),
            keyBreakdownTitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            keyboardHeatmapButton.centerYAnchor.constraint(equalTo: keyBreakdownTitleLabel.centerYAnchor),
            keyboardHeatmapButton.leadingAnchor.constraint(greaterThanOrEqualTo: keyBreakdownTitleLabel.trailingAnchor, constant: 8),
            keyboardHeatmapButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            keyBreakdownArea.topAnchor.constraint(equalTo: keyBreakdownTitleLabel.bottomAnchor, constant: 8),
            keyBreakdownArea.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            keyBreakdownArea.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),

            historyTitleLabel.topAnchor.constraint(equalTo: keyBreakdownArea.bottomAnchor, constant: 14),
            historyTitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            rangeControl.centerYAnchor.constraint(equalTo: historyTitleLabel.centerYAnchor),
            rangeControl.leadingAnchor.constraint(greaterThanOrEqualTo: historyTitleLabel.trailingAnchor, constant: 8),
            rangeControl.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            metricControl.topAnchor.constraint(equalTo: historyTitleLabel.bottomAnchor, constant: 6),
            metricControl.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            metricControl.trailingAnchor.constraint(equalTo: chartStyleControl.leadingAnchor, constant: -8),
            chartStyleControl.centerYAnchor.constraint(equalTo: metricControl.centerYAnchor),
            chartStyleControl.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            chartView.topAnchor.constraint(equalTo: metricControl.bottomAnchor, constant: 6),
            chartView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            chartView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            chartView.heightAnchor.constraint(equalToConstant: chartHeight),
            historySummaryLabel.topAnchor.constraint(equalTo: chartView.bottomAnchor, constant: 2),
            historySummaryLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            historySummaryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 18),

            pointerDetailsStack.topAnchor.constraint(equalTo: historySummaryLabel.bottomAnchor, constant: 10),
            pointerDetailsStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            pointerDetailsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            bottomSeparator.topAnchor.constraint(equalTo: pointerDetailsStack.bottomAnchor, constant: 12),
            bottomSeparator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            bottomSeparator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            footerStack.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 6),
            footerStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 18),
            footerStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18),
            footerStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10)
        ])
    }

    private func createLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    private func makeSymbolButton(systemName: String,
                                  fallbackTitle: String,
                                  pointSize: CGFloat? = nil,
                                  weight: NSFont.Weight = .regular,
                                  action: Selector) -> NSButton {
        var image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        if let pointSize = pointSize, let baseImage = image {
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            image = baseImage.withSymbolConfiguration(configuration)
        }

        if let image = image {
            let button = NSButton(image: image, target: self, action: action)
            button.bezelStyle = .recessed
            button.showsBorderOnlyWhileMouseInside = true
            button.controlSize = .small
            button.imagePosition = .imageOnly
            button.contentTintColor = GeekPalette.secondary
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }

        let button = NSButton(title: fallbackTitle, target: self, action: action)
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - 更新统计数据

    private func updateStats() {
        let stats = StatsManager.shared.displayCurrentStats()
        let hasSideClickData = (stats.sideBackClicks + stats.sideForwardClicks) > 0

        keyPressView.updateValue(formatNumber(stats.keyPresses))
        totalClickView.updateValue(formatNumber(stats.totalClicks))
        updateKPSBadge()
        leftClickView.updateValue(formatNumber(stats.leftClicks))
        rightClickView.updateValue(formatNumber(stats.rightClicks))
        middleClickView.updateValue(formatNumber(stats.middleClicks))
        sideBackClickView.updateValue(formatNumber(stats.sideBackClicks))
        sideForwardClickView.updateValue(formatNumber(stats.sideForwardClicks))
        applySideClickRowVisibility(hasSideClickData)
        mouseDistanceView.updateValue(stats.formattedMouseDistance)
        scrollDistanceView.updateValue(stats.formattedScrollDistance)
        updateKeyBreakdown()
        updateHistorySection()
        updatePermissionButtonVisibility()
        updatePreferredPopoverSizeIfNeeded()
    }

    func prepareForPopoverPresentation() {
        if !isViewLoaded {
            _ = view
        }
        updateStats()
        updatePreferredPopoverSizeIfNeeded()
    }

    private func startLiveUpdates() {
        statsUpdateToken = StatsManager.shared.addStatsUpdateHandler { [weak self] in
            self?.scheduleStatsRefresh()
        }
    }

    private func stopLiveUpdates() {
        if let token = statsUpdateToken {
            StatsManager.shared.removeStatsUpdateHandler(token)
        }
        statsUpdateToken = nil
        pendingStatsRefresh = false
    }

    // MARK: - KPS 实时刷新

    private func updateKPSBadge() {
        let stats = StatsManager.shared.currentStats
        kpsBadge.update(peakKPS: stats.peakKPS, peakCPS: stats.peakCPS)
    }

    private func refreshLiveRates() {
        updateKPSBadge()
        let rates = StatsManager.shared.currentRatesSnapshot()
        pulseView.append(currentKPS: rates.currentKPS, currentCPS: rates.currentCPS)
    }

    private func startKPSRefreshTimer() {
        kpsRefreshTimer?.invalidate()
        refreshLiveRates()
        kpsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.refreshLiveRates()
        }
        if let timer = kpsRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopKPSRefreshTimer() {
        kpsRefreshTimer?.invalidate()
        kpsRefreshTimer = nil
    }

    private func toggleKPSPopover() {
        if let popover = kpsPopover, popover.isShown {
            closeKPSPopover()
        } else {
            showKPSPopover()
        }
    }

    private func showKPSPopover() {
        closeKPSPopover()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: KPSDetailView())
        popover.contentSize = NSSize(width: 220, height: 170)
        self.kpsPopover = popover
        // 在徽章正下方弹出：用徽章底边的零高度矩形作为锚点
        let bottomRect = NSRect(x: 0, y: 0, width: kpsBadge.bounds.width, height: 1)
        popover.show(relativeTo: bottomRect, of: kpsBadge, preferredEdge: .minY)
    }

    private func closeKPSPopover() {
        kpsPopover?.performClose(nil)
        kpsPopover = nil
    }

    private func startUpdateAvailabilityUpdates() {
        if let token = updateAvailabilityToken {
            UpdateManager.shared.removeUpdateButtonStateHandler(token)
        }

        updateAvailabilityToken = UpdateManager.shared.addUpdateButtonStateHandler { [weak self] state in
            self?.applyUpdateButtonState(state)
        }
        UpdateManager.shared.probeForUpdateAvailability()
    }

    private func stopUpdateAvailabilityUpdates() {
        if let token = updateAvailabilityToken {
            UpdateManager.shared.removeUpdateButtonStateHandler(token)
        }
        updateAvailabilityToken = nil
    }

    private func applyUpdateButtonState(_ state: UpdateButtonState) {
        let manualReleases = UpdateManager.shared.usesManualReleasePage
        checkUpdatesButton.title = NSLocalizedString(manualReleases ? "button.viewReleases" : "button.checkUpdates", comment: "")
        checkUpdatesButton.toolTip = manualReleases ? NSLocalizedString("update.manualReleases.help", comment: "") : nil
        checkUpdatesButton.isHidden = manualReleases ? false : state.isHidden
        checkUpdatesButton.isEnabled = manualReleases ? AppLaunchMode.current == .normal : state.isEnabled
        updatePreferredPopoverSizeIfNeeded()
    }

    private func scheduleStatsRefresh() {
        guard !pendingStatsRefresh else { return }
        pendingStatsRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateStats()
            self.pulseView.emitImpulse()
            self.pendingStatsRefresh = false
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatRate(_ rate: Double) -> String {
        if rate <= 0 { return "0" }
        return String(format: "%.1f", rate)
    }

    private func updateKeyBreakdown() {
        let items = StatsManager.shared.keyPressBreakdownSorted()
        let hasItems = !items.isEmpty
        expandsKeys = items.count > 5
        keyPreviewStack.isHidden = expandsKeys
        keyBreakdownGridStack.isHidden = !expandsKeys
        keyBreakdownHeight.constant = keyBreakdownGridHeight
        if !expandsKeys {
            let top = Array(items.prefix(5))
            let keys = top.map { $0.key }
            if keys == keyBreakdownDisplayedKeys && !keyPreviewStack.arrangedSubviews.isEmpty {
                for item in top { keyPreviewCache[item.key]?.update(key: item.key, count: formatNumber(item.count)) }
                return
            }
            keyPreviewStack.arrangedSubviews.forEach { keyPreviewStack.removeArrangedSubview($0); $0.removeFromSuperview() }
            keyPreviewCache = keyPreviewCache.filter { keys.contains($0.key) }
            for item in top {
                let tile = keyPreviewCache[item.key] ?? GeekKeyCountRowView(key: item.key, count: formatNumber(item.count), vertical: true)
                keyPreviewCache[item.key] = tile
                tile.update(key: item.key, count: formatNumber(item.count))
                keyPreviewStack.addArrangedSubview(tile)
            }
            if !hasItems {
                let empty = createLabel(text: NSLocalizedString("keyBreakdown.empty", comment: ""), fontSize: 12, weight: .regular)
                empty.textColor = GeekPalette.secondary
                keyPreviewStack.addArrangedSubview(empty)
            }
            if hasItems {
                for _ in top.count..<5 { keyPreviewStack.addArrangedSubview(NSView()) }
            }
            keyBreakdownDisplayedKeys = keys
            return
        }
        let limitedItems = Array(items.prefix(15))
        let newKeys = limitedItems.map { $0.key }
        if newKeys == keyBreakdownDisplayedKeys {
            for item in limitedItems {
                if let row = keyBreakdownRowCache[item.key] {
                    row.update(key: item.key, count: formatNumber(item.count))
                }
            }
            return
        }
        for column in keyBreakdownColumns {
            column.arrangedSubviews.forEach {
                column.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }
        for (index, item) in limitedItems.enumerated() {
            let columnIndex = index % 5
            if columnIndex >= keyBreakdownColumns.count { break }
            let row = keyBreakdownRowCache[item.key] ?? {
                let row = GeekKeyCountRowView(key: item.key, count: formatNumber(item.count), vertical: true)
                keyBreakdownRowCache[item.key] = row
                return row
            }()
            let column = keyBreakdownColumns[columnIndex]
            column.addArrangedSubview(row)
            row.constrainWidth(to: column)
            row.update(key: item.key, count: formatNumber(item.count))
        }
        keyBreakdownDisplayedKeys = newKeys
    }

    @objc private func historyControlsChanged() {
        let currentRange = rangeControl.selectedSegment
        let currentMetric = metricControl.selectedSegment
        let currentStyle = chartStyleControl.selectedSegment
        let direction: GeekStatsChartView.SlideDirection
        if currentMetric != lastMetricSegment {
            direction = currentMetric > lastMetricSegment ? .right : .left
        } else if currentRange != lastRangeSegment {
            direction = currentRange > lastRangeSegment ? .right : .left
        } else if currentStyle != lastChartStyleSegment {
            direction = currentStyle > lastChartStyleSegment ? .right : .left
        } else {
            return
        }
        if currentRange != lastRangeSegment {
            AppDelegate.trackClick("chart_range", properties: [
                "range": currentRange == 0 ? "7d" : "30d"
            ])
        }
        if currentMetric != lastMetricSegment {
            let metric = currentMetricName(for: currentMetric)
            AppDelegate.trackClick("chart_metric", properties: [
                "metric": metric
            ])
        }
        if currentStyle != lastChartStyleSegment {
            AppDelegate.trackClick("chart_style", properties: [
                "style": currentStyle == 0 ? "line" : "bar"
            ])
        }
        lastRangeSegment = currentRange
        lastMetricSegment = currentMetric
        lastChartStyleSegment = currentStyle
        updateHistorySection(animated: true, slideDirection: direction)
    }

    private func updatePermissionButtonVisibility() {
        if case .connected(_, let granted) = HelperXPCClient.shared.state {
            permissionButton.isHidden = granted
        } else {
            permissionButton.isHidden = false
        }
    }

    private func focusPrimaryControl() {
        if !permissionButton.isHidden {
            view.window?.makeFirstResponder(permissionButton)
        } else {
            // Start without a focused button so typing Space into Input Pulse
            // does not activate the Growth Keyboard entry.
            view.window?.makeFirstResponder(nil)
        }
    }

    private func updateHistorySection(animated: Bool = false, slideDirection: GeekStatsChartView.SlideDirection? = nil) {
        let range = selectedRange()
        let metric = selectedMetric()
        let style = selectedChartStyle()

        let trendSeries = StatsManager.shared.historyTrendSeries(range: range, metric: metric)
        chartView.apply(series: trendSeries.display,
                        localSeries: trendSeries.local,
                        metric: metric,
                        range: range,
                        style: style,
                        animated: animated,
                        slideDirection: slideDirection)

        let total = trendSeries.display.reduce(0) { $0 + $1.value }
        let formatted = StatsManager.shared.formatHistoryValue(metric: metric, value: total)
        historySummaryLabel.stringValue = String(format: NSLocalizedString("history.total", comment: ""), formatted)
    }

    // MARK: - Appearance Updates

    private func updateAppearance() {
        // Setting appearance in loadView can synchronously call back before
        // self.view and the controls exist. Do not recursively load the view.
        guard isViewLoaded, chartView != nil else { return }
        view.needsDisplay = true
        updateKeyBreakdown()
        chartView.needsDisplay = true
    }

    private func selectedRange() -> StatsManager.HistoryRange {
        switch rangeControl.selectedSegment {
        case 0: return .week
        default: return .month
        }
    }

    private func selectedMetric() -> StatsManager.HistoryMetric {
        switch metricControl.selectedSegment {
        case 0: return .keyPresses
        case 1: return .clicks
        case 2: return .mouseDistance
        default: return .scrollDistance
        }
    }

    private func selectedChartStyle() -> GeekStatsChartView.Style {
        switch chartStyleControl.selectedSegment {
        case 1: return .bar
        default: return .line
        }
    }

    // MARK: - 按钮操作

    @objc private func openSettings() {
        AppDelegate.trackClick("open_settings")
        SettingsWindowController.shared.show()
        view.window?.performClose(nil)
    }

    @objc private func showAllTimeStats() {
        AppDelegate.trackClick("open_all_time_stats")
        AllTimeStatsWindowController.shared.show()
        view.window?.performClose(nil)
    }

    @objc private func showAppStats() {
        AppDelegate.trackClick("open_app_stats")
        AppStatsWindowController.shared.show()
        view.window?.performClose(nil)
    }

    @objc private func showKeyboardHeatmap() {
        AppDelegate.trackClick("open_keyboard_heatmap")
        KeyboardHeatmapWindowController.shared.show()
        view.window?.performClose(nil)
    }

    private func currentMetricName(for index: Int) -> String {
        switch index {
        case 0: return "key_presses"
        case 1: return "clicks"
        case 2: return "mouse_distance"
        case 3: return "scroll_distance"
        default: return "unknown"
        }
    }

    @objc private func requestPermission() {
        AppDelegate.shared?.requestAccessibilityPermission(analyticsSource: "popover_button")
        updatePermissionButtonVisibility()
    }

    @objc private func checkForUpdates() {
        guard showUpdatePermissionNoticeIfNeeded() else { return }
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func showUpdatePermissionNoticeIfNeeded() -> Bool {
        guard !UserDefaults.standard.bool(forKey: updatePermissionNoticeSuppressedKey) else {
            return true
        }

        let alert = NSAlert()
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        alert.messageText = NSLocalizedString("update.notice.title", comment: "")
        alert.informativeText = NSLocalizedString("update.notice.message", comment: "")
        alert.alertStyle = .informational
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = NSLocalizedString("update.notice.suppress", comment: "")
        alert.addButton(withTitle: NSLocalizedString("update.notice.continue", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("update.notice.cancel", comment: ""))

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: updatePermissionNoticeSuppressedKey)
        }
        return response == .alertFirstButtonReturn
    }

    private func applySideClickRowVisibility(_ shouldShow: Bool) {
        sideClickRow.isHidden = !shouldShow
    }

    private func updatePreferredPopoverSizeIfNeeded(layoutIfNeeded: Bool = true) {
        guard isViewLoaded else { return }
        if layoutIfNeeded { view.layoutSubtreeIfNeeded() }

        let statsRows = statsStackView.arrangedSubviews
        let statsRowsHeight = statsRows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.fittingSize.height
        }
        let statsSpacing = CGFloat(max(0, statsRows.count - 1)) * statsStackView.spacing

        let titleRowHeight = max(
            titleLabel.fittingSize.height,
            kpsBadge.fittingSize.height,
            permissionButton.isHidden ? 0 : permissionButton.fittingSize.height
        )

        let footerHeight = max(
            settingsButton.fittingSize.height,
            appStatsButton.fittingSize.height,
            allTimeStatsButton.fittingSize.height,
            quitButton.fittingSize.height,
            checkUpdatesButton.isHidden ? 0 : checkUpdatesButton.fittingSize.height
        )

        let keyBreakdownHeaderHeight = max(keyBreakdownTitleLabel.fittingSize.height, keyboardHeatmapButton.fittingSize.height)

        let computedHeight =
            8 + 132 + 12 + titleRowHeight +
            2 + statsRowsHeight + statsSpacing +
            12 + keyBreakdownHeaderHeight + 8 + keyBreakdownGridHeight +
            14 + historyTitleLabel.fittingSize.height +
            6 + metricControl.fittingSize.height +
            6 + chartHeight + 2 + historySummaryLabel.fittingSize.height +
            10 + pointerDetailsStack.fittingSize.height +
            12 + bottomSeparator.fittingSize.height + 6 + footerHeight + 10

        let targetSize = NSSize(width: popoverContentWidth, height: ceil(computedHeight))
        guard preferredContentSize != targetSize else { return }
        preferredContentSize = targetSize
        preferredSizeDidChange?(targetSize)
    }
}

// MARK: - 统计项动画数值

final class GeekAnimatedStatValueViewModel: ObservableObject {
    @Published var text: String

    init(text: String) {
        self.text = text
    }
}

struct GeekAnimatedStatValueView: View {
    @ObservedObject var viewModel: GeekAnimatedStatValueViewModel
    var prominent = false
    var compact = false
    var accentColor: NSColor?

    private var fontSize: CGFloat { compact ? 11 : (prominent ? 30 : 17) }
    private var textColor: Color { Color(nsColor: accentColor ?? GeekPalette.text) }

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                Text(viewModel.text)
                    .font(.system(size: fontSize, weight: (compact || prominent) ? .medium : .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
                    .contentTransition(.numericText())
            } else {
                Text(viewModel.text)
                    .font(.system(size: fontSize, weight: (compact || prominent) ? .medium : .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(compact ? 1 : (prominent ? 0.65 : 0.85))
        .animation(.default, value: viewModel.text)
    }
}

final class GeekAnimatedKeyCountViewModel: ObservableObject {
    @Published var text: String

    init(text: String) {
        self.text = text
    }
}

struct GeekAnimatedKeyCountView: View {
    @ObservedObject var viewModel: GeekAnimatedKeyCountViewModel

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                Text(viewModel.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: GeekPalette.cyan))
                    .contentTransition(.numericText())
            } else {
                Text(viewModel.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: GeekPalette.cyan))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .animation(.default, value: viewModel.text)
    }
}

// MARK: - 统计项视图

class GeekStatItemView: NSView {
    private var iconView: NSImageView!
    private var titleLabel: NSTextField!
    private var valueViewModel: GeekAnimatedStatValueViewModel!
    private var valueHostingView: NSHostingView<GeekAnimatedStatValueView>!

    init(icon: String, title: String, value: String, prominent: Bool = false, compact: Bool = false, fullTitle: String? = nil, accentColor: NSColor? = nil) {
        super.init(frame: .zero)
        setupUI(icon: icon, title: title, value: value, prominent: prominent, compact: compact, accentColor: accentColor)
        toolTip = fullTitle ?? title
        titleLabel.toolTip = fullTitle ?? title
        titleLabel.setAccessibilityLabel(fullTitle ?? title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(icon: String, title: String, value: String, prominent: Bool, compact: Bool, accentColor: NSColor?) {
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        // 图标
        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        iconView.contentTintColor = GeekPalette.secondary
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // 标题
        titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = GeekPalette.secondary
        titleLabel.toolTip = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // 数值（SwiftUI 动画）
        valueViewModel = GeekAnimatedStatValueViewModel(text: value)
        valueHostingView = NSHostingView(rootView: GeekAnimatedStatValueView(viewModel: valueViewModel, prominent: prominent, compact: compact, accentColor: accentColor))
        valueHostingView.translatesAutoresizingMaskIntoConstraints = false
        valueHostingView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueHostingView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(valueHostingView)

        if compact {
            iconView.isHidden = true
            titleLabel.lineBreakMode = .byClipping
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 18),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueHostingView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5),
                valueHostingView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                valueHostingView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            return
        }

        if prominent {
            iconView.isHidden = true
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 48),
                valueHostingView.topAnchor.constraint(equalTo: topAnchor),
                valueHostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                valueHostingView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                titleLabel.topAnchor.constraint(equalTo: valueHostingView.bottomAnchor, constant: 0),
                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
            ])
            return
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: prominent ? 54 : 38),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            valueHostingView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueHostingView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            valueHostingView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            valueHostingView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    func updateValue(_ value: String) {
        let updateBlock = {
            self.valueViewModel.text = value
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async {
                updateBlock()
            }
        }

        valueHostingView.invalidateIntrinsicContentSize()
        needsLayout = true
    }
}

// MARK: - 键位统计行

class GeekKeyCountRowView: NSView {
    private var keyLabel: NSTextField!
    private var countViewModel: GeekAnimatedKeyCountViewModel!
    private var countHostingView: NSHostingView<GeekAnimatedKeyCountView>!
    private var widthConstraint: NSLayoutConstraint?
    private var currentKey: String
    private static let symbolNameMap: [String: String] = [
        "Cmd": "command",
        "Shift": "shift",
        "Option": "option",
        "Ctrl": "control",
        "Fn": "globe",
        "Esc": "escape",
        "Escape": "escape",
        "Tab": "tab",
        "Return": "return",
        "Enter": "return",
        "Delete": "delete.left",
        "ForwardDelete": "delete.right",
        "Left": "arrow.left",
        "Right": "arrow.right",
        "Up": "arrow.up",
        "Down": "arrow.down"
    ]
    private static let squareSymbolKeys: Set<String> = ["Ctrl", "Control"]
    private static let mediaSymbols: [String: String] = [
        "BrightnessDown": "sun.min", "BrightnessUp": "sun.max",
        "VolumeDown": "speaker.wave.1.fill", "VolumeUp": "speaker.wave.3.fill",
        "Mute": "speaker.slash.fill", "PlayPause": "playpause.fill",
        "NextTrack": "forward.end.fill", "PreviousTrack": "backward.end.fill",
        "FastForward": "forward.fill", "Rewind": "backward.fill",
        "KeyboardBrightnessDown": "light.min", "KeyboardBrightnessUp": "light.max",
        "KeyboardBacklightToggle": "lightbulb"
    ]

    init(key: String, count: String, vertical: Bool = false) {
        self.currentKey = key
        super.init(frame: .zero)
        setupUI(key: key, count: count, vertical: vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI(key: String, count: String, vertical: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        let keyFont = NSFont.monospacedDigitSystemFont(ofSize: vertical ? 10 : 12, weight: .medium)
        keyLabel = NSTextField(labelWithAttributedString: Self.attributedKeyLabel(for: key, font: keyFont, appearance: effectiveAppearance, compact: true))
        keyLabel.font = keyFont
        keyLabel.textColor = .labelColor
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.maximumNumberOfLines = 1
        keyLabel.cell?.truncatesLastVisibleLine = true
        keyLabel.toolTip = key
        keyLabel.setAccessibilityValue(key)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyLabel)

        countViewModel = GeekAnimatedKeyCountViewModel(text: count)
        countHostingView = NSHostingView(rootView: GeekAnimatedKeyCountView(viewModel: countViewModel))
        countHostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countHostingView)

        if vertical {
            wantsLayer = true
            layer?.backgroundColor = GeekPalette.panel.withAlphaComponent(0.72).cgColor
            layer?.cornerRadius = 4
            layer?.borderWidth = 0.5
            layer?.borderColor = GeekPalette.cyan.withAlphaComponent(0.12).cgColor
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 32),
                keyLabel.topAnchor.constraint(equalTo: topAnchor),
                keyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                keyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
                countHostingView.centerXAnchor.constraint(equalTo: centerXAnchor),
                countHostingView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
                countHostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            return
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),

            keyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.trailingAnchor.constraint(lessThanOrEqualTo: countHostingView.leadingAnchor, constant: -8),

            countHostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            countHostingView.centerYAnchor.constraint(equalTo: centerYAnchor),
            countHostingView.leadingAnchor.constraint(greaterThanOrEqualTo: keyLabel.trailingAnchor, constant: 8)
        ])
    }

    func update(key: String, count: String) {
        currentKey = key
        applyKeyLabel()
        keyLabel.toolTip = key
        let updateBlock = {
            self.countViewModel.text = count
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async {
                updateBlock()
            }
        }

        countHostingView.invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func constrainWidth(to column: NSView) {
        widthConstraint?.isActive = false
        widthConstraint = widthAnchor.constraint(equalTo: column.widthAnchor)
        widthConstraint?.isActive = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyKeyLabel()
    }

    private func applyKeyLabel() {
        if let font = keyLabel.font {
            keyLabel.attributedStringValue = Self.attributedKeyLabel(for: currentKey, font: font, appearance: effectiveAppearance, compact: true)
        } else {
            keyLabel.stringValue = currentKey
        }
        keyLabel.setAccessibilityValue(currentKey)
    }

    static func attributedKeyLabel(for key: String, font: NSFont, appearance: NSAppearance? = nil, compact: Bool = false) -> NSAttributedString {
        let currentAppearance = appearance ?? NSApp.effectiveAppearance
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: GeekPalette.text
        ]
        let result = NSMutableAttributedString()

        for (index, part) in keyParts(from: key).enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\u{200A}", attributes: textAttributes))
            }
            if let badge = makeKeyBadge(for: part, font: font, appearance: currentAppearance, compact: compact) {
                let attachment = NSTextAttachment()
                attachment.image = badge
                let baselineOffset = (font.ascender + font.descender - badge.size.height) / 2 + 1
                attachment.bounds = CGRect(x: 0, y: baselineOffset, width: badge.size.width, height: badge.size.height)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: part, attributes: textAttributes))
            }
        }

        return result
    }

    private static func makeKeyBadge(for keyPart: String, font: NSFont, appearance: NSAppearance, compact: Bool) -> NSImage? {
        let contentPointSize = max(font.pointSize - 1, 10)
        let padding: CGFloat = compact && font.pointSize <= 10 ? 1.5 : 4
        let lineWidth: CGFloat = 0.8
        let cornerRadiusScale: CGFloat = 0.3
        let textFont = NSFont.systemFont(ofSize: contentPointSize, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: GeekPalette.text
        ]
        let textMetricsHeight = ("M" as NSString).size(withAttributes: textAttributes).height
        let badgeHeight = ceil(max(textMetricsHeight, contentPointSize) + padding * 2)

        if let symbolName = Self.symbolNameMap[keyPart] ?? (compact ? Self.mediaSymbols[keyPart] : nil),
           let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: keyPart)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: contentPointSize, weight: .medium)) {
            let symbolSize = symbol.size
            let forceSquare = Self.squareSymbolKeys.contains(keyPart)
            let symbolRectSize: NSSize
            let badgeWidth: CGFloat

            if forceSquare {
                let maxSide = contentPointSize
                let scale = min(maxSide / symbolSize.width, maxSide / symbolSize.height)
                symbolRectSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
                badgeWidth = badgeHeight
            } else {
                let aspectRatio = symbolSize.height > 0 ? (symbolSize.width / symbolSize.height) : 1
                let symbolHeight = contentPointSize
                let symbolWidth = symbolHeight * aspectRatio
                symbolRectSize = NSSize(width: symbolWidth, height: symbolHeight)
                badgeWidth = ceil(max(badgeHeight, symbolWidth + padding * 2))
            }
            let badgeSize = NSSize(width: badgeWidth, height: badgeHeight)
            return drawBadge(size: badgeSize, cornerRadius: badgeHeight * cornerRadiusScale, lineWidth: lineWidth, appearance: appearance, compact: compact) { rect in
                let symbolRect = NSRect(
                    x: rect.midX - symbolRectSize.width / 2,
                    y: rect.midY - symbolRectSize.height / 2,
                    width: symbolRectSize.width,
                    height: symbolRectSize.height
                )
                // 使用正确的方式绘制带颜色的 SF Symbol
                if let tintedSymbol = tintImage(symbol, with: GeekPalette.text) {
                    tintedSymbol.draw(in: symbolRect)
                } else {
                    symbol.draw(in: symbolRect)
                }
            }
        }

        let text = keyPart
        let textSize = (text as NSString).size(withAttributes: textAttributes)
        let contentHeight = max(contentPointSize, textSize.height)
        let badgeWidth = ceil(max(badgeHeight, textSize.width + padding * 2))
        let badgeSize = NSSize(width: badgeWidth, height: badgeHeight)
        return drawBadge(size: badgeSize, cornerRadius: badgeHeight * cornerRadiusScale, lineWidth: lineWidth, appearance: appearance, compact: compact) { rect in
            let textRect = NSRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: textAttributes)
        }
    }

    private static func drawBadge(size: NSSize, cornerRadius: CGFloat, lineWidth: CGFloat, appearance: NSAppearance, compact: Bool, content: (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.current?.shouldAntialias = true
            NSGraphicsContext.current?.imageInterpolation = .high

            let rect = NSRect(
                x: lineWidth / 2,
                y: lineWidth / 2,
                width: size.width - lineWidth,
                height: size.height - lineWidth
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            if compact {
                GeekPalette.cyan.withAlphaComponent(0.07).setFill()
                path.fill()
                GeekPalette.cyan.withAlphaComponent(0.18).setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            } else {
                GeekPalette.grid.withAlphaComponent(0.6).setFill()
                path.fill()
            }

            content(rect)
        }
        image.unlockFocus()
        return image
    }

    private static func keyParts(from key: String) -> [String] {
        guard key.contains("+") else { return [displayKeyPart(key)] }
        if key.hasSuffix("+") {
            var trimmed = String(key.dropLast())
            if trimmed.hasSuffix("+") {
                trimmed = String(trimmed.dropLast())
            }
            var parts = trimmed.split(separator: "+").map { displayKeyPart(String($0)) }
            parts.append("+")
            return parts.isEmpty ? [displayKeyPart(key)] : parts
        }
        return key.split(separator: "+").map { displayKeyPart(String($0)) }
    }

    private static func displayKeyPart(_ keyPart: String) -> String {
        switch keyPart {
        case "LeftShift":
            return "L Shift"
        case "RightShift":
            return "R Shift"
        case "LeftOption":
            return "L Option"
        case "RightOption":
            return "R Option"
        case "LeftCmd":
            return "L Cmd"
        case "RightCmd":
            return "R Cmd"
        default:
            return keyPart
        }
    }

    private static func tintImage(_ image: NSImage, with color: NSColor) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let tinted = NSImage(size: image.size)
        tinted.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            tinted.unlockFocus()
            return nil
        }

        let imageRect = NSRect(origin: .zero, size: image.size)

        // 使用图像作为遮罩，然后填充颜色
        context.saveGState()
        context.clip(to: imageRect, mask: cgImage)
        color.setFill()
        imageRect.fill()
        context.restoreGState()

        tinted.unlockFocus()
        return tinted
    }
}

// MARK: - 图表视图

class GeekStatsChartView: NSView {
    enum Style {
        case line
        case bar
    }

    enum SlideDirection {
        case left
        case right
    }

    var series: [(date: Date, value: Double)] = [] {
        didSet {
            hoverIndex = nil
            needsDisplay = true
        }
    }

    var localSeries: [(date: Date, value: Double)]? {
        didSet {
            hoverIndex = nil
            needsDisplay = true
        }
    }

    var metric: StatsManager.HistoryMetric = .keyPresses {
        didSet { needsDisplay = true }
    }

    var range: StatsManager.HistoryRange = .week {
        didSet { needsDisplay = true }
    }

    var style: Style = .line {
        didSet { needsDisplay = true }
    }

    private var hoverIndex: Int? {
        didSet {
            if hoverIndex != oldValue {
                needsDisplay = true
                updateHoverLabels()
            }
        }
    }

    private lazy var hoverYBlurView: NSVisualEffectView = makeHoverBlurView()
    private lazy var hoverYTextField: NSTextField = makeHoverTextField(parent: hoverYBlurView)
    private lazy var hoverDateBlurView: NSVisualEffectView = makeHoverBlurView()
    private lazy var hoverDateTextField: NSTextField = makeHoverTextField(parent: hoverDateBlurView)

    private var trackingArea: NSTrackingArea?
    private let transitionDuration: CFTimeInterval = 0.22

    private lazy var dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("M/d")
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func apply(series: [(date: Date, value: Double)],
               localSeries: [(date: Date, value: Double)]?,
               metric: StatsManager.HistoryMetric,
               range: StatsManager.HistoryRange,
               style: Style,
               animated: Bool,
               slideDirection: SlideDirection? = nil) {
        if animated {
            addSlideTransition(direction: slideDirection ?? .right)
        }
        self.series = series
        self.localSeries = localSeries
        self.metric = metric
        self.range = range
        self.style = style
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        updateHoverIndex(for: location)
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let backgroundRect = bounds.insetBy(dx: 0, dy: 6)
        let panelPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 5, yRadius: 5)
        GeekPalette.panel.withAlphaComponent(0.52).setFill()
        panelPath.fill()
        GeekPalette.grid.withAlphaComponent(0.55).setStroke()
        panelPath.lineWidth = 0.5
        panelPath.stroke()

        // 在 Dark Mode 下使用更高的透明度以提高可见性
        let isDarkMode = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let gridAlpha: CGFloat = isDarkMode ? 0.28 : 0.20
        let axisAlpha: CGFloat = isDarkMode ? 0.75 : 0.6

        let gridColor = GeekPalette.grid.withAlphaComponent(gridAlpha)
        let axisColor = GeekPalette.grid.withAlphaComponent(axisAlpha)


        let maxValue = maxSeriesValue()
        guard maxValue > 0 else {
            let text = NSLocalizedString("history.empty", comment: "")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: GeekPalette.secondary
            ]
            let size = text.size(withAttributes: attributes)
            let point = NSPoint(x: backgroundRect.midX - size.width / 2, y: backgroundRect.midY - size.height / 2)
            text.draw(at: point, withAttributes: attributes)
            return
        }

        let plotRect = plotRect(in: backgroundRect, maxValue: maxValue)
        drawGrid(in: plotRect, color: gridColor)
        drawAxes(in: plotRect, color: axisColor)
        drawAxisLabels(in: plotRect, maxValue: maxValue)

        switch style {
        case .line:
            drawLineChart(in: plotRect, maxValue: maxValue)
        case .bar:
            drawBarChart(in: plotRect, maxValue: maxValue)
        }

        drawLegend(in: backgroundRect)

        drawHover(in: plotRect, maxValue: maxValue, backgroundRect: backgroundRect)
    }

    private func drawGrid(in rect: NSRect, color: NSColor) {
        for i in 1...3 {
            let y = rect.minY + rect.height * CGFloat(i) / 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            color.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private func drawAxes(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        color.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawAxisLabels(in rect: NSRect, maxValue: Double) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: GeekPalette.secondary
        ]

        drawLabel(formatValue(0), at: NSPoint(x: rect.minX - 4, y: rect.minY), alignment: .right, attributes: attributes)
        drawLabel(formatValue(maxValue / 2), at: NSPoint(x: rect.minX - 4, y: rect.midY), alignment: .right, attributes: attributes)
        drawLabel(formatValue(maxValue), at: NSPoint(x: rect.minX - 4, y: rect.maxY), alignment: .right, attributes: attributes)

        guard !series.isEmpty else { return }
        let labels = series.map { dateLabel(for: $0.date) }
        let maxLabelWidth = labels
            .map { $0.size(withAttributes: attributes).width }
            .max() ?? 0
        let minSpacing: CGFloat = 6
        let maxLabels = max(2, Int(rect.width / max(1, maxLabelWidth + minSpacing)))
        let count = labels.count
        let step: Int
        if count <= 7 {
            step = 2
        } else if maxLabels >= count {
            step = 1
        } else {
            step = Int(ceil(Double(count - 1) / Double(maxLabels - 1)))
        }
        let xPositions = xPositions(in: rect)
        let y = rect.minY - 14
        var indices = Array(stride(from: 0, to: count, by: step))
        if indices.last != count - 1 {
            // 如果最后一个 stride 索引与末尾太近，替换而非追加，避免标签重叠
            if let last = indices.last, (count - 1 - last) < step / 2, indices.count > 1 {
                indices[indices.count - 1] = count - 1
            } else {
                indices.append(count - 1)
            }
        }
        for index in indices {
            let text = labels[index]
            let x = xPositions[index]
            drawClampedLabel(text, center: NSPoint(x: x, y: y), within: rect, attributes: attributes)
        }
    }

    private func drawLineChart(in rect: NSRect, maxValue: Double) {
        drawLineSeries(
            series,
            in: rect,
            maxValue: maxValue,
            color: GeekPalette.cyan,
            lineWidth: 2.25,
            dashPattern: [],
            dotRadius: 2.5
        )
        if let localSeries = localSeries {
            drawLineSeries(
                localSeries,
                in: rect,
                maxValue: maxValue,
                color: GeekPalette.amber,
                lineWidth: 1.75,
                dashPattern: [5, 3],
                dotRadius: 2
            )
        }
    }

    private func drawLineSeries(
        _ data: [(date: Date, value: Double)],
        in rect: NSRect,
        maxValue: Double,
        color: NSColor,
        lineWidth: CGFloat,
        dashPattern: [CGFloat],
        dotRadius: CGFloat
    ) {
        let count = data.count
        guard count > 0 else { return }
        let xPositions = xPositions(in: rect)
        guard xPositions.count == count else { return }
        let points: [NSPoint] = data.enumerated().map { index, item in
            let x = xPositions[index]
            let y = yPosition(for: item.value, in: rect, maxValue: maxValue)
            return NSPoint(x: x, y: y)
        }

        let path = NSBezierPath()
        path.move(to: points[0])

        if points.count > 1 {
            let tangents = monotoneTangents(for: points)
            for index in 0..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let dx = next.x - current.x
                guard dx > 0 else {
                    path.line(to: next)
                    continue
                }

                let controlPoint1 = NSPoint(
                    x: current.x + dx / 3,
                    y: current.y + tangents[index] * dx / 3
                )
                let controlPoint2 = NSPoint(
                    x: next.x - dx / 3,
                    y: next.y - tangents[index + 1] * dx / 3
                )
                path.curve(to: next, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
        }

        if !dashPattern.isEmpty {
            dashPattern.withUnsafeBufferPointer { buffer in
                path.setLineDash(buffer.baseAddress, count: buffer.count, phase: 0)
            }
        }
        color.setStroke()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        if let point = points.last {
            let x = point.x
            let y = point.y
            let dotRect = NSRect(
                x: x - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            let dot = NSBezierPath(ovalIn: dotRect)
            color.setFill()
            dot.fill()
        }
    }

    private func monotoneTangents(for points: [NSPoint]) -> [CGFloat] {
        let count = points.count
        guard count > 1 else { return [0] }

        var dx = Array(repeating: CGFloat(0), count: count - 1)
        var slopes = Array(repeating: CGFloat(0), count: count - 1)

        for index in 0..<(count - 1) {
            let deltaX = max(0.0001, points[index + 1].x - points[index].x)
            dx[index] = deltaX
            slopes[index] = (points[index + 1].y - points[index].y) / deltaX
        }

        var tangents = Array(repeating: CGFloat(0), count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]

        if count > 2 {
            for index in 1..<(count - 1) {
                let previousSlope = slopes[index - 1]
                let nextSlope = slopes[index]

                if previousSlope == 0 || nextSlope == 0 || (previousSlope > 0) != (nextSlope > 0) {
                    tangents[index] = 0
                    continue
                }

                let previousDX = dx[index - 1]
                let nextDX = dx[index]
                let weight1 = 2 * nextDX + previousDX
                let weight2 = nextDX + 2 * previousDX
                tangents[index] = (weight1 + weight2) / ((weight1 / previousSlope) + (weight2 / nextSlope))
            }
        }

        for index in 0..<(count - 1) {
            let slope = slopes[index]
            if slope == 0 {
                tangents[index] = 0
                tangents[index + 1] = 0
                continue
            }

            let alpha = tangents[index] / slope
            let beta = tangents[index + 1] / slope
            let magnitude = alpha * alpha + beta * beta

            if magnitude > 9 {
                let scale = CGFloat(3.0 / sqrt(Double(magnitude)))
                tangents[index] = scale * alpha * slope
                tangents[index + 1] = scale * beta * slope
            }
        }

        return tangents
    }

    private func drawBarChart(in rect: NSRect, maxValue: Double) {
        let count = series.count
        guard count > 0 else { return }
        let stepX = rect.width / CGFloat(count)
        let hasLocalSeries = localSeries?.count == count
        let groupWidth = min(stepX * 0.72, 26)
        let barSpacing: CGFloat = hasLocalSeries ? 2 : 0
        let barWidth = hasLocalSeries ? (groupWidth - barSpacing) / 2 : min(stepX * 0.6, 22)

        for (index, item) in series.enumerated() {
            let height = (CGFloat(item.value) / CGFloat(maxValue)) * rect.height
            let groupX = rect.minX + CGFloat(index) * stepX + (stepX - groupWidth) / 2
            let x = hasLocalSeries ? groupX : rect.minX + CGFloat(index) * stepX + (stepX - barWidth) / 2
            let barRect = NSRect(x: x, y: rect.minY, width: barWidth, height: height)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
            GeekPalette.cyan.setFill()
            barPath.fill()

            if hasLocalSeries, let localItem = localSeries?[index] {
                let localHeight = (CGFloat(localItem.value) / CGFloat(maxValue)) * rect.height
                let localRect = NSRect(
                    x: groupX + barWidth + barSpacing,
                    y: rect.minY,
                    width: barWidth,
                    height: localHeight
                )
                let localPath = NSBezierPath(roundedRect: localRect, xRadius: 2, yRadius: 2)
                GeekPalette.amber.setFill()
                localPath.fill()
            }
        }
    }

    private func drawLegend(in rect: NSRect) {
        guard let localSeries = localSeries, localSeries.count == series.count else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: GeekPalette.secondary
        ]
        let valueFormat = NSLocalizedString("history.series.value", comment: "")
        let hoverIndex = hoverIndex.flatMap { $0 < series.count ? $0 : nil }
        let syncedLabel = legendLabel(
            title: NSLocalizedString("history.series.synced", comment: ""),
            value: hoverIndex.map { series[$0].value },
            format: valueFormat
        )
        let localLabel = legendLabel(
            title: NSLocalizedString("history.series.local", comment: ""),
            value: hoverIndex.map { localSeries[$0].value },
            format: valueFormat
        )
        let items: [(text: String, color: NSColor, dashed: Bool)] = [
            (syncedLabel, GeekPalette.cyan, false),
            (localLabel, GeekPalette.amber, true)
        ]
        let sampleWidth: CGFloat = 14
        let sampleSpacing: CGFloat = 4
        let itemSpacing: CGFloat = 12
        let widths = items.map { sampleWidth + sampleSpacing + $0.text.size(withAttributes: attributes).width }
        let totalWidth = widths.reduce(0, +) + itemSpacing
        var x = max(rect.minX + 8, rect.maxX - totalWidth - 8)
        let textHeight = items.map { $0.text.size(withAttributes: attributes).height }.max() ?? 0
        let textY = rect.maxY - textHeight - 7
        let sampleY = textY + textHeight / 2

        for (index, item) in items.enumerated() {
            if style == .bar {
                item.color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: sampleY - 3, width: sampleWidth, height: 6), xRadius: 1.5, yRadius: 1.5).fill()
            } else {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: sampleY))
                path.line(to: NSPoint(x: x + sampleWidth, y: sampleY))
                if item.dashed {
                    let pattern: [CGFloat] = [4, 2]
                    pattern.withUnsafeBufferPointer { buffer in
                        path.setLineDash(buffer.baseAddress, count: buffer.count, phase: 0)
                    }
                }
                item.color.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
            item.text.draw(at: NSPoint(x: x + sampleWidth + sampleSpacing, y: textY), withAttributes: attributes)
            x += widths[index] + itemSpacing
        }
    }

    private func legendLabel(title: String, value: Double?, format: String) -> String {
        guard let value = value else { return title }
        return String(format: format, title, formatValue(value))
    }

    private func drawHover(in rect: NSRect, maxValue: Double, backgroundRect: NSRect) {
        guard let hoverIndex = hoverIndex, hoverIndex >= 0, hoverIndex < series.count else { return }
        let xPositions = xPositions(in: rect)
        let value = series[hoverIndex].value
        let x = xPositions[hoverIndex]
        let y = yPosition(for: value, in: rect, maxValue: maxValue)

        let crosshairColor = GeekPalette.cyan.withAlphaComponent(0.25)
        let crosshairPath = NSBezierPath()
        crosshairPath.move(to: NSPoint(x: x, y: rect.minY))
        crosshairPath.line(to: NSPoint(x: x, y: rect.maxY))
        crosshairPath.move(to: NSPoint(x: rect.minX, y: y))
        crosshairPath.line(to: NSPoint(x: rect.maxX, y: y))
        crosshairColor.setStroke()
        crosshairPath.lineWidth = 1
        crosshairPath.stroke()

        let radius: CGFloat = 5
        let dotRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let dot = NSBezierPath(ovalIn: dotRect)
        GeekPalette.cyan.setFill()
        dot.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        dot.lineWidth = 2
        dot.stroke()

        if let localSeries = localSeries, hoverIndex < localSeries.count {
            let localValue = localSeries[hoverIndex].value
            let localY = yPosition(for: localValue, in: rect, maxValue: maxValue)
            let localRadius: CGFloat = abs(localY - y) < 1 ? 6 : 5
            let localRect = NSRect(
                x: x - localRadius,
                y: localY - localRadius,
                width: localRadius * 2,
                height: localRadius * 2
            )
            let localDot = NSBezierPath(ovalIn: localRect)
            GeekPalette.amber.setFill()
            localDot.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            localDot.lineWidth = 1.5
            localDot.stroke()

            if abs(localY - y) < 1 {
                GeekPalette.cyan.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 3, y: y - 3, width: 6, height: 6)).fill()
            }
        }

        // hover 标签通过 NSVisualEffectView 子视图绘制，见 updateHoverLabels()
    }

    private func updateHoverIndex(for location: NSPoint) {
        guard !series.isEmpty else {
            hoverIndex = nil
            return
        }
        let backgroundRect = bounds.insetBy(dx: 0, dy: 6)
        let maxValue = maxSeriesValue()
        let rect = plotRect(in: backgroundRect, maxValue: maxValue)
        guard rect.contains(location) else {
            hoverIndex = nil
            return
        }
        let positions = xPositions(in: rect)
        var nearestIndex = 0
        var nearestDistance = abs(location.x - positions[0])
        for (index, x) in positions.enumerated() {
            let distance = abs(location.x - x)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        hoverIndex = nearestIndex
    }

    private func plotRect(in rect: NSRect, maxValue: Double? = nil) -> NSRect {
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        ]
        let leftPadding: CGFloat
        if let maxValue = maxValue, maxValue > 0 {
            let maxLabel = formatValue(maxValue)
            let midLabel = formatValue(maxValue / 2)
            let maxWidth = max(
                maxLabel.size(withAttributes: labelAttributes).width,
                midLabel.size(withAttributes: labelAttributes).width
            )
            leftPadding = ceil(maxWidth) + 8
        } else {
            leftPadding = 36
        }
        let rightPadding: CGFloat = 10
        let topPadding: CGFloat = localSeries == nil ? 10 : 26
        let bottomPadding: CGFloat = 20
        let width = max(1, rect.width - leftPadding - rightPadding)
        let height = max(1, rect.height - topPadding - bottomPadding)
        return NSRect(
            x: rect.minX + leftPadding,
            y: rect.minY + bottomPadding,
            width: width,
            height: height
        )
    }

    private func xPositions(in rect: NSRect) -> [CGFloat] {
        let count = series.count
        guard count > 0 else { return [] }
        if count == 1 {
            return [rect.midX]
        }
        switch style {
        case .bar:
            let stepX = rect.width / CGFloat(count)
            return (0..<count).map { rect.minX + (CGFloat($0) + 0.5) * stepX }
        case .line:
            let stepX = rect.width / CGFloat(count - 1)
            return (0..<count).map { rect.minX + CGFloat($0) * stepX }
        }
    }

    private func yPosition(for value: Double, in rect: NSRect, maxValue: Double) -> CGFloat {
        let ratio = maxValue > 0 ? CGFloat(value / maxValue) : 0
        return rect.minY + ratio * rect.height
    }

    private func maxSeriesValue() -> Double {
        let displayMax = series.map { $0.value }.max() ?? 0
        let localMax = localSeries?.map { $0.value }.max() ?? 0
        return max(displayMax, localMax)
    }

    private func formatValue(_ value: Double) -> String {
        return StatsManager.shared.formatHistoryValue(metric: metric, value: value)
    }

    private func dateLabel(for date: Date) -> String {
        return dayDateFormatter.string(from: date)
    }

    private enum LabelAlignment {
        case left
        case center
        case right
    }

    private func drawLabel(_ text: String, at point: NSPoint, alignment: LabelAlignment, attributes: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attributes)
        var x = point.x
        switch alignment {
        case .left:
            break
        case .center:
            x -= size.width / 2
        case .right:
            x -= size.width
        }
        let y = point.y - size.height / 2
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private func drawClampedLabel(_ text: String, center: NSPoint, within rect: NSRect, attributes: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attributes)
        var x = center.x - size.width / 2
        x = min(max(x, rect.minX), rect.maxX - size.width)
        let y = center.y - size.height / 2
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    private func makeHoverBlurView() -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 4
        v.layer?.masksToBounds = true
        v.isHidden = true
        addSubview(v)
        return v
    }

    private func makeHoverTextField(parent: NSVisualEffectView) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        parent.addSubview(label)
        return label
    }

    private func updateHoverLabels() {
        guard let hoverIndex = hoverIndex, hoverIndex >= 0, hoverIndex < series.count else {
            hoverYBlurView.isHidden = true
            hoverDateBlurView.isHidden = true
            return
        }

        let backgroundRect = bounds.insetBy(dx: 0, dy: 6)
        let maxValue = maxSeriesValue()
        guard maxValue > 0 else {
            hoverYBlurView.isHidden = true
            hoverDateBlurView.isHidden = true
            return
        }
        let rect = plotRect(in: backgroundRect, maxValue: maxValue)
        guard !rect.isEmpty else {
            hoverYBlurView.isHidden = true
            hoverDateBlurView.isHidden = true
            return
        }

        let xPos = xPositions(in: rect)
        let x = xPos[hoverIndex]
        let value = series[hoverIndex].value
        let y = yPosition(for: value, in: rect, maxValue: maxValue)
        let padding: CGFloat = 3

        // Y 轴数值标签
        let valueText = formatValue(value)
        hoverYTextField.stringValue = valueText
        hoverYTextField.sizeToFit()
        let ySize = hoverYTextField.fittingSize
        let yLabelOriginX = rect.minX - 4 - ySize.width
        let yLabelOriginY = y - ySize.height / 2
        hoverYBlurView.frame = NSRect(
            x: yLabelOriginX - padding,
            y: yLabelOriginY - padding,
            width: ySize.width + padding * 2,
            height: ySize.height + padding * 2
        )
        hoverYTextField.frame = NSRect(x: padding, y: padding, width: ySize.width, height: ySize.height)
        hoverYBlurView.isHidden = false

        // X 轴日期标签
        let dateText = dateLabel(for: series[hoverIndex].date)
        hoverDateTextField.stringValue = dateText
        hoverDateTextField.sizeToFit()
        let dateSize = hoverDateTextField.fittingSize
        var dateX = x - dateSize.width / 2
        dateX = min(max(dateX, backgroundRect.minX), backgroundRect.maxX - dateSize.width)
        let dateY = rect.minY - 14 - dateSize.height / 2
        hoverDateBlurView.frame = NSRect(
            x: dateX - padding,
            y: dateY - padding,
            width: dateSize.width + padding * 2,
            height: dateSize.height + padding * 2
        )
        hoverDateTextField.frame = NSRect(x: padding, y: padding, width: dateSize.width, height: dateSize.height)
        hoverDateBlurView.isHidden = false
    }

    private func addSlideTransition(direction: SlideDirection) {
        guard let layer = layer else { return }
        let timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
        let transition = CATransition()
        transition.type = .push
        transition.subtype = direction == .right ? .fromRight : .fromLeft
        transition.duration = transitionDuration
        transition.timingFunction = timingFunction
        layer.add(transition, forKey: "contentSlide")

        let scaleAnimation = CABasicAnimation(keyPath: "transform")
        scaleAnimation.fromValue = CATransform3DMakeScale(0.98, 0.98, 1)
        scaleAnimation.toValue = CATransform3DIdentity
        scaleAnimation.duration = transitionDuration
        scaleAnimation.timingFunction = timingFunction
        layer.add(scaleAnimation, forKey: "contentScale")
    }
}

// MARK: - KPS 徽章视图

/// Plain peak-rate button; the detail popover remains available.
class GeekKPSBadgeView: NSButton {
    var onTap: (() -> Void)?

    private let iconView: NSImageView
    private let rateLabel: NSTextField

    override init(frame frameRect: NSRect) {
        iconView = NSImageView(image: NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage())
        rateLabel = NSTextField(labelWithString: "0|0")
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let label = rateLabel.intrinsicContentSize
        return NSSize(width: 12 + 2 + label.width + 11, height: max(12, label.height) + 6)
    }

    private func setupUI() {
        wantsLayer = true
        updateAppearance()
        toolTip = "KPS / CPS"
        title = ""; isBordered = false
        target = self; action = #selector(activateBadge)
        setAccessibilityLabel(NSLocalizedString("popover.peakRates", comment: ""))

        iconView.contentTintColor = GeekPalette.amber
        iconView.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 12).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 12).isActive = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setAccessibilityElement(false)

        rateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        rateLabel.textColor = .secondaryLabelColor
        rateLabel.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [iconView, rateLabel])
        mainStack.orientation = .horizontal
        mainStack.alignment = .centerY
        mainStack.spacing = 2
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = nil
    }

    func update(peakKPS: Int, peakCPS: Int) {
        let textColor = GeekPalette.secondary
        let separatorColor = GeekPalette.secondary.withAlphaComponent(0.5)
        let font = rateLabel.font ?? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

        let attributed = NSMutableAttributedString(
            string: "\(peakKPS)",
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        attributed.append(
            NSAttributedString(
                string: " · ",
                attributes: [
                    .font: font,
                    .foregroundColor: separatorColor
                ]
            )
        )
        attributed.append(
            NSAttributedString(
                string: "\(peakCPS)",
                attributes: [
                    .font: font,
                    .foregroundColor: textColor
                ]
            )
        )

        rateLabel.attributedStringValue = attributed
        setAccessibilityValue("\(peakKPS) KPS · \(peakCPS) CPS")
        invalidateIntrinsicContentSize()
    }

    @objc private func activateBadge() { onTap?() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
