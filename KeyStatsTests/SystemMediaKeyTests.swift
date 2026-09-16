import AppKit
import IOKit.hidsystem
import XCTest
@testable import KeyStatsEventCore
@testable import KeyStatsCore

final class SystemMediaKeyTests: XCTestCase {
    private func event(_ code: Int32, state: Int32 = NX_KEYDOWN,
                       repeatFlag: Int = 0, subtype: Int16 = Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)) throws -> CGEvent {
        let data = (Int(code) << 16) | (Int(state) << 8) | repeatFlag
        let ns = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: subtype, data1: data, data2: -1))
        return try XCTUnwrap(ns.cgEvent)
    }

    func testBrightnessVolumeAndPlaybackPressPayloads() throws {
        let examples: [(Int32, String)] = [
            (NX_KEYTYPE_BRIGHTNESS_DOWN, "BrightnessDown"), (NX_KEYTYPE_BRIGHTNESS_UP, "BrightnessUp"),
            (NX_KEYTYPE_SOUND_DOWN, "VolumeDown"), (NX_KEYTYPE_SOUND_UP, "VolumeUp"),
            (NX_KEYTYPE_MUTE, "Mute"), (NX_KEYTYPE_PLAY, "PlayPause"),
            (NX_KEYTYPE_NEXT, "NextTrack"), (NX_KEYTYPE_PREVIOUS, "PreviousTrack"),
            (NX_KEYTYPE_FAST, "FastForward"), (NX_KEYTYPE_REWIND, "Rewind"),
            (NX_KEYTYPE_ILLUMINATION_UP, "KeyboardBrightnessUp"),
            (NX_KEYTYPE_ILLUMINATION_DOWN, "KeyboardBrightnessDown"),
            (NX_KEYTYPE_ILLUMINATION_TOGGLE, "KeyboardBacklightToggle")
        ]
        for (code, name) in examples {
            let cg = try event(code)
            let payload = try XCTUnwrap(PayloadBuilder.build(from: cg, type: SystemMediaKey.eventType))
            XCTAssertEqual(SystemMediaKey.keyName(from: payload), name)
            XCTAssertEqual(Set(payload.keys), Set([HelperPayloadFields.type,
                HelperPayloadFields.mediaKeyCode, HelperPayloadFields.flags]))
        }
    }

    func testDownRepeatUpProducesOneRecordPerPress() throws {
        let events = try [event(NX_KEYTYPE_SOUND_UP), event(NX_KEYTYPE_SOUND_UP, repeatFlag: 1),
                          event(NX_KEYTYPE_SOUND_UP, repeatFlag: 1), event(NX_KEYTYPE_SOUND_UP, state: NX_KEYUP)]
        let payloads = events.compactMap { PayloadBuilder.build(from: $0, type: SystemMediaKey.eventType) }
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(SystemMediaKey.keyName(from: payloads[0]), "VolumeUp")
    }

    func testRejectsUnrelatedSubtypeUnknownCodeAndMalformedPayload() throws {
        XCTAssertNil(PayloadBuilder.build(from: try event(NX_KEYTYPE_SOUND_UP, subtype: 7), type: SystemMediaKey.eventType))
        XCTAssertNil(PayloadBuilder.build(from: try event(0x7fff), type: SystemMediaKey.eventType))
        XCTAssertNil(PayloadBuilder.build(from: try event(NX_KEYTYPE_SOUND_UP, state: 0), type: SystemMediaKey.eventType))
        XCTAssertNil(SystemMediaKey.keyName(from: [:]))
        XCTAssertNil(SystemMediaKey.keyName(from: [HelperPayloadFields.type: NSNumber(value: SystemMediaKey.eventType.rawValue),
                                                  HelperPayloadFields.mediaKeyCode: "VolumeUp"]))
        XCTAssertNil(SystemMediaKey.keyName(for: Int.max))
    }

    func testOrdinaryF1RemainsAnOrdinaryKeyboardEvent() throws {
        let cg = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 122, keyDown: true))
        XCTAssertNil(SystemMediaKey.pressedKeyCode(from: cg))
        let payload = try XCTUnwrap(PayloadBuilder.build(from: cg, type: .keyDown))
        XCTAssertEqual((payload[HelperPayloadFields.keyCode] as? NSNumber)?.intValue, 122)
        XCTAssertNil(payload[HelperPayloadFields.mediaKeyCode])
        XCTAssertNil(SystemMediaKey.keyName(from: payload))
    }

    func testMediaKeyFeedsExistingGlobalStatsWithoutAppAttribution() throws {
        let suite = "SystemMediaKeyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fixedCalendar = calendar
        let manager = StatsManager(environment: .init(userDefaults: defaults,
            now: { Date(timeIntervalSinceReferenceDate: 0) }, calendar: { fixedCalendar },
            makeDateKeyFormatter: {
                let formatter = DateFormatter()
                formatter.calendar = fixedCalendar
                formatter.timeZone = fixedCalendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            }, notificationCenter: NotificationCenter(), schedulesAutomaticWork: false,
            blocksLegacyImport: { false }, syncDisplayContext: { nil }, sendThresholdNotification: { _, _, _ in }))
        let payload = try XCTUnwrap(PayloadBuilder.build(from: try event(NX_KEYTYPE_BRIGHTNESS_DOWN), type: SystemMediaKey.eventType))
        manager.incrementKeyPresses(keyName: try XCTUnwrap(SystemMediaKey.keyName(from: payload)))
        XCTAssertEqual(manager.currentStats.keyPresses, 1)
        XCTAssertEqual(manager.currentStats.keyPressCounts, ["BrightnessDown": 1])
        XCTAssertTrue(manager.currentStats.appStats.isEmpty)
    }
}
