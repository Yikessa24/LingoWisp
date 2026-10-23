import Foundation
import CoreGraphics

/// Pure state machine. It observes input; it never changes or consumes events.
struct GestureTracker {
    // Accessibility three-finger dragging may keep the logical mouse button
    // held briefly after fingers leave the trackpad. Permit that late mouse-up
    // only after an already proven drag, without accepting new unmodified motion.
    static let releaseGrace: TimeInterval = 1.6
    private var origin: CGPoint?
    private var beganAt: TimeInterval = 0
    private var dragged = false
    private var releasedAt: TimeInterval?
    private var releasePoint: CGPoint?
    private var blockedUntilMouseUp = false
    private(set) var active = false

    mutating func down(at point: CGPoint, time: TimeInterval, matches: Bool) {
        reset()
        guard matches else { blockedUntilMouseUp = true; return }
        origin = point
        beganAt = time
        active = true
    }

    mutating func drag(to point: CGPoint, time: TimeInterval? = nil, matches: Bool) {
        if !active {
            // Accessibility dragging can deliver a genuine dragged event without
            // a down visible to this monitor. Never upgrade an observed plain click.
            guard matches, !blockedUntilMouseUp, let time else { return }
            origin = point; beganAt = time; active = true; dragged = true
            return
        }
        guard let origin else { return }
        if !matches {
            // A synthesized final drag event at the same endpoint is harmless;
            // actually moving again without the modifier cancels the gesture.
            guard let releasePoint, hypot(point.x - releasePoint.x, point.y - releasePoint.y) <= 3 else { cancel(); return }
            return
        }
        releasedAt = nil; releasePoint = nil
        if hypot(point.x - origin.x, point.y - origin.y) >= 6 { dragged = true }
    }

    @discardableResult mutating func modifierReleased(at point: CGPoint, time: TimeInterval) -> Bool {
        guard let origin, active else { return false }
        guard time >= beganAt, time - beganAt <= 90,
              hypot(point.x - origin.x, point.y - origin.y) >= 6 else { cancel(); return false }
        // Other flagsChanged callbacks must not extend the grace period.
        if releasedAt == nil { releasedAt = time; releasePoint = point }
        dragged = true
        return true
    }

    mutating func up(at point: CGPoint, time: TimeInterval, matches: Bool) -> Bool {
        defer { reset() }
        guard let origin, active else { return false }
        let distance = hypot(point.x - origin.x, point.y - origin.y)
        guard dragged || distance >= 6 else { return false }
        let lateRelease: Bool
        if let releasedAt, let releasePoint {
            lateRelease = time >= releasedAt && time - releasedAt <= Self.releaseGrace
                && hypot(point.x - releasePoint.x, point.y - releasePoint.y) <= 3
        } else { lateRelease = false }
        guard matches || lateRelease else { return false }
        return time - beganAt >= 0.06 && time - beganAt <= 90 && distance >= 3
    }

    mutating func cancel() {
        reset()
        blockedUntilMouseUp = true
    }

    mutating func reset() {
        blockedUntilMouseUp = false
        origin = nil; dragged = false; active = false
        releasedAt = nil; releasePoint = nil
    }
}
