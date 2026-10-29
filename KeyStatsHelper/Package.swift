// swift-tools-version:5.9
import PackageDescription

// Compile the same sources as the production Xcode helper target. This package
// does not install, sign, register, or launch the service.
let package = Package(
    name: "KeyStatsHelper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KeyStatsHelper", targets: ["KeyStatsHelper"])
    ],
    targets: [
        .executableTarget(
            name: "KeyStatsHelper",
            path: ".",
            exclude: ["Assets.xcassets", "Info.plist", "KeyStatsHelper.entitlements", "README.md", "Tests"],
            sources: [
                "main.swift",
                "EventTapController.swift",
                "PayloadBuilder.swift",
                "HelperPayloadFields.swift",
                "ButtonRoleClassifier.swift",
                "SystemMediaKey.swift",
                "HelperProtocols.swift",
                "HelperLocations.swift",
                "HelperXPCListener.swift",
                "HelperIdleSupervisor.swift"
            ]
        ),
        .testTarget(
            name: "KeyStatsHelperTests",
            dependencies: ["KeyStatsHelper"],
            path: "Tests"
        )
    ]
)
