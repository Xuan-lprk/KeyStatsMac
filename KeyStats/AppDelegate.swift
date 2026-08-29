import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var menuBarController: MenuBarController?
    private var permissionCheckTimer: Timer?
    private var permissionCheckCount = 0
    private let maxPermissionChecks = 150 // 5分钟后停止（2秒间隔 × 150次）
    private let launchAtLoginPromptedKey = "launchAtLoginPrompted"
    private let analyticsInstallTrackedKey = "analyticsInstallTracked"
    private var shouldShowAccessibilityPromptOnLaunch: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 必须在 trackInstallIfNeeded()/MenuBarController 任何 UserDefaults 写入之前采集，
        // 否则 fresh install 与升级用户在后续阶段已无差别。仅作为是否触发迁移提示的判据。
        let wasPreviouslyInstalled = UserDefaults.standard.bool(forKey: analyticsInstallTrackedKey)

        AnalyticsManager.shared.setupIfEnabled()
        trackInstallIfNeeded()
        Self.trackEvent("app_open")

        // 初始化菜单栏控制器
        menuBarController = MenuBarController()
        applyAppIcon()
        _ = UpdateManager.shared
        SyncCoordinator.shared.start()

        setupWindowMenu()

        bootstrapHelperPipeline(wasPreviouslyInstalled: wasPreviouslyInstalled)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        Self.trackEvent("app_exit")
        HelperXPCClient.shared.stopMonitoring()
        HelperXPCClient.shared.disconnect()
        permissionCheckTimer?.invalidate()
        StatsManager.shared.flushPendingSave()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Helper 启动

    private func bootstrapHelperPipeline(wasPreviouslyInstalled: Bool) {
        HelperXPCClient.shared.setEventSink(RemoteEventProcessor.shared)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try HelperSupervisor.shared.ensureInstalled()
                NSLog("[AppDelegate] helper installed + launchd registered")
            } catch {
                NSLog("[AppDelegate] HelperSupervisor.ensureInstalled failed: \(error)")
            }
            DispatchQueue.main.async {
                Task { @MainActor in
                    HelperMigrationPresenter.shared.showIfNeeded(wasPreviouslyInstalled: wasPreviouslyInstalled)
                    self?.connectHelperAndStart()
                }
            }
        }
    }

    private func connectHelperAndStart() {
        HelperXPCClient.shared.connect { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                NSLog("[AppDelegate] helper xpc state = \(state)")
                switch state {
                case .connected(_, let granted):
                    if granted {
                        HelperXPCClient.shared.startMonitoring { ok, code in
                            NSLog("[AppDelegate] helper startMonitoring ok=\(ok) code=\(code)")
                        }
                        self.promptLaunchAtLoginIfNeeded()
                    } else {
                        if self.shouldShowAccessibilityPromptOnLaunch {
                            self.showPermissionAlert()
                        } else {
                            print("开发模式启动：helper 未获辅助功能授权，跳过启动提示")
                        }
                        self.startPermissionPolling()
                    }
                case .disconnected(let reason):
                    NSLog("[AppDelegate] helper disconnected: \(reason); retry in 5s")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.connectHelperAndStart()
                    }
                default:
                    break
                }
            }
        }
    }

    private func isHelperAccessibilityGranted() -> Bool {
        if case .connected(_, let granted) = HelperXPCClient.shared.state {
            return granted
        }
        return false
    }

    func requestAccessibilityPermission(analyticsSource: String) {
        if isHelperAccessibilityGranted() {
            handleAccessibilityPermissionGranted()
            return
        }

        Self.trackClick("request_accessibility_permission", properties: [
            "permission": "accessibility",
            "source": analyticsSource
        ])
        // 先让 helper 调一次 AXIsProcessTrustedWithOptions，把自己写进系统设置的
        // 辅助功能列表；再跳转到那个 pane 方便用户授权。
        HelperXPCClient.shared.promptAccessibility { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.handleAccessibilityPermissionGranted()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.openAccessibilitySettingsPane()
                    self?.startPermissionPolling()
                }
            }
        }
    }

    private func openAccessibilitySettingsPane() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("permission.title", comment: "")
        // 使用 Assets 中的 AppIcon
        if let appIcon = NSImage(named: "AppIcon") {
            alert.icon = makeRoundedAlertIcon(from: appIcon)
        }
        let permissionMessage = NSLocalizedString("permission.message", comment: "")
        let reinstallTip = NSLocalizedString("permission.reinstallTip", comment: "")
        let textParts = [permissionMessage, reinstallTip].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        alert.informativeText = textParts.joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("permission.openSettings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("permission.later", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessibilityPermission(analyticsSource: "launch_alert")
        }
    }

    private func handleAccessibilityPermissionGranted() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        HelperXPCClient.shared.startMonitoring { ok, code in
            NSLog("[AppDelegate] helper startMonitoring after grant ok=\(ok) code=\(code)")
        }
        promptLaunchAtLoginIfNeeded()
    }

    private func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckCount = 0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.permissionCheckCount += 1

            // 每次 poll 都重新握手，以便读 helper 的最新授权状态
            HelperXPCClient.shared.refreshState { state in
                DispatchQueue.main.async {
                    if case .connected(_, let granted) = state, granted {
                        timer.invalidate()
                        self.permissionCheckTimer = nil
                        self.handleAccessibilityPermissionGranted()
                        Self.trackEvent("permission_granted", properties: ["permission": "accessibility"])
                        print("权限已授予，helper 开始监听")
                    }
                }
            }

            if self.permissionCheckCount >= self.maxPermissionChecks {
                timer.invalidate()
                self.permissionCheckTimer = nil
                print("权限检查超时（5分钟），请手动在系统设置中授予 KeyStatsHelper 辅助功能权限")
            }
        }

        if let permissionCheckTimer {
            RunLoop.main.add(permissionCheckTimer, forMode: .common)
        }
    }

    private func promptLaunchAtLoginIfNeeded() {
        guard isHelperAccessibilityGranted() else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: launchAtLoginPromptedKey) else { return }
        defaults.set(true, forKey: launchAtLoginPromptedKey)

        if LaunchAtLoginManager.shared.isEnabled {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("launchAtLogin.prompt.title", comment: "")
        alert.informativeText = NSLocalizedString("launchAtLogin.prompt.message", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("launchAtLogin.prompt.enable", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("launchAtLogin.prompt.later", comment: ""))

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try LaunchAtLoginManager.shared.setEnabled(true)
            } catch {
                showLaunchAtLoginError()
            }
        }
    }

    private func showLaunchAtLoginError() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("launchAtLogin.error.title", comment: "")
        alert.informativeText = NSLocalizedString("launchAtLogin.error.message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("button.ok", comment: ""))
        alert.runModal()
    }
    
    private func makeRoundedAlertIcon(from image: NSImage) -> NSImage {
        let targetSize: CGFloat = 64
        let rect = NSRect(x: 0, y: 0, width: targetSize, height: targetSize)
        let icon = NSImage(size: rect.size)
        icon.lockFocus()
        let radius = targetSize * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        icon.unlockFocus()
        return icon
    }

    private func applyAppIcon() {
        guard let appIcon = NSImage(named: "AppIcon") else {
            return
        }
        NSApp.applicationIconImage = appIcon
    }

    private func setupWindowMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let windowTitle = NSLocalizedString("menu.window", comment: "")
        if mainMenu.items.contains(where: { $0.title == windowTitle }) {
            return
        }
        let windowMenuItem = NSMenuItem(title: windowTitle, action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: windowTitle)
        let closeTitle = NSLocalizedString("menu.closeWindow", comment: "")
        let closeItem = NSMenuItem(title: closeTitle, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu

        let insertIndex = min(1, mainMenu.items.count)
        mainMenu.insertItem(windowMenuItem, at: insertIndex)
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Analytics

    private func trackInstallIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: analyticsInstallTrackedKey) else { return }
        Self.trackEvent("app_install", properties: ["install_utc": AnalyticsManager.shared.firstOpenUTC()])
        defaults.set(true, forKey: analyticsInstallTrackedKey)
    }

    static func trackEvent(_ eventName: String, properties: [String: Any]? = nil) {
        AnalyticsManager.shared.trackEvent(eventName, properties: properties)
    }

    static func trackPageView(_ pageName: String, properties: [String: Any]? = nil) {
        AnalyticsManager.shared.trackPageView(pageName, properties: properties)
    }

    static func trackClick(_ elementName: String, properties: [String: Any]? = nil) {
        AnalyticsManager.shared.trackClick(elementName, properties: properties)
    }
}
