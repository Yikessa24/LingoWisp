import AppKit

@MainActor final class InputMonitor {
    var onGestureStatus: ((String) -> Void)?
    var onSelection: ((CGPoint) -> Void)?
    private var global: Any?
    private var gesture = GestureTracker()
    private(set) var lastGestureTrace: [String: Int] = [:]
    private var traceOrigin = CGPoint.zero
    private var traceBeganAt: TimeInterval = 0
    private let preferences: Preferences
    private let mouseLocation: @MainActor () -> CGPoint

    init(preferences: Preferences, mouseLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }) {
        self.preferences = preferences; self.mouseLocation = mouseLocation
    }
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.process(event) }
        }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        global = nil
        gesture.reset()
    }
    private func modifierBits(_ event: NSEvent) -> Int {
        Int(event.modifierFlags.intersection([.option, .command, .control, .shift]).rawValue)
    }
    func process(_ event: NSEvent) {
        guard preferences.enabled else { gesture.reset(); return }
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ClipboardSelectionReader.eventMarker { return }
        let point: CGPoint
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown:
            // Global events arrive asynchronously. Sampling mouseLocation here
            // can use the final cursor position for every event in a quick drag.
            point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        default: point = mouseLocation()
        }
        let matches = preferences.trigger.matches(event.modifierFlags)
        switch event.type {
        case .leftMouseDown:
            gesture.down(at: point, time: event.timestamp, matches: matches)
            if matches {
                traceOrigin = point; traceBeganAt = event.timestamp
                lastGestureTrace = ["downModifiers": modifierBits(event), "dragCallbacks": 0]
                onGestureStatus?("mouseDownMatched")
            }
        case .leftMouseDragged:
            let wasActive = gesture.active
            gesture.drag(to: point, time: event.timestamp, matches: matches)
            if !wasActive && gesture.active {
                traceOrigin = point; traceBeganAt = event.timestamp
                lastGestureTrace = ["downModifiers": modifierBits(event), "dragCallbacks": 0, "beganWithDrag": 1]
                onGestureStatus?("dragStartedWithoutMouseDown")
            }
            if wasActive || gesture.active {
                lastGestureTrace["dragCallbacks", default: 0] += 1
                if !gesture.active { onGestureStatus?("dragCancelledByMovement") }
            }
        case .leftMouseUp:
            let wasActive = gesture.active
            let accepted = gesture.up(at: point, time: event.timestamp, matches: matches)
            if wasActive || matches {
                lastGestureTrace["upModifiers"] = modifierBits(event)
                lastGestureTrace["durationMilliseconds"] = Int(max(0, event.timestamp - traceBeganAt) * 1000)
                lastGestureTrace["distancePoints"] = Int(hypot(point.x - traceOrigin.x, point.y - traceOrigin.y))
                onGestureStatus?(accepted ? "dragAccepted" : "mouseUpRejected")
            }
            if accepted { onSelection?(point) }
        case .flagsChanged:
            if !matches {
                let wasActive = gesture.active
                let relevant = event.modifierFlags.intersection([.option, .command, .control, .shift])
                if relevant.isSubset(of: preferences.trigger.flags) {
                    let retained = gesture.modifierReleased(at: mouseLocation(), time: event.timestamp)
                    if wasActive {
                        lastGestureTrace["releasedBeforeMouseUp"] = 1
                        onGestureStatus?(retained ? "awaitingDelayedMouseUp" : "modifierReleasedWithoutDrag")
                    }
                } else {
                    gesture.cancel()
                    if wasActive { onGestureStatus?("dragCancelledByOtherModifier") }
                }
            }
        default: break
        }
    }
}
