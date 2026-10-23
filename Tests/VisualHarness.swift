// A standalone visual integration harness, intentionally outside the unit-test target.
// It uses the production panel and real Apple Translation session with fixed synthetic text.
import AppKit
import SwiftUI

@main struct VisualHarness: App {
    @NSApplicationDelegateAdaptor(VisualDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class VisualDelegate: NSObject, NSApplicationDelegate {
    private let model = TranslationModel()
    private var bubble: BubbleController!
    private var defaults: UserDefaults!
    private var started = Date()
    private let suite = "HoldTranslate.VisualTests"
    private var captured = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        bubble = BubbleController(model: model, preferences: preferences)
        model.onFinished = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self?.capture()
            }
        }
        let point = NSScreen.main?.visibleFrame.center ?? .zero
        bubble.show(anchor: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        if CommandLine.arguments.contains("--selection-only") {
            model.original = "This is a beautiful day to learn something new."
            model.state = .result("这是一个学习新事物的好日子。你可以选择这段译文的一部分，然后复制。")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                let board = NSPasteboard(name: .init("HoldTranslateSelectionVerification"))
                board.clearContents(); board.setString("selection-test-not-copied", forType: .string)
                @MainActor func redirectCopy(in view: NSView) {
                    if let text = view as? TranslationTextView { text.copyPasteboard = board }
                    for child in view.subviews { redirectCopy(in: child) }
                }
                for window in NSApp.windows where window is TranslationPanel {
                    if let view = window.contentView { redirectCopy(in: view) }
                }
            }
            return // Interactive selection fixture; no TranslationSession runs.
        }
        started = Date()
        var text = "This is a beautiful day to learn something new."
        if CommandLine.arguments.contains("--chinese") { text = "今天的天气很好，我们一起出去散步吧。" }
        if CommandLine.arguments.contains("--traditional") { text = "今天的天氣很好，我們一起出去散步吧。" }
        if CommandLine.arguments.contains("--word") { text = "hello" }
        if CommandLine.arguments.contains("--long") {
            text = Array(repeating: "Learning a new language opens a window onto another culture. Take your time, read carefully, and enjoy discovering something new every day.", count: 14).joined(separator: "\n\n")
        }
        model.begin(text: text, target: .automatic)
    }
    private func capture() {
        guard !captured else { return }; captured = true
        guard let index = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.indices.contains(index + 1) else { exit(2) }
        let path = CommandLine.arguments[index + 1]
        guard case .result(let result) = model.state, !result.isEmpty else {
            print("Visual translation did not produce a result: \(model.state == .needsDownload ? "needsDownload" : "error")")
            exit(1)
        }
        guard let view = NSApp.windows.first(where: { $0 is TranslationPanel })?.contentView else { exit(3) }
        view.layoutSubtreeIfNeeded()
        if !CommandLine.arguments.contains("--long") && view.bounds.height > 220 {
            print("Unexpected excess height for short translation: \(view.bounds.height)"); exit(6)
        }
        if view.bounds.height > 440 { print("Unbounded translation panel"); exit(7) }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(4) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            print("Real translation captured; seconds=\(String(format: "%.2f", Date().timeIntervalSince(started))), frame=\(view.bounds.size), resultCharacters=\(result.count), source=\(model.pair?.source ?? ""), target=\(model.pair?.target ?? "")")
        } catch { exit(5) }
        defaults.removePersistentDomain(forName: suite)
        NSApp.terminate(nil)
    }
}
private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
