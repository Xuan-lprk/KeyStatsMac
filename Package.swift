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
            exclude: ["Package.swift", "README.md", "Tests", "Assets.xcassets", "Info.plist", "KeyStatsHelper.entitlements", "main.swift",
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
                "MechanicalKeyboardWindowController.swift",
                "Main.storyboard",
                "Info.plist",
                "en.lproj",
                "zh-Hans.lproj",
                "zh-Hant.lproj",
                "AppStatsViewController.swift",
                "AppDetailView.swift",
                "KeyboardHeatmapView.swift",
                "KeyboardHeatmapRepresentable.swift",
                "KeyboardVisualizationViewController.swift",
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
                "TypingPulseView.swift",
                "GeekTypingPulseView.swift",
                "GeekStatsPopoverViewController.swift",
                "MenuUIStyle.swift",
                "SettingsWindowController.swift",
                "MainWindowViewController.swift"
            ],
            sources: [
                "AppLaunchMode.swift",
                "AppStats.swift",
                "AppKeyBreakdown.swift",
                "AppDetailPresentation.swift",
                "InteractionProfile.swift",
                "AppActivityTracker.swift",
                "StatsModels.swift",
                "PhysicalKeyMapping.swift",
                "KeyboardLayout.swift",
                "CumulativeKeyboardSnapshot.swift",
                "KeyboardTrackingPeriod.swift",
                "KeyboardUsageProgress.swift",
                "GrowthKeyboardPresentation.swift",
                "GrowthPlaybackState.swift",
                "EditorialKeyboardRenderer.swift",
                "GrowthKeyboard3DGeometry.swift",
                "GrowthKeyboard3DScene.swift",
                "GrowthKeyboard3DRenderer.swift",
                "MechanicalKeyboardScene.swift",
                "MechanicalKeyboardGeometry.swift",
                "MechanicalKeyboardView.swift",
                "GrowthKeyboardViewController.swift",
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
            sources: ["GrowthKeyboard3DTests.swift", "AppLaunchModeTests.swift", "GrowthKeyboardTests.swift", "KeyboardUsageProgressTests.swift", "KeyboardTrackingPeriodTests.swift", "CumulativeKeyboardSnapshotTests.swift", "KeyboardLayoutTests.swift", "PhysicalKeyMappingTests.swift", "AppStatsTests.swift", "AppKeyBreakdownTests.swift", "AppDetailPresentationTests.swift", "SystemMediaKeyTests.swift", "InteractionProfileTests.swift", "AppActivityTrackerTests.swift", "AnalyticsManagerTests.swift", "StatsManagerTests.swift", "StatsModelsTests.swift", "UpdateCheckCoordinatorTests.swift", "SyncCoreTests.swift"]
        )
    ]
)
