import AppKit
import ApplicationServices

/// A value snapshot, never a reference to a lazy NSPasteboardItem owned by another app.
@MainActor struct ClipboardSnapshot {
    let changeCount: Int
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ pasteboard: NSPasteboard) throws -> Self {
        let version = pasteboard.changeCount
        let source = pasteboard.pasteboardItems ?? []
        guard source.count <= 8 else { throw ClipboardSelectionError.unsupportedClipboard }
        var total = 0
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in source {
            guard item.types.count <= 24 else { throw ClipboardSelectionError.unsupportedClipboard }
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // File promises can ask another application to materialize data or block.
                guard !type.rawValue.lowercased().contains("promise"),
                      let value = item.data(forType: type) else { throw ClipboardSelectionError.unsupportedClipboard }
                total += value.count
                guard total <= 8 * 1024 * 1024 else { throw ClipboardSelectionError.unsupportedClipboard }
                data[type] = value
            }
            items.append(data)
        }
        guard pasteboard.changeCount == version else { throw ClipboardSelectionError.concurrentChange }
        return Self(changeCount: version, items: items)
    }

    /// Never replace a newer clipboard owner. Prepare every item before clearing.
    func restore(_ pasteboard: NSPasteboard, replacing version: Int) -> Bool {
        guard pasteboard.changeCount == version else { return false }
        let copies = items.map { data -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, value) in data { item.setData(value, forType: type) }
            return item
        }
        pasteboard.clearContents()
        return copies.isEmpty || pasteboard.writeObjects(copies)
    }
}

enum ClipboardSelectionError: Error, LocalizedError {
    case unsupportedClipboard, concurrentChange, noCopy, wrongApplication, restoreFailed
    var errorDescription: String? {
        switch self {
        case .unsupportedClipboard: "当前剪贴板包含过大、延迟生成或无法完整备份的内容，已跳过复制兼容模式。"
        case .concurrentChange: "剪贴板同时发生了其他变化，已保留新内容。请重新划选。"
        case .noCopy: "此处没有复制到文字。请确认文字确实可复制，或尝试应用内的复制菜单。"
        case .wrongApplication: "当前应用已改变，请重新划选。"
        case .restoreFailed: "系统未能恢复剪贴板，请检查剪贴板内容。"
        }
    }
}

@MainActor final class ClipboardSelectionReader {
    static let eventMarker: Int64 = 0x48544C434F5059
    private let pasteboard: NSPasteboard
    private let isCurrent: @MainActor (pid_t) -> Bool
    private let sendCopy: @MainActor (pid_t) throws -> Void
    private let delays: [Duration]
    private var busy = false

    init(pasteboard: NSPasteboard = .general,
         delays: [Duration] = [.milliseconds(60), .milliseconds(100), .milliseconds(160), .milliseconds(240), .milliseconds(360)],
         isCurrent: @escaping @MainActor (pid_t) -> Bool = { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0 },
         sendCopy: @escaping @MainActor (pid_t) throws -> Void = { try ClipboardSelectionReader.postCopy($0) }) {
        self.pasteboard = pasteboard; self.delays = delays; self.isCurrent = isCurrent; self.sendCopy = sendCopy
    }

    func read(pid: pid_t) async throws -> Selection {
        try Task.checkCancellation()
        // Once Command-C is sent, finish the bounded restoration transaction even
        // if the user's next action cancels the translation request.
        let transaction = Task { @MainActor in try await self.copyTransaction(pid: pid) }
        let selection = try await transaction.value
        try Task.checkCancellation()
        return selection
    }

    private func copyTransaction(pid: pid_t) async throws -> Selection {
        guard !busy, isCurrent(pid) else { throw ClipboardSelectionError.wrongApplication }
        busy = true
        defer { busy = false }
        let snapshot = try ClipboardSnapshot.capture(pasteboard)
        var copiedVersion: Int?
        var restored = false
        defer {
            // Cancellation and errors still restore a copy we observed owning.
            if !restored, let copiedVersion, pasteboard.changeCount == copiedVersion {
                _ = snapshot.restore(pasteboard, replacing: copiedVersion)
            }
        }
        try Task.checkCancellation()
        guard isCurrent(pid), pasteboard.changeCount == snapshot.changeCount else { throw ClipboardSelectionError.concurrentChange }
        try sendCopy(pid)
        for delay in delays {
            try await Task.sleep(for: delay)
            let version = pasteboard.changeCount
            guard version != snapshot.changeCount else {
                guard isCurrent(pid) else { throw ClipboardSelectionError.wrongApplication }
                continue
            }
            // More than one owner change cannot safely be attributed to this copy.
            guard version == snapshot.changeCount + 1 else { throw ClipboardSelectionError.concurrentChange }
            copiedVersion = version
            guard isCurrent(pid) else { throw ClipboardSelectionError.wrongApplication }
            let text = pasteboard.string(forType: .string)
            guard pasteboard.changeCount == version else { copiedVersion = nil; throw ClipboardSelectionError.concurrentChange }
            guard snapshot.restore(pasteboard, replacing: version) else { throw ClipboardSelectionError.restoreFailed }
            restored = true
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClipboardSelectionError.noCopy }
            return Selection(text: text, axBounds: nil)
        }
        throw ClipboardSelectionError.noCopy
    }

    private static func postCopy(_ pid: pid_t) throws {
        guard AXIsProcessTrusted(),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { throw SelectionError.permission }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.postToPid(pid)
        }
    }
}
