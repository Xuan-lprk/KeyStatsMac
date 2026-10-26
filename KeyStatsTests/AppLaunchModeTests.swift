import XCTest
@testable import KeyStatsCore

final class AppLaunchModeTests: XCTestCase {
    func testNormalLaunchIsTheDefault() {
        XCTAssertEqual(AppLaunchMode(arguments: ["KeyStats"]), .normal)
        XCTAssertEqual(AppLaunchMode(arguments: []), .normal)
    }

    func testOnlyTheExactArgumentEnablesAcceptanceInDebug() {
        let mode = AppLaunchMode(arguments: ["KeyStats", "--debug-gui-acceptance"])
        #if DEBUG
        XCTAssertEqual(mode, .guiAcceptance)
        #else
        XCTAssertEqual(mode, .normal)
        #endif
        for argument in ["--debug-gui-acceptance=true", "--debug-gui-acceptance-extra", "debug-gui-acceptance"] {
            XCTAssertEqual(AppLaunchMode(arguments: ["KeyStats", argument]), .normal)
        }
        XCTAssertEqual(AppLaunchMode(arguments: ["--debug-gui-acceptance"]), .normal)
    }

    func testAcceptanceRejectsIncompatibleHelperBeforeMonitoring() {
        XCTAssertTrue(AppLaunchMode.guiAcceptance.allowsHelperVersion(1, expected: 1))
        XCTAssertFalse(AppLaunchMode.guiAcceptance.allowsHelperVersion(0, expected: 1))
        XCTAssertFalse(AppLaunchMode.guiAcceptance.allowsHelperVersion(2, expected: 1))
    }

    func testNormalLaunchRetainsExistingHelperVersionBehavior() {
        XCTAssertTrue(AppLaunchMode.normal.allowsHelperVersion(0, expected: 1))
        XCTAssertTrue(AppLaunchMode.normal.allowsHelperVersion(1, expected: 1))
        XCTAssertTrue(AppLaunchMode.normal.allowsHelperVersion(2, expected: 1))
    }

    func testUpdaterRequiresAConfiguredPublicKeyAndNormalLaunch() {
        for key in [nil, "", "not-base64", Data(repeating: 1, count: 31).base64EncodedString(),
                    Data(repeating: 1, count: 33).base64EncodedString()] {
            XCTAssertFalse(AppLaunchMode.normal.allowsUpdater(publicKey: key, updatesEnabled: true))
        }
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertTrue(AppLaunchMode.normal.allowsUpdater(publicKey: key, updatesEnabled: true))
        XCTAssertFalse(AppLaunchMode.normal.allowsUpdater(publicKey: key, updatesEnabled: false))
        XCTAssertFalse(AppLaunchMode.guiAcceptance.allowsUpdater(publicKey: key, updatesEnabled: true))
    }
}
