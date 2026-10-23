import XCTest
import AppKit
@testable import LingoWispCore

final class ThreeFingerDragTests: XCTestCase {
    func testLogicalMouseUpAfterReleasingOptionCompletesProvenDrag() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 100, y: 0), matches: true)
        XCTAssertTrue(gesture.modifierReleased(at: CGPoint(x: 100, y: 0), time: 1.4))
        XCTAssertTrue(gesture.up(at: CGPoint(x: 100, y: 0), time: 2.4, matches: false))
        XCTAssertFalse(gesture.up(at: CGPoint(x: 100, y: 0), time: 2.5, matches: false))
    }
    func testModifierReleaseAfterPlainClickDoesNotStartGrace() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        XCTAssertFalse(gesture.modifierReleased(at: CGPoint(x: 2, y: 0), time: 1.2))
        XCTAssertFalse(gesture.up(at: CGPoint(x: 20, y: 0), time: 1.4, matches: false))
    }
    func testDelayedReleaseGraceExpiresAndCannotBeExtendedByFlagsEvents() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 100, y: 0), matches: true)
        gesture.modifierReleased(at: CGPoint(x: 100, y: 0), time: 1.4)
        gesture.modifierReleased(at: CGPoint(x: 100, y: 0), time: 2.5)
        XCTAssertFalse(gesture.up(at: CGPoint(x: 100, y: 0), time: 3.1, matches: false))
    }
    func testMovingAgainWithoutOptionCancelsGrace() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 100, y: 0), matches: true)
        gesture.modifierReleased(at: CGPoint(x: 100, y: 0), time: 1.4)
        gesture.drag(to: CGPoint(x: 120, y: 0), matches: false)
        XCTAssertFalse(gesture.up(at: CGPoint(x: 120, y: 0), time: 1.8, matches: false))
    }
    func testFinalSyntheticDragAtUnchangedEndpointIsAllowed() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 100, y: 0), matches: true)
        gesture.modifierReleased(at: CGPoint(x: 100, y: 0), time: 1.4)
        gesture.drag(to: CGPoint(x: 101, y: 0), matches: false)
        XCTAssertTrue(gesture.up(at: CGPoint(x: 101, y: 0), time: 2.0, matches: false))
    }
    func testThreeFingerDragWithoutVisibleMouseDownCanComplete() {
        var gesture = GestureTracker()
        gesture.drag(to: CGPoint(x: 10, y: 0), time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 120, y: 0), time: 1.3, matches: true)
        gesture.modifierReleased(at: CGPoint(x: 120, y: 0), time: 1.4)
        XCTAssertTrue(gesture.up(at: CGPoint(x: 120, y: 0), time: 2.2, matches: false))
    }
    func testObservedPlainClickCannotBeUpgradedToThreeFingerDrag() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: false)
        gesture.drag(to: CGPoint(x: 10, y: 0), time: 1.2, matches: true)
        gesture.drag(to: CGPoint(x: 120, y: 0), time: 1.4, matches: true)
        XCTAssertFalse(gesture.up(at: CGPoint(x: 120, y: 0), time: 1.8, matches: true))
    }
    func testCancelledGestureCannotRestartUntilMouseUp() {
        var gesture = GestureTracker()
        gesture.down(at: .zero, time: 1, matches: true)
        gesture.drag(to: CGPoint(x: 100, y: 0), matches: true)
        gesture.cancel()
        gesture.drag(to: CGPoint(x: 120, y: 0), time: 1.5, matches: true)
        XCTAssertFalse(gesture.up(at: CGPoint(x: 180, y: 0), time: 1.8, matches: true))
    }
    @MainActor func testMonitorAcceptsThreeFingerSequenceAndKeepsDiagnosticAcrossOrdinaryClicks() async {
        let suite = "LingoWispThreeFinger-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var pointer = CGPoint(x: 100, y: 200)
        let monitor = InputMonitor(preferences: Preferences(defaults: defaults), mouseLocation: { pointer })
        var selected: [CGPoint] = []
        var statuses: [String] = []
        monitor.onSelection = { selected.append($0) }
        monitor.onGestureStatus = { statuses.append($0) }
        func mouse(_ type: NSEvent.EventType, x: CGFloat, time: TimeInterval, flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 200), modifierFlags: flags,
                               timestamp: time, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        monitor.process(mouse(.leftMouseDown, x: 100, time: 10, flags: .option))
        monitor.process(mouse(.leftMouseDragged, x: 250, time: 10.3, flags: .option))
        pointer = CGPoint(x: 250, y: 200)
        let released = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 10.4,
                                        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58)!
        monitor.process(released)
        monitor.process(mouse(.leftMouseUp, x: 250, time: 11.4, flags: []))
        XCTAssertEqual(selected, [CGPoint(x: 250, y: 200)])
        XCTAssertTrue(statuses.contains("awaitingDelayedMouseUp"))
        XCTAssertEqual(statuses.last, "dragAccepted")
        XCTAssertEqual(monitor.lastGestureTrace["releasedBeforeMouseUp"], 1)
        let recorded = monitor.lastGestureTrace
        monitor.process(mouse(.leftMouseDown, x: 20, time: 12, flags: []))
        monitor.process(mouse(.leftMouseUp, x: 20, time: 12.2, flags: []))
        XCTAssertEqual(monitor.lastGestureTrace, recorded)
        XCTAssertEqual(statuses.last, "dragAccepted")
    }
}
