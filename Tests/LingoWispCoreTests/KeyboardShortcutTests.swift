import XCTest
import AppKit
import Carbon
@testable import LingoWispCore

final class KeyboardShortcutTests: XCTestCase {
    @MainActor private func key(_ code: UInt16 = 2, _ flags: NSEvent.ModifierFlags = .option,
                                characters: String = "∂", plain: String = "d") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: plain, isARepeat: false, keyCode: code)!
    }

    @MainActor func testDefaultUsesOptionDAndRecordsUnmodifiedLabel() {
        let shortcut = KeyboardShortcut.selectionDefault
        XCTAssertEqual(shortcut.display, "⌥D")
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(optionKey))
        XCTAssertEqual(KeyboardShortcut.recorded(from: key()), shortcut)
        XCTAssertTrue(shortcut.matches(key(2, [.option, .capsLock])))
    }

    @MainActor func testRecorderRejectsPlainTypingShiftOnlyEscapeAndModifierKeys() {
        XCTAssertNil(KeyboardShortcut.recorded(from: key(2, [])))
        XCTAssertNil(KeyboardShortcut.recorded(from: key(2, .shift)))
        XCTAssertNil(KeyboardShortcut.recorded(from: key(53, .option, characters: "", plain: "")))
        XCTAssertNil(KeyboardShortcut.recorded(from: key(58, .option)))
        XCTAssertEqual(KeyboardShortcut.recorded(from: key(80, [.control, .option], characters: "", plain: ""))?.display, "⌃⌥F19")
        XCTAssertFalse(KeyboardShortcut.selectionDefault.matches(key(2, [.option, .command])))
    }

    @MainActor func testCustomShortcutPersistsAndInvalidPreferencesRecoverToDefault() throws {
        let suite = "LingoWispShortcutTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, .selectionDefault)
        let custom = KeyboardShortcut(keyCode: 17, flags: [.control, .option, .shift], keyLabel: "T")
        Preferences(defaults: defaults).shortcut = custom
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, custom)
        XCTAssertEqual(custom.display, "⌃⌥⇧T")
        defaults.set(try JSONEncoder().encode(KeyboardShortcut(keyCode: 2, flags: [], keyLabel: "D")), forKey: "selectionShortcut")
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, .selectionDefault)
        defaults.set(Data("corrupt".utf8), forKey: "selectionShortcut")
        XCTAssertEqual(Preferences(defaults: defaults).shortcut, .selectionDefault)
    }

    @MainActor func testNativeRegistrationConflictKeepsPreviousShortcutAndShutdownReleasesIt() throws {
        _ = NSApplication.shared
        let first = GlobalShortcut(), second = GlobalShortcut()
        defer { first.shutdown(); second.shutdown() }
        let a = KeyboardShortcut(keyCode: 80, flags: [.control, .option, .command], keyLabel: "F19")
        let b = KeyboardShortcut(keyCode: 90, flags: [.control, .option, .command], keyLabel: "F20")
        try first.register(a)
        try second.register(b)
        XCTAssertThrowsError(try first.register(b))
        XCTAssertEqual(first.registeredShortcut, a)
        first.shutdown()
        try second.register(a)
        XCTAssertEqual(second.registeredShortcut, a)
    }

    @MainActor func testKeyRepeatAndStaleEventsDoNotRetranslate() throws {
        _ = NSApplication.shared
        let registry = GlobalShortcut()
        defer { registry.shutdown() }
        try registry.register(KeyboardShortcut(keyCode: 80, flags: [.control, .option, .shift], keyLabel: "F19"))
        var count = 0
        registry.onPressed = { count += 1 }
        registry.receive(kind: UInt32(kEventHotKeyPressed), signature: GlobalShortcut.signature, id: 1)
        registry.receive(kind: UInt32(kEventHotKeyPressed), signature: GlobalShortcut.signature, id: 1)
        XCTAssertEqual(count, 1)
        registry.receive(kind: UInt32(kEventHotKeyReleased), signature: GlobalShortcut.signature, id: 1)
        registry.receive(kind: UInt32(kEventHotKeyPressed), signature: GlobalShortcut.signature, id: 1)
        XCTAssertEqual(count, 2)
        registry.stop()
        registry.receive(kind: UInt32(kEventHotKeyPressed), signature: GlobalShortcut.signature, id: 1)
        XCTAssertEqual(count, 2)
    }
}
