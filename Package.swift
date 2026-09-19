// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeyStatsCoreTests",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeyStatsCore", targets: ["KeyStatsCore"])
    ],
    targets: [
        .target(
            name: "KeyStatsEventCore",
            path: "KeyStatsHelper",
            exclude: ["Assets.xcassets", "Info.plist", "KeyStatsHelper.entitlements", "main.swift",
                      "EventTapController.swift", "HelperXPCListener.swift", "HelperIdleSupervisor.swift",
                      "HelperLocations.swift", "HelperProtocols.swift"],
            sources: ["SystemMediaKey.swift", "PayloadBuilder.swift", "HelperPayloadFields.swift", "ButtonRoleClassifier.swift"]
        ),
        .target(
            name: "PostHog",
            path: "KeyStatsTestSupport/PostHog"
        ),
        .target(
            name: "KeyStatsCore",
            dependencies: ["PostHog"],
            path: "KeyStats",
            exclude: [
                "Assets.xcassets",
                "Main.storyboard",
                "Info.plist",
                "en.lproj",
                "zh-Hans.lproj",
                "zh-Hant.lproj",
                "AppStatsViewController.swift",
                "AppDetailView.swift",
                "KeyStats.entitlements",
                "NotificationManager.swift",
                "StatsManagerLiveEnvironment.swift",
                "HoverIconButton.swift",
                "MouseDistanceCalibrationViewController.swift",
                "ActivityHeatmapView.swift",
                "AllTimeStatsWindowController.swift",
                "MouseDistanceCalibrationWindowController.swift",
                "SettingsViewController.swift",
                "AppStatsWindowController.swift",
                "AppDelegate.swift",
                "MenuBarController.swift",
                "AllTimeStatsViewController.swift",
                "MainWindowController.swift",
                "HelperMigrationPresenter.swift",
                "HelperSupervisor.swift",
                "HelperXPCClient.swift",
                "KeyboardHeatmapViewController.swift",
                "KPSDetailView.swift",
                "LaunchAtLoginManager.swift",
                "RemoteEventProcessor.swift",
                "Sync/SyncCoordinator.swift",
                "Sync/SyncSettingsWindowController.swift",
                "UpdateManager.swift",
                "KeyboardHeatmapWindowController.swift",
                "StatsPopoverViewController.swift",
                "SettingsWindowController.swift",
                "MainWindowViewController.swift"
            ],
            sources: [
                "AppStats.swift",
                "AppKeyBreakdown.swift",
                "AppDetailPresentation.swift",
                "InteractionProfile.swift",
                "AppActivityTracker.swift",
                "StatsModels.swift",
                "StatsManager.swift",
                "AnalyticsManager.swift",
                "UpdateCheckCoordinator.swift",
                "Sync/SyncModels.swift",
                "Sync/SyncCrypto.swift",
                "Sync/SyncStorage.swift",
                "Sync/SyncTransport.swift",
                "Sync/DisplayStatsAggregator.swift"
            ]
        ),
        .testTarget(
            name: "KeyStatsCoreTests",
            dependencies: ["KeyStatsCore", "KeyStatsEventCore", "PostHog"],
            path: "KeyStatsTests",
            sources: ["AppStatsTests.swift", "AppKeyBreakdownTests.swift", "AppDetailPresentationTests.swift", "SystemMediaKeyTests.swift", "InteractionProfileTests.swift", "AppActivityTrackerTests.swift", "AnalyticsManagerTests.swift", "StatsManagerTests.swift", "StatsModelsTests.swift", "UpdateCheckCoordinatorTests.swift", "SyncCoreTests.swift"]
        )
    ]
)
