import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: UInt
    let keyLabel: String
    static let selectionDefault = KeyboardShortcut(keyCode: 2, flags: .option, keyLabel: "D")
    static let supportedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifiers = flags.intersection(Self.supportedModifiers).rawValue
        self.keyLabel = keyLabel
    }
    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers).intersection(Self.supportedModifiers) }
    var isValid: Bool {
        keyCode < 128 && ![53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && !flags.intersection([.control, .option, .command]).isEmpty
            && !keyLabel.isEmpty && keyLabel.count <= 12
    }
    var display: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + keyLabel
    }
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.supportedModifiers) == flags
    }
    static func recorded(from event: NSEvent) -> Self? {
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let label = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        let shortcut = Self(keyCode: event.keyCode, flags: event.modifierFlags, keyLabel: label)
        return shortcut.isValid ? shortcut : nil
    }
}
