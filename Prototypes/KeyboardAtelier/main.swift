import Cocoa

final class AtelierDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var atelier: AtelierView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        var actual: AtelierDataset?
        var error: String?
        do { actual = try AtelierData.load() } catch let failure { error = failure.localizedDescription }
        atelier = AtelierView(actual: actual, error: error)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: AtelierView.designSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("window.title")
        window.minSize = NSSize(width: 1050, height: 755)
        window.contentView = atelier
        window.center()
        window.isReleasedWhenClosed = false
        if CommandLine.arguments.contains("--geometry-check") {
            do { try PorcelainSceneRenderer().validateGeometry(dataset: actual ?? AtelierData.simulated(1)) }
            catch { fputs("Geometry smoke failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
            return
        }
        if let position = CommandLine.arguments.firstIndex(of: "--render-dir"),
           CommandLine.arguments.count > position + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[position + 1], isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for version in 0...1 {
                    for stage in 0...3 {
                        atelier.setPreview(version: version, stage: stage)
                        try atelier.renderPNG(to: directory.appendingPathComponent("porcelain-v\(version + 1)-stage-\(stage).png"))
                    }
                    atelier.setPreview(version: version, stage: 0, neutral: true)
                    try atelier.renderPNG(to: directory.appendingPathComponent("porcelain-v\(version + 1)-neutral.png"))
                }
                print("Rendered 10 Porcelain comparison previews. Real dataset available: \(actual != nil)")
            } catch { fputs("Preview render failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(atelier)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu()
let rootItem = NSMenuItem()
menu.addItem(rootItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: L("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
rootItem.submenu = appMenu
app.mainMenu = menu
let delegate = AtelierDelegate()
app.delegate = delegate
app.run()
