// Copyright © 2026 Mark Zaros. All Rights Reserved. License: GNU Public License 2.0 only.
import Foundation
import AppKit

struct Hotkey: Codable, Equatable {
    enum KeyCode {
        static let rightCommand: UInt16 = 54
        static let leftCommand: UInt16 = 55
        static let leftShift: UInt16 = 56
        static let capsLock: UInt16 = 57
        static let leftOption: UInt16 = 58
        static let leftControl: UInt16 = 59
        static let rightShift: UInt16 = 60
        static let rightOption: UInt16 = 61
        static let rightControl: UInt16 = 62
        static let function: UInt16 = 63

        static let modifierOnly: Set<UInt16> = [
            rightCommand,
            leftCommand,
            leftShift,
            capsLock,
            leftOption,
            leftControl,
            rightShift,
            rightOption,
            rightControl,
            function
        ]
    }

    var keyCode: UInt16
    var modifiers: CGEventFlags

    static let rightControl = Hotkey(keyCode: KeyCode.rightControl, modifiers: [.maskControl])

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let raw = try container.decode(UInt64.self, forKey: .modifiers)
        modifiers = CGEventFlags(rawValue: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }

    var isModifierOnly: Bool {
        KeyCode.modifierOnly.contains(keyCode)
    }

    func displayString() -> String {
        if isModifierOnly {
            return KeyCodeNames.modifierName(for: keyCode)
        }

        var parts: [String] = []
        if modifiers.contains(.maskControl) { parts.append("Control") }
        if modifiers.contains(.maskAlternate) { parts.append("Option") }
        if modifiers.contains(.maskShift) { parts.append("Shift") }
        if modifiers.contains(.maskCommand) { parts.append("Command") }

        parts.append(KeyCodeNames.name(for: keyCode))
        return parts.joined(separator: " + ")
    }
}

enum KeyCodeNames {
    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 10: return "Section"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Escape"
        case 64: return "F17"
        case 65: return "Decimal"
        case 67: return "*"
        case 69: return "+"
        case 71: return "Clear"
        case 72: return "Volume Up"
        case 73: return "Volume Down"
        case 74: return "Mute"
        case 75: return "/"
        case 76: return "Enter"
        case 78: return "-"
        case 79: return "F18"
        case 80: return "F19"
        case 81: return "="
        case 82: return "0"
        case 83: return "1"
        case 84: return "2"
        case 85: return "3"
        case 86: return "4"
        case 87: return "5"
        case 88: return "6"
        case 89: return "7"
        case 90: return "F20"
        case 91: return "8"
        case 92: return "9"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "Page Down"
        case 122: return "F1"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return "Key Code \(keyCode)"
        }
    }

    static func modifierName(for keyCode: UInt16) -> String {
        switch keyCode {
        case Hotkey.KeyCode.rightCommand: return "Right Command"
        case Hotkey.KeyCode.leftCommand: return "Left Command"
        case Hotkey.KeyCode.leftShift: return "Left Shift"
        case Hotkey.KeyCode.capsLock: return "Caps Lock"
        case Hotkey.KeyCode.leftOption: return "Left Option"
        case Hotkey.KeyCode.leftControl: return "Left Control"
        case Hotkey.KeyCode.rightShift: return "Right Shift"
        case Hotkey.KeyCode.rightOption: return "Right Option"
        case Hotkey.KeyCode.rightControl: return "Right Control"
        case Hotkey.KeyCode.function: return "Function"
        default: return name(for: keyCode)
        }
    }
}
