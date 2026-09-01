import PostHog
import XCTest
@testable import KeyStatsCore

final class AnalyticsManagerTests: XCTestCase {
    func testConsentControlsInitializationTrackingAndRuntimeSwitches() throws {
        let suiteName = "keystats-analytics-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        PostHogSDK.shared.resetForTesting()
        defer {
            PostHogSDK.shared.resetForTesting()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let manager = AnalyticsManager(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: AnalyticsManager.consentKey))
        XCTAssertFalse(manager.isEnabled)

        manager.setupIfEnabled()
        manager.trackEvent("app_opened")
        manager.trackClick("settings")
        manager.trackPageView("stats")

        XCTAssertEqual(PostHogSDK.shared.setupCallCount, 0)
        XCTAssertTrue(PostHogSDK.shared.registeredProperties.isEmpty)
        XCTAssertTrue(PostHogSDK.shared.capturedEvents.isEmpty)

        manager.setEnabled(true)

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(defaults.object(forKey: AnalyticsManager.consentKey) as? Bool, true)
        XCTAssertEqual(PostHogSDK.shared.setupCallCount, 1)
        XCTAssertEqual(PostHogSDK.shared.registeredProperties.count, 1)

        manager.setupIfEnabled()
        manager.trackEvent("app_opened", properties: ["source": "test"])
        manager.trackClick("settings")
        manager.trackPageView("stats")

        XCTAssertEqual(PostHogSDK.shared.setupCallCount, 1)
        XCTAssertEqual(PostHogSDK.shared.capturedEvents.map(\.name), ["app_opened", "click", "pageview"])
        XCTAssertEqual(PostHogSDK.shared.capturedEvents[0].properties?["source"] as? String, "test")
        XCTAssertEqual(PostHogSDK.shared.capturedEvents[1].properties?["element_name"] as? String, "settings")
        XCTAssertEqual(PostHogSDK.shared.capturedEvents[2].properties?["page_name"] as? String, "stats")

        manager.setEnabled(false)
        let eventCountAfterOptOut = PostHogSDK.shared.capturedEvents.count

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(defaults.object(forKey: AnalyticsManager.consentKey) as? Bool, false)
        XCTAssertEqual(PostHogSDK.shared.closeCallCount, 1)

        manager.trackEvent("must_not_send")
        XCTAssertEqual(PostHogSDK.shared.capturedEvents.count, eventCountAfterOptOut)

        manager.setEnabled(true)
        XCTAssertEqual(PostHogSDK.shared.setupCallCount, 2)
    }
}
