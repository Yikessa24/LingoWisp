import XCTest
import AppKit
@testable import LingoWispCore

final class SelectableTranslationTests: XCTestCase {
    private final class FlippedContainer: NSView { override var isFlipped: Bool { true } }
    @MainActor func testSelectedSubstringCopiesWithoutEditingTranslation() {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("LingoWispSelection-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let view = TranslationTextView(); view.copyPasteboard = board
        let text = "选择这一段 🌍，其余保留。"
        view.setTranslation(text)
        view.setSelectedRange((text as NSString).range(of: "这一段 🌍"))
        view.copy(nil)
        XCTAssertEqual(board.string(forType: .string), "这一段 🌍")
        XCTAssertEqual(view.string, text)
        XCTAssertTrue(view.isSelectable); XCTAssertFalse(view.isEditable)
    }
    @MainActor func testCommandCopyAndSelectAllUseCurrentSelection() {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("LingoWispSelection-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let view = TranslationTextView(); view.copyPasteboard = board
        view.setTranslation("First sentence. Second sentence.")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        func key(_ code: UInt16, _ character: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 1,
                            windowNumber: 0, context: nil, characters: character,
                            charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)!
        }
        XCTAssertTrue(view.performKeyEquivalent(with: key(8, "c")))
        XCTAssertEqual(board.string(forType: .string), "First")
        XCTAssertTrue(view.performKeyEquivalent(with: key(0, "a")))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: (view.string as NSString).length))
        view.copy(nil)
        XCTAssertEqual(board.string(forType: .string), view.string)
    }
    @MainActor func testEmptySelectionKeepsClipboardAndViewRefreshPreservesSelection() {
        _ = NSApplication.shared
        let board = NSPasteboard(name: .init("LingoWispSelection-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("existing copy", forType: .string)
        let view = TranslationTextView(); view.copyPasteboard = board
        view.setTranslation("A translation")
        view.copy(nil)
        XCTAssertEqual(board.string(forType: .string), "existing copy")
        view.setSelectedRange(NSRange(location: 2, length: 5))
        view.setTranslation("A translation")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 5))
        view.setTranslation("A new translation")
        XCTAssertEqual(view.selectedRange().length, 0)
    }
    @MainActor func testPanelOnlyAllowsKeyboardFocusAfterTextInteraction() {
        _ = NSApplication.shared
        let panel = TranslationPanel(contentRect: CGRect(x: 0, y: 0, width: 358, height: 180),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 358, height: 180))
        let text = TranslationTextView(); text.frame = CGRect(x: 18, y: 18, width: 322, height: 80)
        container.addSubview(text); panel.contentView = container
        XCTAssertFalse(panel.canBecomeKey)
        panel.prepareTextInteraction(at: CGPoint(x: 100, y: 150)) // header/background
        XCTAssertFalse(panel.canBecomeKey)
        panel.prepareTextInteraction(at: text.convert(CGPoint(x: text.bounds.midX, y: text.bounds.midY), to: nil))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        panel.resetTextInteraction()
        XCTAssertFalse(panel.canBecomeKey)
    }
    @MainActor func testShortAndLongTextMeasureWithoutClipping() {
        _ = NSApplication.shared
        let view = TranslationTextView()
        view.setTranslation("这是一个学习新事物的好日子。")
        let short = view.measuredSize(width: 322)
        view.setTranslation(Array(repeating: "这是一段比较长的译文，需要上下滚动阅读。", count: 30).joined(separator: "\n"))
        let long = view.measuredSize(width: 322)
        XCTAssertEqual(short.width, 322)
        XCTAssertLessThan(short.height, 70)
        XCTAssertGreaterThan(long.height, 270)
    }
    @MainActor func testFlippedHostingCoordinatesOnlyFocusTheClickedTranslation() {
        _ = NSApplication.shared
        let panel = TranslationPanel(contentRect: CGRect(x: 0, y: 0, width: 358, height: 180),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let container = FlippedContainer(frame: CGRect(x: 0, y: 0, width: 358, height: 180))
        let text = TranslationTextView(); text.frame = CGRect(x: 18, y: 70, width: 322, height: 80)
        container.addSubview(text); panel.contentView = container
        panel.prepareTextInteraction(at: CGPoint(x: 100, y: 150))
        XCTAssertFalse(panel.canBecomeKey)
        panel.prepareTextInteraction(at: text.convert(CGPoint(x: text.bounds.midX, y: text.bounds.midY), to: nil))
        XCTAssertTrue(panel.canBecomeKey)
    }
}
