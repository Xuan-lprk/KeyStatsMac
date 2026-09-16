import AppKit
import IOKit.hidsystem

/// Public NSEvent bridge for NX auxiliary keys; no private CGEventField offsets.
enum SystemMediaKey {
    static let eventType = CGEventType(rawValue: UInt32(NX_SYSDEFINED))!

    static func pressedKeyCode(from event: CGEvent) -> Int? {
        guard event.type == eventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS else { return nil }
        // NX auxiliary data1: key flavor in bits 16...31, down/up in 8...15,
        // repeat in the low byte. Do not call NSEvent.isARepeat on systemDefined.
        let data = UInt32(truncatingIfNeeded: nsEvent.data1)
        let state = (data >> 8) & 0xff
        let isRepeat = (data & 0xff) != 0
        let code = Int((data >> 16) & 0xffff)
        guard state == NX_KEYDOWN, !isRepeat, keyName(for: code) != nil else { return nil }
        return code
    }

    static func keyName(for code: Int) -> String? {
        switch Int32(exactly: code) {
        case NX_KEYTYPE_BRIGHTNESS_DOWN: return "BrightnessDown"
        case NX_KEYTYPE_BRIGHTNESS_UP: return "BrightnessUp"
        case NX_KEYTYPE_SOUND_DOWN: return "VolumeDown"
        case NX_KEYTYPE_SOUND_UP: return "VolumeUp"
        case NX_KEYTYPE_MUTE: return "Mute"
        case NX_KEYTYPE_PLAY: return "PlayPause"
        case NX_KEYTYPE_NEXT: return "NextTrack"
        case NX_KEYTYPE_PREVIOUS: return "PreviousTrack"
        case NX_KEYTYPE_FAST: return "FastForward"
        case NX_KEYTYPE_REWIND: return "Rewind"
        case NX_KEYTYPE_ILLUMINATION_DOWN: return "KeyboardBrightnessDown"
        case NX_KEYTYPE_ILLUMINATION_UP: return "KeyboardBrightnessUp"
        case NX_KEYTYPE_ILLUMINATION_TOGGLE: return "KeyboardBacklightToggle"
        default: return nil
        }
    }

    static func keyName(from payload: [String: Any]) -> String? {
        guard (payload[HelperPayloadFields.type] as? NSNumber)?.uint32Value == eventType.rawValue,
              let code = (payload[HelperPayloadFields.mediaKeyCode] as? NSNumber)?.intValue
        else { return nil }
        return keyName(for: code)
    }
}
