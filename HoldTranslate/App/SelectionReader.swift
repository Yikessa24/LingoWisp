import AppKit
import ApplicationServices

struct Selection: Sendable {
    let text: String
    let axBounds: CGRect?
}

enum SelectionError: Error, LocalizedError {
    case permission, secure, unavailable, timedOut
    var errorDescription: String? {
        switch self {
        case .permission: "需要辅助功能权限。请在菜单栏打开设置。"
        case .secure: "出于隐私保护，已跳过安全输入区域。"
        case .unavailable: "此应用未提供可访问的选区。可尝试先选中，再按 ⇧⌘T。"
        case .timedOut: "此应用暂时没有响应选区请求，请稍后重试。"
        }
    }
}

/// AX calls can block in another process. Keep them off the UI actor and impose
/// a per-call timeout, a small candidate budget, and an overall time budget.
actor SelectionReader {
    func read(pid: pid_t, point: CGPoint) throws -> Selection {
        guard AXIsProcessTrusted() else { throw SelectionError.permission }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let deadline = Date().addingTimeInterval(1.2)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard Date() < deadline else { return nil }
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func secure(_ candidate: AXUIElement) -> Bool {
            var current: AXUIElement? = candidate
            for _ in 0..<5 {
                guard let item = current else { break }
                if (attribute(item, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole { return true }
                if (attribute(item, "AXProtectedContent") as? Bool) == true { return true }
                current = element(attribute(item, kAXParentAttribute))
            }
            return false
        }
        var candidates: [AXUIElement] = []
        if let focused = element(attribute(app, kAXFocusedUIElementAttribute)) {
            if secure(focused) { throw SelectionError.secure }
            candidates.append(focused)
        }
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit)
        if let hit {
            if secure(hit) { throw SelectionError.secure }
            candidates.append(hit)
        }
        // Some browsers expose selected text on a focused element's parent.
        var index = 0
        while index < candidates.count && index < 7 && Date() < deadline {
            let candidate = candidates[index]
            index += 1
            if secure(candidate) { throw SelectionError.secure }
            var text = attribute(candidate, kAXSelectedTextAttribute) as? String
            var bounds: CGRect?
            if let rawRange = attribute(candidate, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() {
                let rangeValue = rawRange as! AXValue
                var range = CFRange()
                if AXValueGetType(rangeValue) == .cfRange && AXValueGetValue(rangeValue, .cfRange, &range) && range.length > 0 && range.length <= 20_000 {
                    if text == nil || text?.isEmpty == true {
                        var substring: CFTypeRef?
                        if Date() < deadline {
                            AXUIElementCopyParameterizedAttributeValue(candidate, kAXStringForRangeParameterizedAttribute as CFString, rawRange, &substring)
                            text = substring as? String
                        }
                    }
                    var rawBounds: CFTypeRef?
                    if Date() < deadline {
                        AXUIElementCopyParameterizedAttributeValue(candidate, kAXBoundsForRangeParameterizedAttribute as CFString, rawRange, &rawBounds)
                    }
                    if let rawBounds, CFGetTypeID(rawBounds) == AXValueGetTypeID() {
                        let value = rawBounds as! AXValue
                        var rect = CGRect.zero
                        if AXValueGetType(value) == .cgRect && AXValueGetValue(value, .cgRect, &rect) && !rect.isEmpty && !rect.isInfinite && !rect.isNull {
                            bounds = rect
                        }
                    }
                }
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Selection(text: text, axBounds: bounds)
            }
            if let parent = element(attribute(candidate, kAXParentAttribute)), !candidates.contains(where: { CFEqual($0, parent) }) {
                candidates.append(parent)
            }
        }
        if Date() >= deadline { throw SelectionError.timedOut }
        throw SelectionError.unavailable
    }
}
