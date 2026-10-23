import AppKit
import SwiftUI

 enum TriggerKey: String, CaseIterable, Identifiable {
    case option, control, optionCommand
    var id: String { rawValue }
    var title: String {
        switch self { case .option: "⌥ Option"; case .control: "⌃ Control"; case .optionCommand: "⌥⌘ Option + Command" }
    }
    var flags: NSEvent.ModifierFlags {
        switch self { case .option: .option; case .control: .control; case .optionCommand: [.option, .command] }
    }
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.option, .command, .control, .shift]) == self.flags
    }
}

@MainActor final class Preferences: ObservableObject {
    @Published var shortcut: KeyboardShortcut {
        didSet { if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: "selectionShortcut") } }
    }
    @Published var enabled: Bool { didSet { save(enabled, "enabled") } }
    @Published var trigger: TriggerKey { didSet { save(trigger.rawValue, "trigger") } }
    @Published var target: TargetChoice { didSet { save(target.rawValue, "target") } }
    @Published var allowClipboardFallback: Bool { didSet { save(allowClipboardFallback, "allowClipboardFallback") } }
    @Published var showOriginal: Bool { didSet { save(showOriginal, "showOriginal") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "selectionShortcut"),
           let stored = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), stored.isValid { shortcut = stored }
        else { shortcut = .selectionDefault }
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        trigger = TriggerKey(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .option
        target = TargetChoice(rawValue: defaults.string(forKey: "target") ?? "") ?? .automatic
        allowClipboardFallback = defaults.bool(forKey: "allowClipboardFallback")
        showOriginal = defaults.object(forKey: "showOriginal") as? Bool ?? true
    }
    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
