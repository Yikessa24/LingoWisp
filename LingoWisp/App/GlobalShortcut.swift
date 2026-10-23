import AppKit
import Carbon

@MainActor final class GlobalShortcut {
    var onPressed: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var registeredShortcut: KeyboardShortcut?
    private var identifier: UInt32 = 0
    private var held = false
    static let signature: OSType = 0x48544C54

    func register(_ shortcut: KeyboardShortcut) throws {
        guard shortcut.isValid else { throw ShortcutError.invalid }
        if reference != nil && registeredShortcut == shortcut { return }
        if handler == nil {
            var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                    return owner.receive(kind: GetEventKind(event), signature: key.signature, id: key.id)
                }
            }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw ShortcutError.unavailable }
        }
        let next = identifier &+ 1
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: next), GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr, let candidate else { throw ShortcutError.conflict }
        if let reference { UnregisterEventHotKey(reference) }
        reference = candidate; identifier = next; registeredShortcut = shortcut; held = false
    }
    @discardableResult func receive(kind: UInt32, signature: OSType, id: UInt32) -> OSStatus {
        guard reference != nil, signature == Self.signature, id == identifier else { return OSStatus(eventNotHandledErr) }
        if kind == UInt32(kEventHotKeyReleased) { held = false; return noErr }
        guard kind == UInt32(kEventHotKeyPressed) else { return OSStatus(eventNotHandledErr) }
        if !held { held = true; onPressed?() }
        return noErr
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil; registeredShortcut = nil; held = false
    }
    func shutdown() {
        stop()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

enum ShortcutError: Error, LocalizedError {
    case invalid, conflict, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "请使用包含 Option、Control 或 Command 的组合键。Esc 用于取消录制。"
        case .conflict: "这个快捷键已被系统或其他应用占用，请换一个组合。"
        case .unavailable: "暂时无法注册全局快捷键，请重启应用后重试。"
        }
    }
}
