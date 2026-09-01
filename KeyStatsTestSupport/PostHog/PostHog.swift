import Foundation

public final class PostHogConfig {
    public let apiKey: String
    public let host: String
    public var captureApplicationLifecycleEvents = false
    public var captureScreenViews = false

    public init(apiKey: String, host: String) {
        self.apiKey = apiKey
        self.host = host
    }
}

public final class PostHogSDK {
    public struct CapturedEvent {
        public let name: String
        public let properties: [String: Any]?
    }

    public static let shared = PostHogSDK()

    public private(set) var setupCallCount = 0
    public private(set) var closeCallCount = 0
    public private(set) var registeredProperties: [[String: Any]] = []
    public private(set) var capturedEvents: [CapturedEvent] = []
    public private(set) var lastConfig: PostHogConfig?

    private init() {}

    public func setup(_ config: PostHogConfig) {
        setupCallCount += 1
        lastConfig = config
    }

    public func register(_ properties: [String: Any]) {
        registeredProperties.append(properties)
    }

    public func capture(_ eventName: String) {
        capturedEvents.append(CapturedEvent(name: eventName, properties: nil))
    }

    public func capture(_ eventName: String, properties: [String: Any]) {
        capturedEvents.append(CapturedEvent(name: eventName, properties: properties))
    }

    public func close() {
        closeCallCount += 1
    }

    public func resetForTesting() {
        setupCallCount = 0
        closeCallCount = 0
        registeredProperties = []
        capturedEvents = []
        lastConfig = nil
    }
}
