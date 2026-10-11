import Foundation

/// The fixed Mac-style keyboard currently displayed by KeyStats.
/// Units describe structure only; renderers choose scale, colors and drawing.
struct KeyboardLayout: Equatable {
    let rows: [KeyboardRow]
    let keySpacingUnits: Double

    var keys: [KeyboardKey] { rows.flatMap(\.keys) }

    /// Includes generic modifier IDs used by existing renderer fallbacks.
    /// These are supported count identities, not additional visible keycaps.
    var supportedKeyIDs: Set<String> {
        Set(keys.flatMap { [$0.id] + $0.fallbackCountIDs })
    }

    static let macStyle: KeyboardLayout = {
        let keyGap = 0.15
        let rowStep = 1.0 + keyGap
        let deleteWidth = 2.38 - keyGap
        let backslashWidth = 1.93 - keyGap
        let rightShiftWidth = 2.93 + keyGap
        let numberRowWidths = Array(repeating: 1.0, count: 13) + [deleteWidth]
        let keyboardRightEdge = numberRowWidths.reduce(0, +) + Double(numberRowWidths.count - 1) * keyGap
        let escWidth = 1.45
        let functionGapTotal = keyGap + 11 * keyGap
        let functionKeyWidth = (keyboardRightEdge - escWidth - functionGapTotal) / 12

        func row(y: Double, keys: [(String, String, Double, String?, [String])]) -> KeyboardRow {
            KeyboardRow(yUnits: y, keys: keys.map {
                KeyboardKey(id: $0.0, label: $0.1, widthUnits: $0.2,
                            symbolName: $0.3, fallbackCountIDs: $0.4)
            })
        }

        let functionRow = KeyboardRow(yUnits: 0, keys:
            [KeyboardKey(id: "Esc", label: "esc", widthUnits: escWidth)]
            + (1...12).map {
                KeyboardKey(id: "F\($0)", label: "F\($0)", widthUnits: functionKeyWidth)
            })
        let y1 = rowStep
        let numberRow = row(y: y1, keys: [
            ("`", "~\n`", 1.0, nil, []), ("1", "!\n1", 1.0, nil, []), ("2", "@\n2", 1.0, nil, []), ("3", "#\n3", 1.0, nil, []), ("4", "$\n4", 1.0, nil, []),
            ("5", "%\n5", 1.0, nil, []), ("6", "^\n6", 1.0, nil, []), ("7", "&\n7", 1.0, nil, []), ("8", "*\n8", 1.0, nil, []), ("9", "(\n9", 1.0, nil, []),
            ("0", ")\n0", 1.0, nil, []), ("-", "_\n-", 1.0, nil, []), ("=", "+\n=", 1.0, nil, []), ("Delete", "delete", deleteWidth, nil, [])
        ])
        let y2 = y1 + rowStep
        let tabRow = row(y: y2, keys: [
            ("Tab", "tab", 1.45, nil, []), ("Q", "Q", 1.0, nil, []), ("W", "W", 1.0, nil, []), ("E", "E", 1.0, nil, []), ("R", "R", 1.0, nil, []),
            ("T", "T", 1.0, nil, []), ("Y", "Y", 1.0, nil, []), ("U", "U", 1.0, nil, []), ("I", "I", 1.0, nil, []), ("O", "O", 1.0, nil, []),
            ("P", "P", 1.0, nil, []), ("[", "{\n[", 1.0, nil, []), ("]", "}\n]", 1.0, nil, []), ("\\", "|\n\\", backslashWidth, nil, [])
        ])
        let y3 = y2 + rowStep
        let capsRow = row(y: y3, keys: [
            ("CapsLock", "caps lock", 1.8, nil, []), ("A", "A", 1.0, nil, []), ("S", "S", 1.0, nil, []), ("D", "D", 1.0, nil, []), ("F", "F", 1.0, nil, []),
            ("G", "G", 1.0, nil, []), ("H", "H", 1.0, nil, []), ("J", "J", 1.0, nil, []), ("K", "K", 1.0, nil, []), ("L", "L", 1.0, nil, []),
            (";", ":\n;", 1.0, nil, []), ("'", "\"\n'", 1.0, nil, []), ("Return", "return", 2.58, nil, [])
        ])
        let y4 = y3 + rowStep
        let shiftRow = row(y: y4, keys: [
            ("LeftShift", "", 2.45, "shift", ["Shift"]), ("Z", "Z", 1.0, nil, []), ("X", "X", 1.0, nil, []), ("C", "C", 1.0, nil, []), ("V", "V", 1.0, nil, []),
            ("B", "B", 1.0, nil, []), ("N", "N", 1.0, nil, []), ("M", "M", 1.0, nil, []), (",", "<\n,", 1.0, nil, []), (".", ">\n.", 1.0, nil, []),
            ("/", "?\n/", 1.0, nil, []), ("RightShift", "", rightShiftWidth, "shift", [])
        ])
        let y5 = y4 + rowStep
        let bottomKeys = [
            KeyboardKey(id: "Fn", label: "", symbolName: "globe"),
            KeyboardKey(id: "Ctrl", label: "", widthUnits: 1.1, symbolName: "control"),
            KeyboardKey(id: "LeftOption", label: "", widthUnits: 1.1,
                        symbolName: "option", fallbackCountIDs: ["Option"]),
            KeyboardKey(id: "LeftCmd", label: "", widthUnits: 1.3,
                        symbolName: "command", fallbackCountIDs: ["Cmd"]),
            KeyboardKey(id: "Space", label: "", widthUnits: 6.0),
            KeyboardKey(id: "RightCmd", label: "", widthUnits: 1.3, symbolName: "command"),
            KeyboardKey(id: "RightOption", label: "", widthUnits: 1.1, symbolName: "option")
        ]
        let arrowWidth = 1.0
        let arrowStep = arrowWidth + keyGap
        let arrowClusterWidth = arrowStep * 2 + arrowWidth
        let arrowStartX = keyboardRightEdge - arrowClusterWidth
        let verticalGap = 0.04
        let halfArrowHeight = (1.0 - verticalGap) / 2.0
        let arrows = [
            KeyboardKey(id: "Left", label: "◀", widthUnits: arrowWidth, xUnits: arrowStartX),
            KeyboardKey(id: "Up", label: "▲", widthUnits: arrowWidth,
                        heightUnits: halfArrowHeight, xUnits: arrowStartX + arrowStep),
            KeyboardKey(id: "Down", label: "▼", widthUnits: arrowWidth,
                        heightUnits: halfArrowHeight, xUnits: arrowStartX + arrowStep,
                        yOffsetUnits: halfArrowHeight + verticalGap),
            KeyboardKey(id: "Right", label: "▶", widthUnits: arrowWidth,
                        xUnits: arrowStartX + arrowStep * 2)
        ]
        return KeyboardLayout(
            rows: [functionRow, numberRow, tabRow, capsRow, shiftRow,
                   KeyboardRow(yUnits: y5, keys: bottomKeys + arrows)],
            keySpacingUnits: keyGap
        )
    }()
}

struct KeyboardRow: Equatable {
    let yUnits: Double
    let startXUnits: Double
    let keys: [KeyboardKey]

    init(yUnits: Double, startXUnits: Double = 0, keys: [KeyboardKey]) {
        self.yUnits = yUnits
        self.startXUnits = startXUnits
        self.keys = keys
    }
}

struct KeyboardKey: Equatable {
    let id: String
    let label: String
    let widthUnits: Double
    let heightUnits: Double
    let symbolName: String?
    let fallbackCountIDs: [String]
    /// A row-relative horizontal position for the independently aligned arrow cluster.
    /// Ordinary keys follow the row cursor and key spacing.
    let xUnits: Double?
    let yOffsetUnits: Double

    init(id: String, label: String, widthUnits: Double = 1, heightUnits: Double = 1,
         symbolName: String? = nil, fallbackCountIDs: [String] = [],
         xUnits: Double? = nil, yOffsetUnits: Double = 0) {
        self.id = id
        self.label = label
        self.widthUnits = widthUnits
        self.heightUnits = heightUnits
        self.symbolName = symbolName
        self.fallbackCountIDs = fallbackCountIDs
        self.xUnits = xUnits
        self.yOffsetUnits = yOffsetUnits
    }
}
