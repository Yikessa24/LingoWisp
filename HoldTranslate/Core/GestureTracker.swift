import Foundation
import CoreGraphics

/// Pure state machine. It observes input; it never changes or consumes events.
struct GestureTracker {
    private var origin: CGPoint?
    private var beganAt: TimeInterval = 0
    private var dragged = false
    private(set) var active = false

    mutating func down(at point: CGPoint, time: TimeInterval, matches: Bool) {
        reset()
        guard matches else { return }
        origin = point
        beganAt = time
        active = true
    }

    mutating func drag(to point: CGPoint, matches: Bool) {
        guard matches, let origin else { reset(); return }
        if hypot(point.x - origin.x, point.y - origin.y) >= 6 { dragged = true }
    }

    mutating func up(at point: CGPoint, time: TimeInterval, matches: Bool) -> Bool {
        defer { reset() }
        guard let origin, active, matches else { return false }
        // Down/up positions are sufficient evidence of a held-button drag when
        // the global monitor coalesces intermediate drag callbacks.
        let distance = hypot(point.x - origin.x, point.y - origin.y)
        guard dragged || distance >= 6 else { return false }
        return time - beganAt >= 0.06 && time - beganAt <= 90
            && hypot(point.x - origin.x, point.y - origin.y) >= 3
    }

    mutating func reset() { origin = nil; dragged = false; active = false }
}
