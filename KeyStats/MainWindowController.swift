import Cocoa

class MainWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.contentViewController = MainWindowViewController()
        window?.title = "KeyStats"
    }
}
