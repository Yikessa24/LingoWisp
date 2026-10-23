import AppKit
import SwiftUI

struct SelectableTranslationText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TranslationTextView { TranslationTextView() }
    func updateNSView(_ view: TranslationTextView, context: Context) { view.setTranslation(text) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TranslationTextView, context: Context) -> CGSize? {
        nsView.measuredSize(width: proposal.width ?? 322)
    }
}

/// A read-only native text view: selection, copy and Select All are intentional
/// interactions. It never asks for focus just because a translation appears.
@MainActor final class TranslationTextView: NSTextView {
    private let translationStorage: NSTextStorage
    var copyPasteboard: NSPasteboard = .general
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 322, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        translationStorage = storage
        super.init(frame: .zero, textContainer: container)
        isEditable = false; isSelectable = true; isRichText = false
        drawsBackground = false; textContainerInset = .zero
        isHorizontallyResizable = false; isVerticallyResizable = true
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        focusRingType = .none
        setAccessibilityLabel("译文")
        toolTip = "划选译文后按 ⌘C，或右键复制"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTranslation(_ text: String) {
        guard string != text else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
        textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ]))
        setSelectedRange(NSRange(location: 0, length: 0))
        invalidateIntrinsicContentSize()
    }
    func measuredSize(width: CGFloat) -> CGSize {
        let width = max(1, width)
        textContainer?.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if let textContainer { layoutManager?.ensureLayout(for: textContainer) }
        let height = textContainer.flatMap { layoutManager?.usedRect(for: $0).height } ?? 20
        return CGSize(width: width, height: max(20, ceil(height) + 2))
    }
    override func copy(_ sender: Any?) {
        let range = selectedRange(), value = string as NSString
        guard range.length > 0, range.location <= value.length, range.length <= value.length - range.location else { return }
        copyPasteboard.clearContents()
        copyPasteboard.setString(value.substring(with: range), forType: .string)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            if event.keyCode == 8 { copy(nil); return true }
            if event.keyCode == 0 { selectAll(nil); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(); menu.autoenablesItems = false
        let copy = NSMenuItem(title: "复制", action: #selector(copy(_:)), keyEquivalent: "c")
        copy.target = self; copy.isEnabled = selectedRange().length > 0
        let all = NSMenuItem(title: "全选", action: #selector(selectAll(_:)), keyEquivalent: "a")
        all.target = self; all.isEnabled = !string.isEmpty
        menu.addItem(copy); menu.addItem(all)
        return menu
    }
}
