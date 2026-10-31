import Foundation
import CoreGraphics

// Only these aggregates cross the process boundary. No raw event is retained.
final class Aggregates: EventPayloadSink {
    private(set) var keyPresses = 0
    private(set) var leftClicks = 0
    private(set) var rightClicks = 0
    private(set) var middleClicks = 0
    private(set) var otherClicks = 0
    private(set) var mouseDistancePoints = 0.0
    private(set) var scrollDistanceUnits = 0.0
    private var previousPosition: CGPoint?

    func forward(payload: [String: Any]) {
        guard let raw = (payload[HelperPayloadFields.type] as? NSNumber)?.uint32Value else { return }
        if raw == SystemMediaKey.eventType.rawValue {
            keyPresses += 1
            return
        }
        guard let type = CGEventType(rawValue: raw) else { return }
        switch type {
        case .keyDown:
            if (payload[HelperPayloadFields.isAutoRepeat] as? NSNumber)?.boolValue != true { keyPresses += 1 }
        case .leftMouseDown: leftClicks += 1
        case .rightMouseDown: rightClicks += 1
        case .otherMouseDown:
            if (payload[HelperPayloadFields.buttonNumber] as? NSNumber)?.intValue == 2 { middleClicks += 1 }
            else { otherClicks += 1 }
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            guard let x = (payload[HelperPayloadFields.locationX] as? NSNumber)?.doubleValue,
                  let y = (payload[HelperPayloadFields.locationY] as? NSNumber)?.doubleValue,
                  x.isFinite, y.isFinite else { return }
            let position = CGPoint(x: x, y: y)
            if let last = previousPosition {
                let distance = hypot(position.x - last.x, position.y - last.y)
                if distance < 500 { mouseDistancePoints += distance }
            }
            previousPosition = position
        case .scrollWheel:
            let dx = (payload[HelperPayloadFields.scrollDX] as? NSNumber)?.doubleValue ?? 0
            let dy = (payload[HelperPayloadFields.scrollDY] as? NSNumber)?.doubleValue ?? 0
            if dx.isFinite, dy.isFinite { scrollDistanceUnits += hypot(dx, dy) }
        default: break // Modifier-only presses are not counted in this probe.
        }
    }

    var snapshot: [String: Any] {
        ["schemaVersion": 1, "kind": "snapshot", "keyPresses": keyPresses,
         "leftClicks": leftClicks, "rightClicks": rightClicks,
         "middleClicks": middleClicks, "otherClicks": otherClicks,
         "mouseDistancePoints": mouseDistancePoints, "scrollDistanceUnits": scrollDistanceUnits]
    }
}
