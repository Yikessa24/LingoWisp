import AppKit
import SwiftUI
import QuartzCore

struct BubbleView: View {
    @ObservedObject var model: TranslationModel
    @ObservedObject var preferences: Preferences
    let close: () -> Void
    let hover: (Bool) -> Void
    let sizeChanged: (CGSize) -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 6) {
                Image(systemName: "character.bubble").font(.system(size: 12, weight: .medium))
                Text(model.pair?.label ?? "HoldTranslate").font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                if case let .result(result) = model.state {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        copied = true
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .help("复制译文").accessibilityLabel(copied ? "已复制" : "复制译文")
                }
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .help("关闭 · Esc").accessibilityLabel("关闭翻译")
            }
            .foregroundStyle(.secondary).buttonStyle(.borderless)

            if preferences.showOriginal && !model.original.isEmpty {
                Text(model.original).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Divider().opacity(0.65)
            }
            switch model.state {
            case .loading:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("正在翻译…").font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            case .result(let result):
                if resultHeight(result) <= 270 {
                    resultText(result).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView { resultText(result).fixedSize(horizontal: false, vertical: true) }
                        .frame(height: 270)
                }
            case .message(let message):
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .selectionUnavailable:
                Text("此应用未公开可访问的选中文字。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button("复制选区并翻译") { model.copySelection?() }.buttonStyle(.bordered)
                Text("仅此次临时复制，随后恢复原剪贴板。也可在设置中启用自动兼容。")
                    .font(.caption).foregroundStyle(.tertiary)
            case .needsDownload:
                Text("首次翻译需要下载语言包。下载后可在设备端使用。")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Button("准备语言包…") {
                    if let pair = model.pair { model.openPreparation?(pair) }
                }.buttonStyle(.bordered)
            }
        }
        .padding(18).frame(width: 358)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.primary.opacity(0.09), lineWidth: 0.5))
        .background(GeometryReader { geometry in
            Color.clear.onAppear { sizeChanged(geometry.size) }
                .onChange(of: geometry.size) { _, size in sizeChanged(size) }
        })
        .onHover(perform: hover)
        .onChange(of: model.request?.id) { _, _ in copied = false }
        .overlay(alignment: .topLeading) {
            if let request = model.request { TranslationWorker(request: request, model: model).id(request.id) }
        }
    }
    private func resultHeight(_ text: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: 322, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
        ).height) + 2
    }
    private func resultText(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("译文：\(text)")
    }
}

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class BubbleController {
    private let panel: TranslationPanel
    private let model: TranslationModel
    private let preferences: Preferences
    private var anchor = CGRect.zero
    private var size = CGSize(width: 358, height: 160)
    private var dismissal: Task<Void, Never>?
    private var closeGeneration = UUID()
    private var closeDeadline: Date?
    private var shownAt = Date.distantPast
    private(set) var hovering = false
    var onHide: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var canBecomeKey: Bool { panel.canBecomeKey }

    init(model: TranslationModel, preferences: Preferences) {
        self.model = model; self.preferences = preferences
        panel = TranslationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("HoldTranslate 翻译")
        panel.contentView = NSHostingView(rootView: BubbleView(model: model, preferences: preferences, close: { [weak self] in self?.hide() }, hover: { [weak self] in self?.setHover($0) }, sizeChanged: { [weak self] size in self?.resize(size) }))
        panel.contentView?.wantsLayer = true
    }
    func show(anchor: CGRect) {
        dismissal?.cancel(); dismissal = nil; closeDeadline = nil; closeGeneration = UUID()
        hovering = false; self.anchor = anchor; shownAt = Date()
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.985; scale.toValue = 1.0; scale.duration = 0.13
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.contentView?.layer?.add(scale, forKey: "appear")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.13
            panel.animator().alphaValue = 1
        }
    }
    func finished() {
        shownAt = Date()
        guard preferences.dismissMode == .automatic else { return }
        let seconds: Double
        if case .result(let text) = model.state { seconds = min(45, max(12, Double(text.count) / 12)) }
        else { seconds = 12 }
        scheduleClose(after: seconds)
    }
    func released() {
        guard preferences.dismissMode == .release else { return }
        // Allow the pointer to enter the bubble, even if a key is released immediately.
        scheduleClose(after: 1.2)
    }
    func moved(to point: CGPoint) {
        guard isVisible, !hovering, preferences.dismissMode == .automatic,
              model.state != .loading, Date().timeIntervalSince(shownAt) > 3 else { return }
        if !panel.frame.insetBy(dx: -140, dy: -100).contains(point) { scheduleClose(after: 0.8) }
    }
    private func setHover(_ value: Bool) {
        hovering = value
        if value { dismissal?.cancel(); dismissal = nil; closeDeadline = nil }
        else if preferences.dismissMode != .manual { scheduleClose(after: preferences.dismissMode == .release ? 1.2 : 4) }
    }
    private func scheduleClose(after seconds: Double) {
        guard isVisible, !hovering else { return }
        let deadline = Date().addingTimeInterval(seconds)
        // Keep the earlier deadline. Mouse movement must not postpone dismissal,
        // and moving away should be able to shorten the ordinary reading timer.
        if let closeDeadline, closeDeadline <= deadline { return }
        dismissal?.cancel()
        closeDeadline = deadline
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.dismissal = nil; self.closeDeadline = nil
            if !self.hovering { self.hide() }
        }
    }
    func hide() {
        dismissal?.cancel(); dismissal = nil; closeDeadline = nil
        guard panel.isVisible else { model.reset(); return }
        let token = UUID(); closeGeneration = token
        onHide?()
        model.reset()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.closeGeneration == token else { return }
                self.panel.orderOut(nil)
            }
        }
    }
    private func resize(_ size: CGSize) {
        guard abs(self.size.height - size.height) > 1 else { return }
        self.size = size
        if panel.isVisible { position() }
    }
    private func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(BubblePlacement.frame(anchor: anchor, size: size, visibleFrame: screen.visibleFrame), display: true)
        panel.invalidateShadow()
    }
}
