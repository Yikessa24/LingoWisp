import SwiftUI
@preconcurrency import ApplicationServices
import ServiceManagement
@preconcurrency import Translation

@MainActor final class SettingsModel: ObservableObject {
    @Published var shortcutError: String?
    @Published var recordingShortcut = false
    var applyShortcut: ((KeyboardShortcut) -> Bool)?
    var recordingChanged: ((Bool) -> Void)?
    func setRecording(_ value: Bool) { recordingShortcut = value; recordingChanged?(value) }
    @Published var trusted = AXIsProcessTrusted()
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginMessage: String?
    @Published var preparationPair = LanguagePair(source: "en", target: "zh-Hans")
    @Published var preparationID = UUID()
    @Published var preparing = false
    @Published var preparationMessage = "语言包由 macOS 管理，首次下载需要网络和你的确认。"
    func refresh() {
        trusted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许译泡（LingoWisp）。" : nil
        } catch { loginMessage = "无法更改登录项。请将应用放在固定位置后重试，或在系统设置中管理。" }
        refresh()
    }
    func prepare(_ pair: LanguagePair) {
        preparationPair = pair; preparationID = UUID(); preparing = true
        preparationMessage = "正在检查语言包，请完成系统下载确认…"
    }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "character.bubble.fill").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("译泡 · LingoWisp").font(.system(size: 23, weight: .semibold))
                    Text("选中文字，译文就在旁边。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Form {
                Section {
                    Toggle("启用划词翻译", isOn: $preferences.enabled)
                    Picker("划选时按住", selection: $preferences.trigger) { ForEach(TriggerKey.allCases) { Text($0.title).tag($0) } }
                    HStack {
                        Text("选中后翻译")
                        Spacer()
                        ShortcutRecorder(shortcut: preferences.shortcut,
                                         commit: { model.applyShortcut?($0) ?? false },
                                         recordingChanged: { model.setRecording($0) },
                                         invalid: { model.shortcutError = ShortcutError.invalid.localizedDescription })
                            .frame(width: 140, height: 26)
                        Button("恢复默认") { _ = model.applyShortcut?(.selectionDefault) }
                            .disabled(model.recordingShortcut)
                    }
                    if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                    if model.recordingShortcut { Text("按下新的组合键；Esc 取消。至少包含 Option、Control 或 Command。").font(.caption).foregroundStyle(.secondary) }
                    Text("若 Option 改变了应用的选区行为，请换用其他修饰键，或先选中文字，再按 \(preferences.shortcut.display)。点击上方快捷键可自行修改。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("翻译为", selection: $preferences.target) { ForEach(TargetChoice.allCases) { Text($0.title).tag($0) } }
                } header: { Text("翻译") }
                Section {
                    Text("译文气泡保持显示，拖动顶部可移动（支持三指拖移）。点击 ×，或在气泡内双指右滑，气泡会从右侧碎成圆形粒子并向右飘散。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("显示原文摘要", isOn: $preferences.showOriginal)
                    Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    if let message = model.loginMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                } header: { Text("行为") }
                Section {
                    HStack {
                        Label(model.trusted ? "辅助功能已授权" : "需要辅助功能权限", systemImage: model.trusted ? "checkmark.circle.fill" : "hand.raised")
                            .foregroundStyle(model.trusted ? Color.green : Color.primary)
                        Spacer()
                        Button(model.trusted ? "重新检查" : "前往授权") {
                            if model.trusted { model.refresh() } else { model.requestPermission() }
                        }
                    }
                    Toggle("选区不可访问时使用复制兼容模式", isOn: $preferences.allowClipboardFallback)
                    Text("兼容模式会临时执行复制并恢复原剪贴板；若剪贴板同时被其他操作修改，则保留新内容。特殊格式或过大的剪贴板会跳过。默认关闭。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("仅在你触发翻译时读取选区，跳过安全输入框。不记录按键或翻译历史，不使用屏幕录制。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("权限与隐私") }
                Section {
                    HStack {
                        Text(model.preparationPair.label)
                        Spacer()
                        Button(model.preparing ? "准备中…" : "准备语言包") { model.prepare(model.preparationPair) }.disabled(model.preparing)
                    }
                    Text(model.preparationMessage).font(.caption).foregroundStyle(.secondary)
                } header: { Text("设备端翻译") }
            }.formStyle(.grouped)
            HStack {
                Text("macOS 原生 · 无账号 · 无历史记录").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.caption2).foregroundStyle(.tertiary)
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 510, height: 650)
        .background(.background)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .overlay {
            if model.preparing { PreparationWorker(model: model, pair: model.preparationPair, id: model.preparationID).id(model.preparationID) }
        }
    }
}

struct PreparationWorker: View {
    @ObservedObject var model: SettingsModel
    let pair: LanguagePair
    let id: UUID
    private var configuration: TranslationSession.Configuration {
        let source = Locale.Language(identifier: pair.source)
        let target = Locale.Language(identifier: pair.target)
        if #available(macOS 26.4, *) { return .init(source: source, target: target, preferredStrategy: .lowLatency) }
        return .init(source: source, target: target)
    }
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    let status = await TranslationModel.languageStatus(pair)
                    guard model.preparationID == id else { return }
                    model.preparationMessage = status == .installed ? "语言包已就绪。回到原应用划选即可翻译。" : "下载已请求。请等待系统完成下载后重试划词。"
                } catch {
                    guard model.preparationID == id else { return }
                    model.preparationMessage = "语言包尚未准备完成。请检查网络并重试，也可在系统设置 → 语言与地区中管理翻译语言。"
                }
                model.preparing = false
            }
    }
}
