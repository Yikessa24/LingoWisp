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
            .help("拖动顶部移动气泡，支持三指拖移")

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
        SelectableTranslationText(text: text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class BubbleHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        let region = BubblePlacement.dragRegion(in: bounds)
        let cursorRect = isFlipped ? CGRect(x: region.minX, y: bounds.height - region.maxY, width: region.width, height: region.height) : region
        addCursorRect(cursorRect, cursor: .openHand)
    }
}

final class TranslationPanel: NSPanel {
    var onScroll: ((NSEvent) -> Bool)?
    var canStartDrag: ((NSEvent) -> Bool)?
    var onDrag: (() -> Void)?
    private var textInteraction = false
    override var canBecomeKey: Bool { textInteraction }
    override var canBecomeMain: Bool { false }
    @discardableResult func prepareTextInteraction(at point: CGPoint) -> TranslationTextView? {
        guard let contentView else { return nil }
        func translation(in view: NSView) -> TranslationTextView? {
            guard !view.isHidden, view.bounds.contains(view.convert(point, from: nil)) else { return nil }
            if let text = view as? TranslationTextView { return text }
            return view.subviews.reversed().compactMap { translation(in: $0) }.first
        }
        let text = translation(in: contentView)
        if text != nil { textInteraction = true }
        return text
    }
    func resetTextInteraction() {
        if isKeyWindow { resignKey() }
        textInteraction = false
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, canStartDrag?(event) == true {
            onDrag?()
            performDrag(with: event)
            return
        }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if let text = prepareTextInteraction(at: event.locationInWindow) {
                makeKey()
                makeFirstResponder(text)
            }
        }
        if event.type == .scrollWheel, onScroll?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor final class BubbleController: NSObject, NSWindowDelegate {
    private let panel: TranslationPanel
    private let model: TranslationModel
    private let reduceMotion: () -> Bool
    private var anchor = CGRect.zero
    private var size = CGSize(width: 358, height: 160)
    private var closeGeneration = UUID()
    private var swipe = BubbleSwipeTracker()
    private var burst: BubbleBurstEffect?
    private var manualTopLeft: CGPoint?
    private var positioning = false
    private(set) var isDismissing = false
    var onHide: (() -> Void)?
    var isVisible: Bool { panel.isVisible || burst?.isVisible == true }
    var frame: CGRect { panel.frame }
    var canBecomeKey: Bool { panel.canBecomeKey }

    init(model: TranslationModel, preferences: Preferences,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.model = model; self.reduceMotion = reduceMotion
        panel = TranslationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.isMovable = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.setAccessibilityLabel("HoldTranslate 翻译")
        panel.contentView = BubbleHostingView(rootView: BubbleView(model: model, preferences: preferences,
            close: { [weak self] in self?.hide(dissolving: true) },
            sizeChanged: { [weak self] size in self?.resize(size) }))
        panel.contentView?.wantsLayer = true
        panel.onScroll = { [weak self] in self?.handleScroll($0) ?? false }
        panel.canStartDrag = { [weak self] event in
            guard let self, !self.isDismissing, let bounds = self.panel.contentView?.bounds else { return false }
            return BubblePlacement.dragRegion(in: bounds).contains(event.locationInWindow)
        }
        panel.onDrag = { [weak self] in
            guard let self else { return }
            self.swipe.reset()
            self.manualTopLeft = CGPoint(x: self.panel.frame.minX, y: self.panel.frame.maxY)
        }
    }
    func show(anchor: CGRect) {
        closeGeneration = UUID(); isDismissing = false; swipe.reset()
        burst?.cancel(); burst = nil; manualTopLeft = nil
        panel.resetTextInteraction()
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
        if dissolving && isDismissing { return }
        let token = UUID(); closeGeneration = token; swipe.reset()
        burst?.cancel(); burst = nil
        guard panel.isVisible else { model.reset(); isDismissing = false; return }
        onHide?()
        panel.resetTextInteraction()
        guard dissolving else {
            panel.orderOut(nil); panel.contentView?.layer?.removeAllAnimations()
            isDismissing = false; model.reset()
            return
        }
        isDismissing = true; panel.ignoresMouseEvents = true
        model.cancelWork()
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.closeGeneration == token else { return }
            self.panel.orderOut(nil)
            self.burst = nil; self.isDismissing = false
            self.model.reset()
        }
        if !reduceMotion(), let view = panel.contentView {
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let image = bitmap.cgImage,
                   let effect = BubbleBurstEffect(image: image, frame: panel.frame, completion: finish) {
                    burst = effect
                    effect.start()
                    panel.orderOut(nil)
                    return
                }
            }
        }
        // Reduced motion (or a failed own-view snapshot) remains a short fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { Task { @MainActor in finish() } }
    }
    func reposition() {
        if panel.isVisible, !isDismissing { position() }
    }
    func windowDidMove(_ notification: Notification) {
        guard !positioning, !isDismissing, manualTopLeft != nil else { return }
        manualTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }
    private func resize(_ size: CGSize) {
        guard abs(self.size.height - size.height) > 1 else { return }
        self.size = size
        if panel.isVisible, !isDismissing { position() }
    }
    private func position() {
        let reference = manualTopLeft.map { CGPoint(x: $0.x + size.width / 2, y: $0.y - size.height / 2) }
            ?? CGPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(reference) } ?? NSScreen.main
        guard let screen else { return }
        positioning = true
        defer { positioning = false }
        let frame = manualTopLeft.map { BubblePlacement.manualFrame(topLeft: $0, size: size, visibleFrame: screen.visibleFrame) }
            ?? BubblePlacement.frame(anchor: anchor, size: size, visibleFrame: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        if manualTopLeft != nil { manualTopLeft = CGPoint(x: frame.minX, y: frame.maxY) }
        panel.invalidateShadow()
    }
}
