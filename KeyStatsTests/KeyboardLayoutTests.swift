import XCTest
@testable import KeyStatsCore

final class KeyboardLayoutTests: XCTestCase {
    private let layout = KeyboardLayout.macStyle

    func testKeyIDsAreUniqueAndRowsKeepTheirOriginalOrder() {
        let expectedRows = [
            ["Esc"] + (1...12).map { "F\($0)" },
            ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Delete"],
            ["Tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
            ["CapsLock", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "Return"],
            ["LeftShift", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "RightShift"],
            ["Fn", "Ctrl", "LeftOption", "LeftCmd", "Space", "RightCmd", "RightOption",
             "Left", "Up", "Down", "Right"]
        ]
        XCTAssertEqual(layout.rows.map { $0.keys.map(\.id) }, expectedRows)
        XCTAssertEqual(layout.keys.count, 77)
        XCTAssertEqual(Set(layout.keys.map(\.id)).count, layout.keys.count)
    }

    func testWidthsAndSpacingPreserveTheFixedKeyboard() throws {
        let expectedWidths = ["Esc": 1.45, "Delete": 2.23, "\\": 1.78,
                              "Tab": 1.45, "CapsLock": 1.8, "Return": 2.58,
                              "LeftShift": 2.45, "RightShift": 3.08, "Space": 6.0,
                              "Ctrl": 1.1, "LeftOption": 1.1, "RightOption": 1.1,
                              "LeftCmd": 1.3, "RightCmd": 1.3]
        for (id, width) in expectedWidths {
            let key = try XCTUnwrap(layout.keys.first { $0.id == id })
            XCTAssertEqual(key.widthUnits, width, accuracy: 1e-12, id)
        }
        XCTAssertEqual(layout.keySpacingUnits, 0.15)
        for (row, y) in zip(layout.rows, [0.0, 1.15, 2.3, 3.45, 4.6, 5.75]) {
            XCTAssertEqual(row.yUnits, y, accuracy: 1e-12)
            XCTAssertEqual(row.startXUnits, 0)
        }
        for key in layout.rows[0].keys.dropFirst() {
            XCTAssertEqual(key.widthUnits, 1.1608333333333334, accuracy: 1e-12)
        }
    }

    func testLegendsAndModifierFallbackRemainUnchanged() throws {
        let keys = Dictionary(uniqueKeysWithValues: layout.keys.map { ($0.id, $0) })
        XCTAssertEqual(keys["="]?.label, "+\n=")
        XCTAssertEqual(keys["1"]?.label, "!\n1")
        XCTAssertEqual(keys["'"]?.label, "\"\n'")
        XCTAssertEqual(keys["Fn"]?.symbolName, "globe")
        XCTAssertEqual(keys["Ctrl"]?.symbolName, "control")
        for (left, right, symbol, fallback) in [
            ("LeftCmd", "RightCmd", "command", "Cmd"),
            ("LeftShift", "RightShift", "shift", "Shift"),
            ("LeftOption", "RightOption", "option", "Option")
        ] {
            XCTAssertEqual(keys[left]?.symbolName, symbol)
            XCTAssertEqual(keys[right]?.symbolName, symbol)
            XCTAssertEqual(keys[left]?.fallbackCountIDs, [fallback])
            XCTAssertEqual(keys[right]?.fallbackCountIDs, [])
        }
        XCTAssertEqual(keys["Space"]?.label, "")
        XCTAssertEqual(keys["Esc"]?.label, "esc")
        XCTAssertEqual(keys["Return"]?.label, "return")
    }

    func testArrowClusterRetainsHalfHeightAndIndependentPosition() throws {
        let bottom = layout.rows[5]
        let keys = Dictionary(uniqueKeysWithValues: bottom.keys.map { ($0.id, $0) })
        let left = try XCTUnwrap(keys["Left"])
        let up = try XCTUnwrap(keys["Up"])
        let down = try XCTUnwrap(keys["Down"])
        let right = try XCTUnwrap(keys["Right"])
        XCTAssertEqual(left.heightUnits, 1)
        XCTAssertEqual(right.heightUnits, 1)
        XCTAssertEqual(up.heightUnits, 0.48, accuracy: 1e-12)
        XCTAssertEqual(down.heightUnits, 0.48, accuracy: 1e-12)
        XCTAssertEqual(down.yOffsetUnits, 0.52, accuracy: 1e-12)
        XCTAssertEqual(up.xUnits, down.xUnits)
        XCTAssertEqual(try XCTUnwrap(up.xUnits) - XCTUnwrap(left.xUnits), 1.15, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(right.xUnits) - XCTUnwrap(up.xUnits), 1.15, accuracy: 1e-12)
        XCTAssertEqual([left.label, up.label, down.label, right.label], ["◀", "▲", "▼", "▶"])
    }

    func testSupportedIDsIncludeExactlyVisibleKeysAndGenericFallbacks() {
        let visibleIDs = Set(layout.keys.map(\.id))
        XCTAssertEqual(layout.supportedKeyIDs, visibleIDs.union(["Cmd", "Shift", "Option"]))
        XCTAssertEqual(layout.supportedKeyIDs.count, 80)
        let input = Dictionary(uniqueKeysWithValues: layout.supportedKeyIDs.map { ($0, 1) })
        XCTAssertEqual(PhysicalKeyMapping.map(input).counts, input)
        XCTAssertTrue(PhysicalKeyMapping.map(input).unsupported.isEmpty)
        XCTAssertTrue(layout.supportedKeyIDs.isDisjoint(with:
            ["F13", "F19", "Home", "End", "Enter", "BrightnessUp", "VolumeUp", "Key160"]))
    }

    func testEveryOriginalKeyKeepsItsUnitGeometry() {
        // Captured from the pre-extraction AppKit renderer, independent of the new model.
        let expected: [(String, Double, Double, Double, Double)] = [
            ("Esc", 0, 0, 1.45, 1),
            ("F1", 1.5999999999999999, 0, 1.1608333333333334, 1),
            ("F2", 2.910833333333333, 0, 1.1608333333333334, 1),
            ("F3", 4.221666666666667, 0, 1.1608333333333334, 1),
            ("F4", 5.5325, 0, 1.1608333333333334, 1),
            ("F5", 6.843333333333333, 0, 1.1608333333333334, 1),
            ("F6", 8.154166666666667, 0, 1.1608333333333334, 1),
            ("F7", 9.465, 0, 1.1608333333333334, 1),
            ("F8", 10.775833333333333, 0, 1.1608333333333334, 1),
            ("F9", 12.086666666666666, 0, 1.1608333333333334, 1),
            ("F10", 13.397499999999999, 0, 1.1608333333333334, 1),
            ("F11", 14.708333333333332, 0, 1.1608333333333334, 1),
            ("F12", 16.019166666666667, 0, 1.1608333333333334, 1),
            ("`", 0, 1.15, 1, 1),
            ("1", 1.15, 1.15, 1, 1),
            ("2", 2.3, 1.15, 1, 1),
            ("3", 3.4499999999999997, 1.15, 1, 1),
            ("4", 4.6, 1.15, 1, 1),
            ("5", 5.75, 1.15, 1, 1),
            ("6", 6.9, 1.15, 1, 1),
            ("7", 8.05, 1.15, 1, 1),
            ("8", 9.200000000000001, 1.15, 1, 1),
            ("9", 10.350000000000001, 1.15, 1, 1),
            ("0", 11.500000000000002, 1.15, 1, 1),
            ("-", 12.650000000000002, 1.15, 1, 1),
            ("=", 13.800000000000002, 1.15, 1, 1),
            ("Delete", 14.950000000000003, 1.15, 2.23, 1),
            ("Tab", 0, 2.3, 1.45, 1),
            ("Q", 1.5999999999999999, 2.3, 1, 1),
            ("W", 2.75, 2.3, 1, 1),
            ("E", 3.9, 2.3, 1, 1),
            ("R", 5.05, 2.3, 1, 1),
            ("T", 6.199999999999999, 2.3, 1, 1),
            ("Y", 7.35, 2.3, 1, 1),
            ("U", 8.5, 2.3, 1, 1),
            ("I", 9.65, 2.3, 1, 1),
            ("O", 10.8, 2.3, 1, 1),
            ("P", 11.950000000000001, 2.3, 1, 1),
            ("[", 13.100000000000001, 2.3, 1, 1),
            ("]", 14.250000000000002, 2.3, 1, 1),
            ("\\", 15.400000000000002, 2.3, 1.78, 1),
            ("CapsLock", 0, 3.4499999999999997, 1.8, 1),
            ("A", 1.95, 3.4499999999999997, 1, 1),
            ("S", 3.0999999999999996, 3.4499999999999997, 1, 1),
            ("D", 4.25, 3.4499999999999997, 1, 1),
            ("F", 5.4, 3.4499999999999997, 1, 1),
            ("G", 6.550000000000001, 3.4499999999999997, 1, 1),
            ("H", 7.700000000000001, 3.4499999999999997, 1, 1),
            ("J", 8.850000000000001, 3.4499999999999997, 1, 1),
            ("K", 10.000000000000002, 3.4499999999999997, 1, 1),
            ("L", 11.150000000000002, 3.4499999999999997, 1, 1),
            (";", 12.300000000000002, 3.4499999999999997, 1, 1),
            ("'", 13.450000000000003, 3.4499999999999997, 1, 1),
            ("Return", 14.600000000000003, 3.4499999999999997, 2.58, 1),
            ("LeftShift", 0, 4.6, 2.45, 1),
            ("Z", 2.6, 4.6, 1, 1),
            ("X", 3.75, 4.6, 1, 1),
            ("C", 4.9, 4.6, 1, 1),
            ("V", 6.050000000000001, 4.6, 1, 1),
            ("B", 7.200000000000001, 4.6, 1, 1),
            ("N", 8.350000000000001, 4.6, 1, 1),
            ("M", 9.500000000000002, 4.6, 1, 1),
            (",", 10.650000000000002, 4.6, 1, 1),
            (".", 11.800000000000002, 4.6, 1, 1),
            ("/", 12.950000000000003, 4.6, 1, 1),
            ("RightShift", 14.100000000000003, 4.6, 3.08, 1),
            ("Fn", 0, 5.75, 1, 1),
            ("Ctrl", 1.15, 5.75, 1.1, 1),
            ("LeftOption", 2.4, 5.75, 1.1, 1),
            ("LeftCmd", 3.65, 5.75, 1.3, 1),
            ("Space", 5.1, 5.75, 6, 1),
            ("RightCmd", 11.25, 5.75, 1.3, 1),
            ("RightOption", 12.7, 5.75, 1.1, 1),
            ("Left", 13.879999999999999, 5.75, 1, 1),
            ("Up", 15.03, 5.75, 1, 0.48),
            ("Down", 15.03, 6.2700000000000005, 1, 0.48),
            ("Right", 16.18, 5.75, 1, 1)
        ]
        var actual: [(String, Double, Double, Double, Double)] = []
        for row in layout.rows {
            var x = row.startXUnits
            for key in row.keys {
                let keyX = key.xUnits.map { row.startXUnits + $0 } ?? x
                actual.append((key.id, keyX, row.yUnits + key.yOffsetUnits,
                               key.widthUnits, key.heightUnits))
                x = keyX + key.widthUnits + layout.keySpacingUnits
            }
        }
        XCTAssertEqual(actual.count, expected.count)
        for (current, original) in zip(actual, expected) {
            XCTAssertEqual(current.0, original.0)
            XCTAssertEqual(current.1, original.1, accuracy: 1e-12, current.0)
            XCTAssertEqual(current.2, original.2, accuracy: 1e-12, current.0)
            XCTAssertEqual(current.3, original.3, accuracy: 1e-12, current.0)
            XCTAssertEqual(current.4, original.4, accuracy: 1e-12, current.0)
        }
    }
}
