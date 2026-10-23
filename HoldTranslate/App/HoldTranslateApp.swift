import SwiftUI
import AppKit
import Combine
import ApplicationServices

@main struct HoldTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let settingsModel = SettingsModel()
    private let translation = TranslationModel()
    private let reader = SelectionReader()
    private let clipboardReader = ClipboardSelectionReader()
    private let instanceLock = InstanceLock()
    private let globalShortcut = GlobalShortcut()
    private var monitor: InputMonitor!
    private var bubble: BubbleController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var selectionTask: Task<Void, Never>?
    private var generation = UUID()
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent("com.yikessa.HoldTranslate.instance.lock")
        guard instanceLock.acquire(at: lockURL) else { NSApp.terminate(nil); return }
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        bubble = BubbleController(model: translation, preferences: preferences)
        monitor = InputMonitor(preferences: preferences)
        if CommandLine.arguments.contains("--input-report") {
            monitor.onGestureStatus = { [weak self] in self?.writeInputStatus($0) }
        }
        monitor.onSelection = { [weak self] in self?.translate(at: $0) }
        bubble.onHide = { [weak self] in
            self?.selectionTask?.cancel()
            self?.generation = UUID()
        }
        translation.onFinished = { [weak self] in
            self?.recordDiagnosticResult()
            if case .result = self?.translation.state { self?.writeInputStatus("translationSucceeded") }
        }
        translation.openPreparation = { [weak self] pair in
            self?.dismiss(); self?.settingsModel.preparationPair = pair; self?.showSettings()
        }
        globalShortcut.onPressed = { [weak self] in
            guard let self, self.preferences.enabled, !self.settingsModel.recordingShortcut else { return }
            self.writeInputStatus("selectionShortcut")
            self.translate(at: NSEvent.mouseLocation)
        }
        settingsModel.applyShortcut = { [weak self] shortcut in self?.applyShortcut(shortcut) ?? false }
        settingsModel.recordingChanged = { [weak self] recording in
            if recording { self?.globalShortcut.stop() }
            else { self?.configureShortcut() }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "HoldTranslate")
        preferences.$enabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.dismiss(); self?.configureMonitoring(); self?.updateMenu() }
        }.store(in: &subscriptions)
        preferences.$trigger.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.configureMonitoring() } }.store(in: &subscriptions)
        updateMenu(); configureMonitoring()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.settingsModel.refresh(); self?.configureMonitoring() }
            })
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in self?.settingsModel.refresh(); self?.configureMonitoring() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            Task { @MainActor in self?.bubble.reposition() }
        }.store(in: &subscriptions)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || CommandLine.arguments.contains("--settings") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                diagnosticFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                translation.begin(text: "This is a beautiful day to learn something new.", target: .automatic)
                let screen = NSScreen.main?.visibleFrame ?? .zero
                bubble.show(anchor: CGRect(x: screen.midX, y: screen.midY, width: 1, height: 1))
                writeDiagnostic(status: "started")
            }
        }
    }
    private func writeInputStatus(_ stage: String) {
        guard let flag = CommandLine.arguments.firstIndex(of: "--input-report"),
              CommandLine.arguments.indices.contains(flag + 1) else { return }
        // Opt-in troubleshooting only: one status record, no text, key contents,
        // app identifiers or absolute mouse positions.
        let report: [String: Any] = ["stage": stage, "accessibilityTrusted": AXIsProcessTrusted(),
                                    "trigger": preferences.trigger.rawValue, "enabled": preferences.enabled,
                                    "gesture": monitor?.lastGestureTrace ?? [:]]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
        }
    }
    private var diagnosticFrontmost: String?
    private var diagnosticFinished = false
    private func recordDiagnosticResult() {
        guard CommandLine.arguments.contains("--smoke-test"), !diagnosticFinished else { return }
        diagnosticFinished = true
        switch translation.state {
        case .loading: break
        case .result(let text): writeDiagnostic(status: text.isEmpty ? "emptyResult" : "translated")
        case .needsDownload: writeDiagnostic(status: "needsDownload")
        case .message, .selectionUnavailable: writeDiagnostic(status: "error")
        }
    }
    private func writeDiagnostic(status: String) {
        // Explicit developer smoke test only. Never writes selected or translated text.
        guard let flag = CommandLine.arguments.firstIndex(of: "--diagnostic-report"),
              CommandLine.arguments.indices.contains(flag + 1) else { return }
        let report: [String: Any] = [
            "status": status,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "frontmostUnchanged": diagnosticFrontmost == NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            "panelCanBecomeKey": bubble.canBecomeKey,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]), options: .atomic)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    private func configureMonitoring() {
        if preferences.enabled { monitor.start() } else { monitor.stop() }
        configureShortcut()
    }
    private func configureShortcut() {
        guard preferences.enabled, !settingsModel.recordingShortcut else { globalShortcut.stop(); return }
        do { try globalShortcut.register(preferences.shortcut); settingsModel.shortcutError = nil }
        catch { settingsModel.shortcutError = error.localizedDescription }
    }
    private func applyShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        do {
            try globalShortcut.register(shortcut)
            preferences.shortcut = shortcut
            settingsModel.shortcutError = nil
            if !preferences.enabled || settingsModel.recordingShortcut { globalShortcut.stop() }
            updateMenu()
            return true
        } catch { settingsModel.shortcutError = error.localizedDescription; return false }
    }
    private func updateMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: preferences.enabled ? "暂停划词翻译" : "恢复划词翻译", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        let hint = NSMenuItem(title: "先选中，再按 \(preferences.shortcut.display)", action: nil, keyEquivalent: "")
        menu.addItem(hint); menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 HoldTranslate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.appearsDisabled = !preferences.enabled
        statusItem.button?.toolTip = preferences.enabled ? "HoldTranslate · 按住修饰键划选" : "HoldTranslate · 已暂停"
    }
    @objc private func toggleEnabled() { preferences.enabled.toggle() }
    @objc func showSettings() {
        settingsModel.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 650), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "HoldTranslate 设置"
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, model: settingsModel))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func translate(at point: CGPoint, usingClipboard: Bool = false, expectedPID: pid_t? = nil) {
        guard preferences.enabled, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let expectedPID, expectedPID != front.processIdentifier { return }
        dismiss()
        let token = UUID(); generation = token
        let pid = front.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        selectionTask = Task { [self] in
            // Let the source application finish updating its AX selection after mouse-up.
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled else { return }
            do {
                writeInputStatus(usingClipboard ? "copySafetyCheck" : "accessibilityRead")
                let selection: Selection
                if usingClipboard {
                    try await reader.validateForCopy(pid: pid, point: axPoint)
                    guard valid(token: token, pid: pid) else { return }
                    selection = try await clipboardReader.read(pid: pid)
                } else {
                    do { selection = try await reader.read(pid: pid, point: axPoint) }
                    catch SelectionError.unavailable where preferences.allowClipboardFallback {
                        try await reader.validateForCopy(pid: pid, point: axPoint)
                        guard valid(token: token, pid: pid) else { return }
                        selection = try await clipboardReader.read(pid: pid)
                    }
                }
                guard valid(token: token, pid: pid) else { return }
                let text = try LanguagePolicy.cleaned(selection.text)
                var anchor = CGRect(origin: point, size: CGSize(width: 1, height: 1))
                if let bounds = selection.axBounds {
                    let converted = BubblePlacement.appKitRect(fromAX: bounds, primaryHeight: primaryHeight)
                    // Huge multi-line selections or stale AX rectangles should not displace the bubble far from the pointer.
                    if converted.width < 1800 && converted.height < 300 && converted.insetBy(dx: -80, dy: -80).contains(point) { anchor = converted }
                }
                translation.begin(text: text, target: preferences.target)
                bubble.show(anchor: anchor)
            } catch {
                guard valid(token: token, pid: pid) else { return }
                if case SelectionError.secure = error { writeInputStatus("secureInputSkipped"); return }
                writeInputStatus("selectionReadFailed")
                if case SelectionError.unavailable = error, !usingClipboard {
                    translation.unavailable { [weak self] in self?.translate(at: point, usingClipboard: true, expectedPID: pid) }
                } else { translation.message(error.localizedDescription) }
                bubble.show(anchor: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
            }
        }
    }
    private func valid(token: UUID, pid: pid_t) -> Bool {
        !Task.isCancelled && generation == token && preferences.enabled && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    private func dismiss() {
        generation = UUID(); selectionTask?.cancel(); selectionTask = nil
        bubble?.hide()
    }
    func applicationWillTerminate(_ notification: Notification) {
        dismiss(); monitor?.stop(); globalShortcut.shutdown()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
