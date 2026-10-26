import Foundation

/// Process-local opt-in. Release ignores the argument; no preference is persisted.
enum AppLaunchMode: Equatable {
    case normal
    case guiAcceptance

    static let current = AppLaunchMode(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        #if DEBUG
        self = arguments.dropFirst().contains("--debug-gui-acceptance") ? .guiAcceptance : .normal
        #else
        self = .normal
        #endif
    }

    /// Normal launches retain their existing compatibility behavior. Acceptance must
    /// stop before monitoring when the installed Helper reports a different protocol.
    func allowsHelperVersion(_ version: Int, expected: Int) -> Bool {
        self == .normal || version == expected
    }

    /// Preparing a public key must not enable the updater before release setup.
    func allowsUpdater(publicKey: String?, updatesEnabled: Bool) -> Bool {
        guard self == .normal, updatesEnabled, let publicKey,
              let bytes = Data(base64Encoded: publicKey) else { return false }
        return bytes.count == 32
    }
}
