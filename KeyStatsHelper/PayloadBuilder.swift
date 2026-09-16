import Foundation
import CoreGraphics

enum PayloadBuilder {
    static func build(from event: CGEvent, type: CGEventType) -> [String: Any]? {
        if type == SystemMediaKey.eventType {
            guard let code = SystemMediaKey.pressedKeyCode(from: event) else { return nil }
            // System actions have no reliable target App. Forward only a validated key and modifiers.
            return [
                HelperPayloadFields.type: NSNumber(value: type.rawValue),
                HelperPayloadFields.mediaKeyCode: NSNumber(value: code),
                HelperPayloadFields.flags: NSNumber(value: event.flags.rawValue)
            ]
        }
        var p: [String: Any] = [
            HelperPayloadFields.type: NSNumber(value: type.rawValue),
            HelperPayloadFields.monotonicTime: NSNumber(value: ProcessInfo.processInfo.systemUptime),
            HelperPayloadFields.sourcePID: NSNumber(value: event.getIntegerValueField(.eventSourceUnixProcessID))
        ]

        switch type {
        case .keyDown, .flagsChanged:
            p[HelperPayloadFields.keyCode] = NSNumber(value: event.getIntegerValueField(.keyboardEventKeycode))
            p[HelperPayloadFields.keyboardType] = NSNumber(value: event.getIntegerValueField(.keyboardEventKeyboardType))
            p[HelperPayloadFields.flags] = NSNumber(value: event.flags.rawValue)
            p[HelperPayloadFields.isAutoRepeat] = NSNumber(value: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if let role = ButtonRoleClassifier.role(for: type, event: event) {
                p[HelperPayloadFields.buttonRole] = role as NSString
            }
            p[HelperPayloadFields.buttonNumber] = NSNumber(value: event.getIntegerValueField(.mouseEventButtonNumber))

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let loc = event.location
            p[HelperPayloadFields.locationX] = NSNumber(value: Double(loc.x))
            p[HelperPayloadFields.locationY] = NSNumber(value: Double(loc.y))

        case .scrollWheel:
            p[HelperPayloadFields.scrollDX] = NSNumber(value: event.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            p[HelperPayloadFields.scrollDY] = NSNumber(value: event.getDoubleValueField(.scrollWheelEventDeltaAxis1))
            p[HelperPayloadFields.scrollPhase] = NSNumber(value: event.getIntegerValueField(.scrollWheelEventScrollPhase))
            p[HelperPayloadFields.scrollMomentumPhase] = NSNumber(value: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
            p[HelperPayloadFields.scrollIsContinuous] = NSNumber(value: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0)

        default:
            return nil
        }
        return p
    }
}
