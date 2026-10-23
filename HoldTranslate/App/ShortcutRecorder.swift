import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let commit: (KeyboardShortcut) -> Bool
    let recordingChanged: (Bool) -> Void
    let invalid: () -> Void
    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.bezelStyle = .rounded
        control.setButtonType(.momentaryPushIn)
        control.target = control; control.action = #selector(ShortcutRecorderControl.beginRecording)
        updateNSView(control, context: context)
        return control
    }
    func updateNSView(_ control: ShortcutRecorderControl, context: Context) {
        control.shortcut = shortcut; control.commit = commit; control.recordingChanged = recordingChanged; control.invalid = invalid
        control.refreshTitle()
    }
    static func dismantleNSView(_ control: ShortcutRecorderControl, coordinator: ()) {
        control.finishRecording()
        control.removeObservers()
    }
}

@MainActor final class ShortcutRecorderControl: NSButton {
    var shortcut = KeyboardShortcut.selectionDefault
    var commit: ((KeyboardShortcut) -> Bool)?
    var recordingChanged: ((Bool) -> Void)?
    var invalid: (() -> Void)?
    private var recording = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    override var acceptsFirstResponder: Bool { true }
    func refreshTitle() {
        title = recording ? "按下快捷键…" : shortcut.display
        setAccessibilityLabel(recording ? "正在录制快捷键，按 Esc 取消" : "修改翻译快捷键，当前为 \(shortcut.display)")
        toolTip = "点击录制快捷键；Esc 取消"
    }
    @objc func beginRecording() {
        guard !recording else { finishRecording(); return }
        window?.makeFirstResponder(self)
        recording = true; recordingChanged?(true); refreshTitle()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.recording, NSApp.keyWindow === self.window else { return false }
                if event.keyCode == 53 { self.finishRecording(); return true }
                guard !event.isARepeat else { return true }
                guard let candidate = KeyboardShortcut.recorded(from: event) else { self.invalid?(); return true }
                if self.commit?(candidate) == true { self.shortcut = candidate; self.finishRecording() }
                return true
            }
            return consumed ? nil : event
        }
    }
    func finishRecording() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; recordingChanged?(false); refreshTitle()
    }
    override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window else { finishRecording(); return }
        for (name, object) in [(NSWindow.willCloseNotification, window as AnyObject), (NSApplication.didResignActiveNotification, NSApp as AnyObject)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishRecording() }
            })
        }
    }
    func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
}
