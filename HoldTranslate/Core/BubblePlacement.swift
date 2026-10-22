import Foundation
import CoreGraphics

struct BubblePlacement {
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
