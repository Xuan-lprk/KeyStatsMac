import Cocoa

final class KeyboardHeatmapWindowController: NSWindowController {
    static let shared = KeyboardHeatmapWindowController()

    private init() {
        let viewController = KeyboardVisualizationViewController()
        let window = NSWindow(contentViewController: viewController)
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1160, height: 780)
        let fixedSize = NSSize(width: min(1100, available.width - 60), height: min(720, available.height - 90))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = NSLocalizedString("keyboardVisualization.title", comment: "")
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.isMovableByWindowBackground = true
        window.backgroundColor = KeyboardVisualizationCanvasView.backgroundColor(
            for: window.effectiveAppearance, showsGrowth: true)
        window.setContentSize(fixedSize)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window = window else { return }
        let wasVisible = window.isVisible
        let wasMiniaturized = window.isMiniaturized
        NSApp.activate(ignoringOtherApps: true)
        if wasMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        if let vc = contentViewController as? KeyboardVisualizationViewController {
            vc.refreshForPresentation(resetToToday: !wasVisible && !wasMiniaturized)
            if !vc.showsGrowth { AppDelegate.trackPageView("keyboard_heatmap") }
        }
    }
}
