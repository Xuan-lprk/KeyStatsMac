import Cocoa

enum MenuUIStyle: String, CaseIterable {
    case standard
    case geek

    static let defaultsKey = "menuUIStyle.v1"
    static var current: MenuUIStyle {
        MenuUIStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .standard
    }
}

protocol MenuStatsPresenting: AnyObject {
    var preferredSizeDidChange: ((NSSize) -> Void)? { get set }
    var preferredContentSize: NSSize { get }
    func prepareForPopoverPresentation()
}

extension StatsPopoverViewController: MenuStatsPresenting {}
extension GeekStatsPopoverViewController: MenuStatsPresenting {}
