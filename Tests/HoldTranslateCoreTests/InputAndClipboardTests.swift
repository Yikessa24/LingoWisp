import XCTest
import AppKit
@testable import HoldTranslateCore

final class InputPipelineTests: XCTestCase {
    @MainActor func testDelayedEventsUseTheirOwnCoordinatesInsteadOfCurrentCursor() async {
        let defaults = UserDefaults(suiteName: "HoldTranslateInputTests")!
        defer { defaults.removePersistentDomain(forName: "HoldTranslateInputTests") }
        let monitor = InputMonitor(preferences: Preferences(defaults: defaults))
        var selected: [CGPoint] = []
        monitor.onSelection = { selected.append($0) }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ time: TimeInterval) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 200), modifierFlags: .option,
                               timestamp: time, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        // Cursor is not moved by this test. Current mouseLocation is identical
        // across callbacks, reproducing asynchronously delivered real events.
        monitor.process(event(.leftMouseDown, 100, 10))
        monitor.process(event(.leftMouseDragged, 250, 10.2))
        monitor.process(event(.leftMouseUp, 260, 10.4))
        XCTAssertEqual(selected, [CGPoint(x: 260, y: 200)])
    }
    func testMissingIntermediateDragCallbackStillRecognizesHeldButtonMovement() {
        var gesture = GestureTracker()
        gesture.down(at: CGPoint(x: 10, y: 20), time: 1, matches: true)
        XCTAssertTrue(gesture.up(at: CGPoint(x: 110, y: 20), time: 1.4, matches: true))
        gesture.down(at: CGPoint(x: 10, y: 20), time: 2, matches: true)
        XCTAssertFalse(gesture.up(at: CGPoint(x: 12, y: 20), time: 2.4, matches: true))
    }
    func testDuplicateInstanceRejectedAndLockReleasedOnExit() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        var first: InstanceLock? = InstanceLock()
        XCTAssertTrue(first!.acquire(at: path))
        let second = InstanceLock()
        XCTAssertFalse(second.acquire(at: path))
        first = nil
        XCTAssertTrue(second.acquire(at: path))
    }
}

final class ClipboardCompatibilityTests: XCTestCase {
    @MainActor private func board() -> NSPasteboard { NSPasteboard(name: .init("HoldTranslateTests-" + UUID().uuidString)) }

    @MainActor func testPreservesEveryItemAndFormatAfterSuccessfulCopy() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("original clipboard", forType: .string)
        original.setData(Data([1, 2, 3, 4]), forType: .init("com.example.custom"))
        let second = NSPasteboardItem(); second.setString("second item", forType: .string)
        board.writeObjects([original, second])
        let reader = ClipboardSelectionReader(pasteboard: board, delays: [.milliseconds(1)], isCurrent: { _ in true }, sendCopy: { _ in
            board.clearContents(); board.setString("selected words", forType: .string)
        })
        let selection = try await reader.read(pid: 1)
        XCTAssertEqual(selection.text, "selected words")
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertEqual(board.pasteboardItems?[0].string(forType: .string), "original clipboard")
        XCTAssertEqual(board.pasteboardItems?[0].data(forType: .init("com.example.custom")), Data([1, 2, 3, 4]))
        XCTAssertEqual(board.pasteboardItems?[1].string(forType: .string), "second item")
    }
    @MainActor func testNoCopyDoesNotTranslateStaleClipboard() async {
        let board = board(); defer { board.releaseGlobally() }
        board.setString("unrelated text", forType: .string)
        let reader = ClipboardSelectionReader(pasteboard: board, delays: [.milliseconds(1)], isCurrent: { _ in true }, sendCopy: { _ in })
        do { _ = try await reader.read(pid: 1); XCTFail("Stale clipboard must not be used") } catch {}
        XCTAssertEqual(board.string(forType: .string), "unrelated text")
    }
    @MainActor func testConcurrentClipboardOwnerIsNeverOverwritten() async {
        let board = board(); defer { board.releaseGlobally() }
        board.setString("old clipboard", forType: .string)
        let reader = ClipboardSelectionReader(pasteboard: board, delays: [.milliseconds(1)], isCurrent: { _ in true }, sendCopy: { _ in
            board.clearContents(); board.setString("selection", forType: .string)
            board.clearContents(); board.setString("new user copy", forType: .string)
        })
        do { _ = try await reader.read(pid: 1); XCTFail("Concurrent change must abort") } catch {}
        XCTAssertEqual(board.string(forType: .string), "new user copy")
    }
    @MainActor func testUnsupportedPromiseIsNotCopiedOrCleared() async {
        let board = board(); defer { board.releaseGlobally() }
        board.setData(Data([1]), forType: .init("com.apple.pasteboard.promised-file-content"))
        let version = board.changeCount
        var sent = false
        let reader = ClipboardSelectionReader(pasteboard: board, delays: [.milliseconds(1)], isCurrent: { _ in true }, sendCopy: { _ in sent = true })
        do { _ = try await reader.read(pid: 1); XCTFail("Promise must abort") } catch {}
        XCTAssertFalse(sent); XCTAssertEqual(board.changeCount, version)
    }
    @MainActor func testCancellationStillFinishesClipboardRestoration() async {
        let board = board(); defer { board.releaseGlobally() }
        board.setString("keep this", forType: .string)
        let reader = ClipboardSelectionReader(pasteboard: board, delays: [.milliseconds(60)], isCurrent: { _ in true }, sendCopy: { _ in
            board.clearContents(); board.setString("temporary selection", forType: .string)
        })
        let request = Task { try await reader.read(pid: 1) }
        try? await Task.sleep(for: .milliseconds(10))
        request.cancel()
        do { _ = try await request.value; XCTFail("Cancelled request should not translate") } catch {}
        XCTAssertEqual(board.string(forType: .string), "keep this")
    }
}
