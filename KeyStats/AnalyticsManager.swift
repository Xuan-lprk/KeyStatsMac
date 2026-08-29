import Foundation
import PostHog

final class AnalyticsManager {
    static let shared = AnalyticsManager()

    static let consentKey = "analytics.optIn.v1"

    private let defaults: UserDefaults
    private let stateLock = NSLock()
    private let analyticsFirstOpenUTCKey = "analyticsFirstOpenUTC"
    private var isInitialized = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.consentKey)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            defaults.set(true, forKey: Self.consentKey)
            setupIfEnabled()
        } else {
            stateLock.lock()
            defaults.set(false, forKey: Self.consentKey)
            if isInitialized {
                PostHogSDK.shared.close()
                isInitialized = false
            }
            stateLock.unlock()
        }
    }

    func setupIfEnabled() {
        guard isEnabled else { return }

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isEnabled, !isInitialized else { return }

        let config = PostHogConfig(
            apiKey: "phc_TYyyKIfGgL1CXZx7t9dY7igE3yNwNpjj9aqItSpNVLx",
            host: "https://us.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(analyticsBaseProperties())
        isInitialized = true
    }

    func trackEvent(_ eventName: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }
        setupIfEnabled()

        stateLock.lock()
        defer { stateLock.unlock() }

        guard isEnabled, isInitialized else { return }

        if let properties {
            PostHogSDK.shared.capture(eventName, properties: properties)
        } else {
            PostHogSDK.shared.capture(eventName)
        }
    }

    func trackClick(_ elementName: String, properties: [String: Any]? = nil) {
        var payload = properties ?? [:]
        payload["element_name"] = elementName
        trackEvent("click", properties: payload)
    }

    func trackPageView(_ pageName: String, properties: [String: Any]? = nil) {
        var payload = properties ?? [:]
        payload["page_name"] = pageName
        trackEvent("pageview", properties: payload)
    }

    func firstOpenUTC() -> String {
        if let existing = defaults.string(forKey: analyticsFirstOpenUTCKey), !existing.isEmpty {
            return existing
        }

        let value = ISO8601DateFormatter().string(from: Date())
        defaults.set(value, forKey: analyticsFirstOpenUTCKey)
        return value
    }

    private func analyticsBaseProperties() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let buildVersion = info?["CFBundleVersion"] as? String ?? "0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osMajorVersion = "macOS \(osVersion.majorVersion)"
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        return [
            "app_name": "KeyStats",
            "app_version": shortVersion,
            "app_build": buildVersion,
            "platform": "macos",
            "os": "macOS",
            "os_major_version": osMajorVersion,
            "os_version": osVersionString,
            "first_open_utc": firstOpenUTC(),
            "$app_name": "KeyStats",
            "$app_version": shortVersion,
            "$os": "macOS",
            "$os_version": osMajorVersion
        ]
    }
}
