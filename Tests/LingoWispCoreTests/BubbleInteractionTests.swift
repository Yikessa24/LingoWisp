import XCTest
import AppKit
@testable import LingoWispCore

final class BubbleSwipeTests: XCTestCase {
    private func feed(_ tracker: inout BubbleSwipeTracker, x: CGFloat, y: CGFloat = 0,
                      phase: NSEvent.Phase = .changed, momentum: NSEvent.Phase = [],
                      precise: Bool = true, inverted: Bool = true, inside: Bool = true) -> Bool {
        tracker.process(deltaX: x, deltaY: y, phase: phase, momentum: momentum,
                        precise: precise, inverted: inverted, inside: inside)
    }
    func testRightSwipeWorksWithBothNaturalScrollingSettings() {
        for natural in [false, true] {
            var tracker = BubbleSwipeTracker()
            let direction: CGFloat = natural ? 1 : -1
            XCTAssertFalse(feed(&tracker, x: 20 * direction, phase: .began, inverted: natural))
            XCTAssertTrue(feed(&tracker, x: 50 * direction, inverted: natural))
            XCTAssertFalse(feed(&tracker, x: 100 * direction, inverted: natural))
        }
    }
    func testVerticalReadingLocksOutDismissalUntilFingersLift() {
        var tracker = BubbleSwipeTracker()
        XCTAssertFalse(feed(&tracker, x: 1, y: 20, phase: .began))
        XCTAssertFalse(feed(&tracker, x: 100))
        XCTAssertFalse(feed(&tracker, x: 0, phase: .ended))
        XCTAssertTrue(feed(&tracker, x: 80, phase: .began))
    }
    func testLeftSwipeAndDiagonalScrollNeverDismiss() {
        var tracker = BubbleSwipeTracker()
        XCTAssertFalse(feed(&tracker, x: -80, phase: .began))
        XCTAssertFalse(feed(&tracker, x: 160))
        XCTAssertFalse(feed(&tracker, x: 80, y: 65, phase: .began))
    }
    func testMomentumAndMouseWheelCannotDismiss() {
        var tracker = BubbleSwipeTracker()
        XCTAssertFalse(feed(&tracker, x: 10, phase: .began))
        XCTAssertFalse(feed(&tracker, x: 100, momentum: .began))
        XCTAssertFalse(feed(&tracker, x: 100, phase: .began, precise: false))
        XCTAssertFalse(feed(&tracker, x: 100, phase: []))
    }
    func testGestureMustBeginInsideAndCannotResumeAfterLeaving() {
        var tracker = BubbleSwipeTracker()
        XCTAssertFalse(feed(&tracker, x: 10, phase: .began, inside: false))
        XCTAssertFalse(feed(&tracker, x: 100))
        XCTAssertFalse(feed(&tracker, x: 20, phase: .began))
        XCTAssertFalse(feed(&tracker, x: 10, inside: false))
        XCTAssertFalse(feed(&tracker, x: 100))
    }
    func testCancellationAndSmallMovementCannotDismiss() {
        var tracker = BubbleSwipeTracker()
        XCTAssertFalse(feed(&tracker, x: 20, phase: .began))
        XCTAssertFalse(feed(&tracker, x: 20))
        XCTAssertFalse(feed(&tracker, x: 0, phase: .cancelled))
        XCTAssertFalse(feed(&tracker, x: 100))
        XCTAssertTrue(feed(&tracker, x: 80, phase: .began))
    }
}

final class BubbleLifetimeTests: XCTestCase {
    @MainActor private func makeBubble(reduceMotion: Bool = false) -> (BubbleController, TranslationModel, UserDefaults, String) {
        _ = NSApplication.shared
        let suite = "LingoWispBubbleTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        // Old automatic/release settings must not revive automatic dismissal.
        defaults.set("release", forKey: "dismissMode")
        let model = TranslationModel()
        let bubble = BubbleController(model: model, preferences: Preferences(defaults: defaults), reduceMotion: { reduceMotion })
        model.state = .result("A visible translation")
        bubble.show(anchor: CGRect(x: 300, y: 300, width: 1, height: 1))
        return (bubble, model, defaults, suite)
    }
    @MainActor func testDissolveKeepsTextUntilAnimationEndsThenClearsIt() async {
        let (bubble, model, defaults, suite) = makeBubble()
        defer { bubble.hide(); defaults.removePersistentDomain(forName: suite) }
        var closed = 0
        bubble.onHide = { closed += 1 }
        bubble.hide(dissolving: true)
        bubble.hide(dissolving: true)
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(bubble.isDismissing)
        XCTAssertEqual(model.state, .result("A visible translation"))
        try? await Task.sleep(for: .milliseconds(1550))
        XCTAssertFalse(bubble.isVisible)
        XCTAssertFalse(bubble.isDismissing)
        XCTAssertEqual(model.state, .loading)
    }
    @MainActor func testNewTranslationDuringDissolveIsNotClosedByOldCompletion() async {
        let (bubble, model, defaults, suite) = makeBubble()
        defer { bubble.hide(); defaults.removePersistentDomain(forName: suite) }
        bubble.hide(dissolving: true)
        model.state = .result("New result")
        bubble.show(anchor: CGRect(x: 400, y: 400, width: 1, height: 1))
        try? await Task.sleep(for: .milliseconds(1550))
        XCTAssertTrue(bubble.isVisible)
        XCTAssertFalse(bubble.isDismissing)
        XCTAssertEqual(model.state, .result("New result"))
        XCTAssertFalse(bubble.canBecomeKey)
    }
    @MainActor func testReduceMotionFadesWithoutMovingPanel() async {
        let (bubble, _, defaults, suite) = makeBubble(reduceMotion: true)
        defer { bubble.hide(); defaults.removePersistentDomain(forName: suite) }
        // Let the hosting view finish its first intrinsic-size layout.
        try? await Task.sleep(for: .milliseconds(160))
        let origin = bubble.frame.origin
        bubble.hide(dissolving: true)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(bubble.frame.origin, origin)
        XCTAssertFalse(bubble.isVisible)
    }
}
