import Foundation

extension DailyStats {
    var formattedMouseDistance: String {
        StatsManager.shared.formatMouseDistance(mouseDistance)
    }

    var formattedScrollDistance: String {
        if scrollDistance >= 10000 {
            return String(format: "%.1f kPx", scrollDistance / 1000)
        } else {
            return String(format: "%.0f px", scrollDistance)
        }
    }
}

extension AllTimeStats {
    var formattedMouseDistance: String {
        StatsManager.shared.formatMouseDistance(totalMouseDistance)
    }

    var formattedScrollDistance: String {
        if totalScrollDistance >= 10000 {
            return String(format: "%.1f kPx", totalScrollDistance / 1000)
        } else {
            return String(format: "%.0f px", totalScrollDistance)
        }
    }
}

extension StatsManager.Environment {
    static var live: StatsManager.Environment {
        StatsManager.Environment(
            userDefaults: .standard,
            now: Date.init,
            calendar: { Calendar.current },
            makeDateKeyFormatter: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            },
            notificationCenter: .default,
            schedulesAutomaticWork: true,
            blocksLegacyImport: { SyncCoordinator.shared.blocksLegacyImport },
            syncDisplayContext: {
                let state = SyncCoordinator.shared.state
                guard state.isConfigured, !state.needsRepair else { return nil }
                return StatsManager.SyncDisplayContext(
                    deviceId: state.deviceId,
                    remoteSnapshots: RemoteShardCache.shared.snapshots(excludingDeviceId: state.deviceId)
                )
            },
            sendThresholdNotification: { metric, count, threshold in
                let notificationMetric: NotificationManager.Metric
                switch metric {
                case .keyPresses:
                    notificationMetric = .keyPresses
                case .clicks:
                    notificationMetric = .clicks
                }
                NotificationManager.shared.sendThresholdNotification(
                    metric: notificationMetric,
                    count: count,
                    threshold: threshold
                )
            }
        )
    }
}

extension StatsManager {
    static let shared = StatsManager(environment: .live)
}
