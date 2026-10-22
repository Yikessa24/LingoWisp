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

enum DismissMode: String, CaseIterable, Identifiable {
    case automatic, release, manual
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: "读完后自动收起"; case .release: "松开修饰键后收起"; case .manual: "点击外部或按 Esc 收起" }
    }
}

@MainActor final class Preferences: ObservableObject {
    @Published var enabled: Bool { didSet { save(enabled, "enabled") } }
    @Published var trigger: TriggerKey { didSet { save(trigger.rawValue, "trigger") } }
    @Published var target: TargetChoice { didSet { save(target.rawValue, "target") } }
    @Published var dismissMode: DismissMode { didSet { save(dismissMode.rawValue, "dismissMode") } }
    @Published var showOriginal: Bool { didSet { save(showOriginal, "showOriginal") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        trigger = TriggerKey(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .option
        target = TargetChoice(rawValue: defaults.string(forKey: "target") ?? "") ?? .automatic
        dismissMode = DismissMode(rawValue: defaults.string(forKey: "dismissMode") ?? "") ?? .automatic
        showOriginal = defaults.object(forKey: "showOriginal") as? Bool ?? true
    }
    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
