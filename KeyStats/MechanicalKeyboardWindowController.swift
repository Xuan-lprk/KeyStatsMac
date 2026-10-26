import Cocoa

final class MechanicalKeyboardWindowController: NSWindowController {
    static let shared = MechanicalKeyboardWindowController()

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        KeyboardHeatmapWindowController.shared.show()
    }
}
