import Foundation
import CoreGraphics

struct BubblePlacement {
    static func dragRegion(in bounds: CGRect) -> CGRect {
        // Leave the copy/close buttons and the body out of the drag area.
        CGRect(x: bounds.minX + 10, y: bounds.maxY - 44, width: max(0, bounds.width - 94), height: 40)
    }

    static func manualFrame(topLeft: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let safe = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width), height = min(size.height, safe.height)
        return CGRect(x: min(max(topLeft.x, safe.minX), safe.maxX - width),
                      y: min(max(topLeft.y - height, safe.minY), safe.maxY - height), width: width, height: height)
    }
    /// All arguments use AppKit's global, bottom-left coordinate space, in points.
    static func frame(anchor: CGRect, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let safe = visibleFrame.insetBy(dx: 12, dy: 12)
        let width = min(size.width, safe.width)
        let height = min(size.height, safe.height)
        let x = min(max(anchor.midX - width / 2, safe.minX), safe.maxX - width)
        let below = anchor.minY - 10 - height
        let y = below >= safe.minY ? below : min(anchor.maxY + 10, safe.maxY - height)
        return CGRect(x: x, y: min(max(safe.minY, y), safe.maxY - height), width: width, height: height)
    }

    static func appKitRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
