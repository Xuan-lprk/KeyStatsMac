import Foundation

enum HelperLocations {
    static let mainBundleId = "com.xuanlprk.KeyStatsMac"
    static let helperBundleId = "com.xuanlprk.KeyStatsMac.helper"
    static let machServiceName = "com.xuanlprk.KeyStatsMac.helper"
    static let launchAgentLabel = "com.xuanlprk.KeyStatsMac.helper"
    static let interfaceVersion = 1

    static var installDir: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("KeyStatsMac/Helper", isDirectory: true)
    }

    static var installedHelperURL: URL {
        installDir.appendingPathComponent("KeyStatsHelper.app", isDirectory: true)
    }

    static var installedHelperBinaryURL: URL {
        installedHelperURL.appendingPathComponent("Contents/MacOS/KeyStatsHelper")
    }

    static var launchAgentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }
}
