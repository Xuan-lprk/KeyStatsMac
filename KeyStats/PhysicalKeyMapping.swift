import Foundation

/// Counts key participation, not whole keyboard events. Generic modifiers remain
/// unresolved; renderers may apply their existing fallback without guessing here.
struct PhysicalKeyMappingResult: Equatable {
    let counts: [String: Int]
    let unsupported: [String: Int]
}

enum PhysicalKeyMapping {
    private static let supportedIDs = KeyboardLayout.macStyle.supportedKeyIDs

    static func map(_ keyPressCounts: [String: Int]) -> PhysicalKeyMappingResult {
        var counts: [String: Int] = [:]
        var unsupported: [String: Int] = [:]
        for (rawKey, count) in keyPressCounts where count > 0 {
            for component in components(of: rawKey) {
                guard let normalized = normalizedKeyboardHeatmapDisplayKey(component) else { continue }
                let key = normalized == "+" ? "=" : normalized
                if supportedIDs.contains(key) {
                    counts[key, default: 0] += count
                } else {
                    // Preserve the original component, including unknown/media names.
                    unsupported[component, default: 0] += count
                }
            }
        }
        return PhysicalKeyMappingResult(counts: counts, unsupported: unsupported)
    }

    private static func components(of rawKey: String) -> [String] {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "+" { return ["+"] }
        let trailingPlus = trimmed.hasSuffix("++")
        let prefix = trailingPlus ? String(trimmed.dropLast()) : trimmed
        var parts = prefix.split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if trailingPlus { parts.append("+") }
        return parts
    }
}

// Existing heatmap aliases are intentionally preserved; stored canonical names
// and Key Breakdown's whole-event naming are not changed by this mapping.
private func normalizedKeyboardHeatmapDisplayKey(_ rawKey: String) -> String? {
    let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let collapsed = trimmed
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "-", with: "")
        .uppercased()

    if collapsed.count == 1 {
        return collapsed
    }

    if collapsed.hasPrefix("F"), Int(collapsed.dropFirst()) != nil {
        return collapsed
    }

    switch collapsed {
    case "LEFTCMD", "LEFTCOMMAND":
        return "LeftCmd"
    case "RIGHTCMD", "RIGHTCOMMAND":
        return "RightCmd"
    case "CMD", "COMMAND", "⌘":
        return "Cmd"
    case "LEFTOPTION", "LEFTOPT", "LEFTALT":
        return "LeftOption"
    case "RIGHTOPTION", "RIGHTOPT", "RIGHTALT":
        return "RightOption"
    case "OPTION", "OPT", "ALT", "⌥":
        return "Option"
    case "LEFTSHIFT":
        return "LeftShift"
    case "RIGHTSHIFT":
        return "RightShift"
    case "SHIFT", "⇧":
        return "Shift"
    case "CTRL", "CONTROL", "⌃":
        return "Ctrl"
    case "FN", "FUNCTION", "🌐":
        return "Fn"
    case "SPACE", "SPACEBAR":
        return "Space"
    case "ESCAPE", "ESC", "⎋":
        return "Esc"
    case "RETURN", "↩":
        return "Return"
    case "ENTER", "⌅":
        return "Enter"
    case "BACKSPACE":
        return "Delete"
    case "DELETE", "⌫":
        return "Delete"
    case "FORWARDDELETE", "DEL", "⌦":
        return "ForwardDelete"
    case "INSERT", "INS", "HELP":
        return "Insert"
    case "PAGEUP":
        return "PageUp"
    case "PAGEDOWN":
        return "PageDown"
    case "HOME":
        return "Home"
    case "END":
        return "End"
    case "PRINTSCREEN", "PRTSC", "PRTSCN", "SNAPSHOT":
        return "PrintScreen"
    case "SCROLLLOCK", "SCROLL":
        return "ScrollLock"
    case "PAUSE", "BREAK":
        return "Pause"
    case "LEFT", "ARROWLEFT", "LEFTARROW":
        return "Left"
    case "RIGHT", "ARROWRIGHT", "RIGHTARROW":
        return "Right"
    case "UP", "ARROWUP", "UPARROW":
        return "Up"
    case "DOWN", "ARROWDOWN", "DOWNARROW":
        return "Down"
    case "CAPSLOCK", "CAPS":
        return "CapsLock"
    default:
        return trimmed
    }
}
