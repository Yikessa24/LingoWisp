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
        bubble = BubbleController(model: translation, preferences: preferences)
        monitor = InputMonitor(preferences: preferences)
        monitor.onSelection = { [weak self] in self?.translate(at: $0) }
        monitor.onOutsideClick = { [weak self] in self?.dismiss() }
        monitor.onTyping = { [weak self] in self?.dismiss() }
        monitor.onRelease = { [weak self] in self?.bubble.released() }
        monitor.onMove = { [weak self] in self?.bubble.moved(to: $0) }
        bubble.onHide = { [weak self] in
            self?.selectionTask?.cancel()
            self?.generation = UUID()
            self?.monitor.watchMovement(false)
        }
        translation.onFinished = { [weak self] in self?.bubble.finished() }
        translation.openPreparation = { [weak self] pair in
            self?.dismiss(); self?.settingsModel.preparationPair = pair; self?.showSettings()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "HoldTranslate")
        preferences.$enabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.dismiss(); self?.configureMonitoring(); self?.updateMenu() }
        }.store(in: &subscriptions)
        preferences.$trigger.dropFirst().sink { [weak self] _ in Task { @MainActor in self?.dismiss(); self?.configureMonitoring() } }.store(in: &subscriptions)
        updateMenu(); configureMonitoring()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.settingsModel.refresh(); self?.configureMonitoring() }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in self?.settingsModel.refresh(); self?.configureMonitoring() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }.store(in: &subscriptions)
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
    }
    private func configureMonitoring() {
        if preferences.enabled { monitor.start() } else { monitor.stop() }
    }
    private func updateMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: preferences.enabled ? "暂停划词翻译" : "恢复划词翻译", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; menu.addItem(toggle)
        let hint = NSMenuItem(title: "先选中，再按 ⇧⌘T", action: nil, keyEquivalent: "")
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
        dismiss()
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
    private func translate(at point: CGPoint) {
        guard preferences.enabled, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        dismiss()
        let token = UUID(); generation = token
        let pid = front.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        selectionTask = Task {
            // Let the source application finish updating its AX selection after mouse-up.
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled else { return }
            do {
                let selection = try await reader.read(pid: pid, point: axPoint)
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
                monitor.watchMovement(true)
            } catch {
                guard valid(token: token, pid: pid) else { return }
                if case SelectionError.secure = error { return }
                translation.message(error.localizedDescription)
                bubble.show(anchor: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
                bubble.finished()
                monitor.watchMovement(true)
            }
        }
    }
    private func valid(token: UUID, pid: pid_t) -> Bool {
        !Task.isCancelled && generation == token && preferences.enabled && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
    private func dismiss() {
        generation = UUID(); selectionTask?.cancel(); selectionTask = nil
        bubble?.hide(); monitor?.watchMovement(false)
    }
    func applicationWillTerminate(_ notification: Notification) {
        dismiss(); monitor.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
