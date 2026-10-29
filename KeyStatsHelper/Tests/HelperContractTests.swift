import AppKit
import IOKit.hidsystem
import XCTest
@testable import KeyStatsHelper

/// Synthetic payload checks only: no event tap, XPC connection, or service start.
final class HelperContractTests: XCTestCase {
    private let baseFields: Set<String> = [
        HelperPayloadFields.type,
        HelperPayloadFields.monotonicTime,
        HelperPayloadFields.sourcePID
    ]

    func testKeyboardPayloadContainsCodesAndFlagsWithoutText() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.flags = [.maskShift, .maskCommand]
        let syntheticText: [UniChar] = [0x61, 0x62]
        syntheticText.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
        }
        let payload = try XCTUnwrap(PayloadBuilder.build(from: event, type: .keyDown))
        XCTAssertEqual(Set(payload.keys), baseFields.union([
            HelperPayloadFields.keyCode, HelperPayloadFields.keyboardType,
            HelperPayloadFields.flags, HelperPayloadFields.isAutoRepeat
        ]))
        XCTAssertEqual((payload[HelperPayloadFields.keyCode] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((payload[HelperPayloadFields.flags] as? NSNumber)?.uint64Value, event.flags.rawValue)
        XCTAssertTrue(payload.values.allSatisfy { $0 is NSNumber })
    }

    func testModifierPayloadRetainsTheKeyboardWireShape() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true))
        let payload = try XCTUnwrap(PayloadBuilder.build(from: event, type: .flagsChanged))
        XCTAssertEqual((payload[HelperPayloadFields.type] as? NSNumber)?.uint32Value, CGEventType.flagsChanged.rawValue)
        XCTAssertEqual((payload[HelperPayloadFields.keyCode] as? NSNumber)?.intValue, 56)
        XCTAssertNil(payload[HelperPayloadFields.locationX])
        XCTAssertNil(payload[HelperPayloadFields.locationY])
    }

    func testSideButtonPayloadDoesNotIncludeClickCoordinates() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                         mouseCursorPosition: CGPoint(x: 12, y: 34), mouseButton: .center))
        for (number, role) in [(3, ButtonRole.back), (4, ButtonRole.forward)] {
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
            let payload = try XCTUnwrap(PayloadBuilder.build(from: event, type: .otherMouseDown))
            XCTAssertEqual(Set(payload.keys), baseFields.union([
                HelperPayloadFields.buttonRole, HelperPayloadFields.buttonNumber
            ]))
            XCTAssertEqual(payload[HelperPayloadFields.buttonRole] as? String, role)
        }
    }

    func testMovementCoordinatesStayInTheExistingTransientPayload() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                         mouseCursorPosition: CGPoint(x: 12, y: 34), mouseButton: .left))
        let payload = try XCTUnwrap(PayloadBuilder.build(from: event, type: .mouseMoved))
        XCTAssertEqual(Set(payload.keys), baseFields.union([
            HelperPayloadFields.locationX, HelperPayloadFields.locationY
        ]))
        XCTAssertEqual((payload[HelperPayloadFields.locationX] as? NSNumber)?.doubleValue, 12)
        XCTAssertEqual((payload[HelperPayloadFields.locationY] as? NSNumber)?.doubleValue, 34)
    }

    func testScrollPayloadRetainsSessionMetadataWithoutCoordinates() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                         wheelCount: 2, wheel1: 12, wheel2: -4, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let payload = try XCTUnwrap(PayloadBuilder.build(from: event, type: .scrollWheel))
        XCTAssertEqual(Set(payload.keys), baseFields.union([
            HelperPayloadFields.scrollDX, HelperPayloadFields.scrollDY,
            HelperPayloadFields.scrollPhase, HelperPayloadFields.scrollMomentumPhase,
            HelperPayloadFields.scrollIsContinuous
        ]))
        XCTAssertEqual((payload[HelperPayloadFields.scrollPhase] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((payload[HelperPayloadFields.scrollIsContinuous] as? NSNumber)?.boolValue, true)
    }

    func testMediaPayloadAcceptsOnlyAValidatedPress() throws {
        for (state, isRepeat, shouldForward) in [(NX_KEYDOWN, 0, true), (NX_KEYUP, 0, false), (NX_KEYDOWN, 1, false)] {
            let data = (Int(NX_KEYTYPE_SOUND_UP) << 16) | (Int(state) << 8) | isRepeat
            let event = try XCTUnwrap(NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: data, data2: -1)?.cgEvent)
            let payload = PayloadBuilder.build(from: event, type: SystemMediaKey.eventType)
            XCTAssertEqual(payload != nil, shouldForward)
            if let payload {
                XCTAssertEqual(Set(payload.keys), Set([
                    HelperPayloadFields.type, HelperPayloadFields.mediaKeyCode, HelperPayloadFields.flags
                ]))
                XCTAssertEqual(SystemMediaKey.keyName(from: payload), "VolumeUp")
            }
        }
    }

    func testUnsupportedEventsAreNotForwarded() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false))
        XCTAssertNil(PayloadBuilder.build(from: event, type: .keyUp))
        XCTAssertNil(PayloadBuilder.build(from: event, type: .leftMouseUp))
    }

    func testPackageKeepsTheExistingServiceIdentityAndXPCInterfaces() {
        XCTAssertEqual(HelperLocations.interfaceVersion, 1)
        XCTAssertEqual(HelperLocations.mainBundleId, "com.xuanlprk.KeyStatsMac")
        XCTAssertEqual(HelperLocations.helperBundleId, "com.xuanlprk.KeyStatsMac.helper")
        XCTAssertEqual(HelperLocations.machServiceName, HelperLocations.helperBundleId)
        XCTAssertEqual(HelperLocations.launchAgentLabel, HelperLocations.helperBundleId)
        XCTAssertNotNil(NSXPCInterface(with: KeyStatsHelperProtocol.self))
        XCTAssertNotNil(NSXPCInterface(with: KeyStatsEventSinkProtocol.self))
    }
}
