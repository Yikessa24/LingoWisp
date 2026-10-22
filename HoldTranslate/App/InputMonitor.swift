import AppKit

@MainActor final class InputMonitor {
    var onSelection: ((CGPoint) -> Void)?
    var onOutsideClick: (() -> Void)?
    var onRelease: (() -> Void)?
    var onTyping: (() -> Void)?
    var onMove: ((CGPoint) -> Void)?
    private var global: Any?
    private var local: Any?
    private var gesture = GestureTracker()
    private let preferences: Preferences

    init(preferences: Preferences) { self.preferences = preferences }
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown, .flagsChanged, .keyDown, .scrollWheel]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { self?.onTyping?() }
            }
            return event
        }
    }
    private var movement: Any?
    func watchMovement(_ enabled: Bool) {
        if let movement { NSEvent.removeMonitor(movement); self.movement = nil }
        guard enabled else { return }
        movement = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.onMove?(NSEvent.mouseLocation) }
        }
    }
    func stop() {
        for token in [global, local, movement].compactMap({ $0 }) { NSEvent.removeMonitor(token) }
        global = nil; local = nil; movement = nil
        gesture.reset()
    }
    private func handle(_ event: NSEvent) {
        guard preferences.enabled else { gesture.reset(); return }
        let point = NSEvent.mouseLocation
        let matches = preferences.trigger.matches(event.modifierFlags)
        switch event.type {
        case .leftMouseDown:
            onOutsideClick?()
            gesture.down(at: point, time: event.timestamp, matches: matches)
        case .leftMouseDragged:
            gesture.drag(to: point, matches: matches)
        case .leftMouseUp:
            if gesture.up(at: point, time: event.timestamp, matches: matches) { onSelection?(point) }
        case .flagsChanged:
            if !matches { gesture.reset(); onRelease?() }
        case .keyDown:
            if event.keyCode == 17 && event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift] && !event.isARepeat {
                onSelection?(point)
            } else { onTyping?() }
        case .rightMouseDown, .otherMouseDown, .scrollWheel: onOutsideClick?()
        default: break
        }
    }
}
