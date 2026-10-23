import AppKit
import QuartzCore

@MainActor final class BubbleBurstEffect {
    private let window: TranslationPanel
    private let view: BurstAnimationView
    init?(image: CGImage, frame: CGRect, completion: @escaping () -> Void) {
        let card = CGRect(x: BubbleBurstRenderer.margin, y: BubbleBurstRenderer.margin, width: frame.width, height: frame.height)
        guard let renderer = BubbleBurstRenderer(image: image, card: card) else { return nil }
        let expanded = frame.insetBy(dx: -BubbleBurstRenderer.margin, dy: -BubbleBurstRenderer.margin)
        window = TranslationPanel(contentRect: expanded, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.level = .popUpMenu; window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false; window.animationBehavior = .none
        view = BurstAnimationView(frame: CGRect(origin: .zero, size: expanded.size), renderer: renderer)
        window.contentView = view
        view.completion = { [weak self] in self?.cancel(); completion() }
    }
    func start() { view.start(); window.orderFrontRegardless() }
    func cancel() { view.stop(); window.orderOut(nil); window.close() }
    var isVisible: Bool { window.isVisible }
}

@MainActor private final class BurstAnimationView: NSView {
    private let renderer: BubbleBurstRenderer
    private var started: CFTimeInterval = 0
    private var link: CADisplayLink?
    var completion: (() -> Void)?
    override var isOpaque: Bool { false }
    init(frame: CGRect, renderer: BubbleBurstRenderer) {
        self.renderer = renderer
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func start() {
        started = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(tick))
        self.link = link
        link.add(to: .main, forMode: .common)
        needsDisplay = true
    }
    func stop() { link?.invalidate(); link = nil; completion = nil }
    @objc private func tick(_ link: CADisplayLink) {
        if CACurrentMediaTime() - started >= BubbleBurstRenderer.duration {
            let finished = completion
            stop(); finished?()
        } else { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        renderer.draw(in: context, time: CACurrentMediaTime() - started)
    }
}
