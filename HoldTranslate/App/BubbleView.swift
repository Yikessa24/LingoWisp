import AppKit
import SwiftUI
import QuartzCore

struct BubbleView: View {
    @ObservedObject var model: TranslationModel
    @ObservedObject var preferences: Preferences
    let close: () -> Void
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
                    .help("关闭 · 气泡内双指右滑").accessibilityLabel("关闭翻译")
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
    var onScroll: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, onScroll?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor final class BubbleController {
    private let panel: TranslationPanel
    private let model: TranslationModel
    private let reduceMotion: () -> Bool
    private var anchor = CGRect.zero
    private var size = CGSize(width: 358, height: 160)
    private var closeGeneration = UUID()
    private var swipe = BubbleSwipeTracker()
    private(set) var isDismissing = false
    var onHide: (() -> Void)?
    var isVisible: Bool { panel.isVisible }
    var frame: CGRect { panel.frame }
    var canBecomeKey: Bool { panel.canBecomeKey }

    init(model: TranslationModel, preferences: Preferences,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.model = model; self.reduceMotion = reduceMotion
        panel = TranslationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("HoldTranslate 翻译")
        panel.contentView = NSHostingView(rootView: BubbleView(model: model, preferences: preferences,
            close: { [weak self] in self?.hide(dissolving: true) },
            sizeChanged: { [weak self] size in self?.resize(size) }))
        panel.contentView?.wantsLayer = true
        panel.onScroll = { [weak self] in self?.handleScroll($0) ?? false }
    }
    func show(anchor: CGRect) {
        closeGeneration = UUID(); isDismissing = false; swipe.reset()
        panel.ignoresMouseEvents = false
        panel.contentView?.layer?.mask = nil
        panel.contentView?.layer?.removeAllAnimations()
        self.anchor = anchor
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if !reduceMotion() {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.985; scale.toValue = 1.0; scale.duration = 0.13
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.contentView?.layer?.add(scale, forKey: "appear")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion() ? 0 : 0.13
            panel.animator().alphaValue = 1
        }
    }
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard isVisible, !isDismissing else { return false }
        let point = event.window === panel ? event.locationInWindow : panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let inside = panel.contentView?.bounds.contains(point) == true
        if swipe.process(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                         phase: event.phase, momentum: event.momentumPhase,
                         precise: event.hasPreciseScrollingDeltas,
                         inverted: event.isDirectionInvertedFromDevice, inside: inside) {
            hide(dissolving: true)
            return true
        }
        return false // Vertical gestures continue to the translation's ScrollView.
    }
    func hide(dissolving: Bool = false) {
        let token = UUID()
        if dissolving && isDismissing { return }
        closeGeneration = token; swipe.reset()
        guard panel.isVisible else { model.reset(); isDismissing = false; return }
        onHide?()
        guard dissolving else {
            panel.orderOut(nil); panel.contentView?.layer?.mask = nil
            panel.contentView?.layer?.removeAllAnimations()
            isDismissing = false; model.reset()
            return
        }
        isDismissing = true
        panel.ignoresMouseEvents = true
        model.cancelWork() // Keep the displayed text until the animation completes.
        let duration = reduceMotion() ? 0.12 : 0.28
        if !reduceMotion(), let layer = panel.contentView?.layer {
            let mask = CAGradientLayer()
            mask.frame = layer.bounds
            mask.startPoint = CGPoint(x: 0, y: 0.5); mask.endPoint = CGPoint(x: 1, y: 0.5)
            mask.locations = [0, 0.7, 1]
            let opaque = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1)]
            let dissolved = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 1)]
            mask.colors = dissolved
            let fade = CABasicAnimation(keyPath: "colors")
            fade.fromValue = opaque; fade.toValue = dissolved; fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.mask = mask; mask.add(fade, forKey: "dissolve")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !reduceMotion() { panel.animator().setFrameOrigin(CGPoint(x: panel.frame.minX + 64, y: panel.frame.minY)) }
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.closeGeneration == token else { return }
                self.panel.orderOut(nil)
                self.panel.contentView?.layer?.mask = nil
                self.isDismissing = false
                self.model.reset()
            }
        }
    }
    func reposition() {
        if panel.isVisible, !isDismissing { position() }
    }
    private func resize(_ size: CGSize) {
        guard abs(self.size.height - size.height) > 1 else { return }
        self.size = size
        if panel.isVisible, !isDismissing { position() }
    }
    private func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(BubblePlacement.frame(anchor: anchor, size: size, visibleFrame: screen.visibleFrame), display: true)
        panel.invalidateShadow()
    }
}
