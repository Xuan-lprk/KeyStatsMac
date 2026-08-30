import Cocoa
import CoreGraphics

struct AppIdentity: Equatable {
    let bundleId: String
    let displayName: String

    static let unknown = AppIdentity(bundleId: "unknown", displayName: "")
}

struct PIDAppIdentityCache {
    private var pidToBundleId: [pid_t: String] = [:]
    private var bundleIdToName: [String: String] = [:]

    func identity(forPID pid: pid_t) -> AppIdentity? {
        guard let bundleId = pidToBundleId[pid] else { return nil }
        return AppIdentity(bundleId: bundleId, displayName: bundleIdToName[bundleId] ?? "")
    }

    mutating func store(bundleId: String, displayName: String, forPID pid: pid_t) {
        pidToBundleId[pid] = bundleId
        storeDisplayName(displayName, forBundleId: bundleId)
    }

    mutating func storeDisplayName(_ displayName: String, forBundleId bundleId: String) {
        guard !displayName.isEmpty else { return }
        bundleIdToName[bundleId] = displayName
    }

    @discardableResult
    mutating func removePID(_ pid: pid_t, matchingBundleId bundleId: String?) -> Bool {
        guard let cachedBundleId = pidToBundleId[pid] else { return false }
        if let bundleId, cachedBundleId != bundleId {
            return false
        }
        pidToBundleId.removeValue(forKey: pid)
        return true
    }
}

final class AppActivityTracker {
    static let shared = AppActivityTracker()

    private let lock = NSLock()
    private var frontmostIdentity = AppIdentity.unknown
    private var identityCache = PIDAppIdentityCache()

    private init() {
        let workspace = NSWorkspace.shared
        updateFrontmostApp(workspace.frontmostApplication)
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: workspace
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: workspace
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func appIdentity(for event: CGEvent?) -> AppIdentity {
        if let event = event {
            let pidValue = event.getIntegerValueField(.eventSourceUnixProcessID)
            if pidValue > 0 {
                let pid = pid_t(pidValue)
                if let identity = identityForPID(pid) {
                    return identity
                }
            }
        }
        return currentFrontmostIdentity()
    }

    /// 直接基于 PID 查询（helper 路径只带 PID，无 CGEvent）。
    func appIdentity(forPID pid: pid_t) -> AppIdentity {
        if pid > 0, let identity = identityForPID(pid) {
            return identity
        }
        return currentFrontmostIdentity()
    }

    private func identityForPID(_ pid: pid_t) -> AppIdentity? {
        lock.lock()
        if let identity = identityCache.identity(forPID: pid) {
            lock.unlock()
            return identity
        }
        lock.unlock()

        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleId = app.bundleIdentifier else {
            return nil
        }
        let name = app.localizedName ?? ""

        lock.lock()
        identityCache.store(bundleId: bundleId, displayName: name, forPID: pid)
        let identity = AppIdentity(bundleId: bundleId, displayName: name)
        lock.unlock()
        return identity
    }

    private func currentFrontmostIdentity() -> AppIdentity {
        lock.lock()
        let identity = frontmostIdentity
        lock.unlock()
        return identity
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        updateFrontmostApp(app)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        lock.lock()
        identityCache.removePID(app.processIdentifier, matchingBundleId: app.bundleIdentifier)
        lock.unlock()
    }

    private func updateFrontmostApp(_ app: NSRunningApplication?) {
        guard let app = app, let bundleId = app.bundleIdentifier else { return }
        let name = app.localizedName ?? ""
        lock.lock()
        frontmostIdentity = AppIdentity(bundleId: bundleId, displayName: name)
        identityCache.storeDisplayName(name, forBundleId: bundleId)
        lock.unlock()
    }
}
