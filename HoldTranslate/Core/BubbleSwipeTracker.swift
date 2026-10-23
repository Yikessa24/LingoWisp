import AppKit

/// Recognizes an intentional physical rightward two-finger scroll. A gesture
/// must begin inside the bubble; vertical scrolls lock out dismissal until lift.
struct BubbleSwipeTracker {
    private var active = false
    private var rejected = false
    private var horizontal: CGFloat = 0
    private var vertical: CGFloat = 0

    mutating func process(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase,
                          momentum: NSEvent.Phase, precise: Bool, inverted: Bool,
                          inside: Bool) -> Bool {
        guard precise, momentum.isEmpty, inside else { reset(); return false }
        if phase.contains(.cancelled) { reset(); return false }
        if phase.contains(.began) {
            reset(); active = true
        }
        guard active else { return false }
        defer { if phase.contains(.ended) { reset() } }
        guard !rejected else { return false }
        // AppKit reverses deltas for natural scrolling. Normalize to physical
        // finger movement so right means right under either system preference.
        horizontal += inverted ? deltaX : -deltaX
        vertical += abs(deltaY)
        if vertical >= 10 && vertical > abs(horizontal) * 1.2 { rejected = true }
        if horizontal <= -12 { rejected = true }
        guard !rejected, horizontal >= 64, horizontal > vertical * 2 else { return false }
        rejected = true
        return true
    }
    mutating func reset() {
        active = false; rejected = false; horizontal = 0; vertical = 0
    }
}
