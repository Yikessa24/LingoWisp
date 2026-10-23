import XCTest
import AppKit
@testable import HoldTranslateCore

final class BubbleDragPlacementTests: XCTestCase {
    func testHeaderDragRegionExcludesActionButtonsAndTranslationBody() {
        let bounds = CGRect(x: 0, y: 0, width: 358, height: 152)
        let region = BubblePlacement.dragRegion(in: bounds)
        XCTAssertTrue(region.contains(CGPoint(x: 100, y: 128)))
        XCTAssertFalse(region.contains(CGPoint(x: 336, y: 128))) // close
        XCTAssertFalse(region.contains(CGPoint(x: 307, y: 128))) // copy
        XCTAssertFalse(region.contains(CGPoint(x: 150, y: 65))) // scroll body
    }
    func testManualPositionKeepsTopLeftWhenTranslationHeightChanges() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let topLeft = CGPoint(x: -1000, y: 500)
        for height in [128.0, 379.0] {
            let frame = BubblePlacement.manualFrame(topLeft: topLeft, size: CGSize(width: 358, height: height), visibleFrame: screen)
            XCTAssertEqual(frame.minX, topLeft.x)
            XCTAssertEqual(frame.maxY, topLeft.y)
        }
    }
    func testManualPositionRemainsReachableAfterDisplayChanges() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        for point in [CGPoint(x: -900, y: 1400), CGPoint(x: 2000, y: -400)] {
            let frame = BubblePlacement.manualFrame(topLeft: point, size: CGSize(width: 358, height: 379), visibleFrame: screen)
            XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(frame))
        }
    }
}

final class BubbleBurstRendererTests: XCTestCase {
    private let card = CGRect(x: 240, y: 240, width: 358, height: 128)
    private func context() -> CGContext {
        CGContext(data: nil, width: 838, height: 608, bitsPerComponent: 8, bytesPerRow: 838 * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private func renderer() -> BubbleBurstRenderer {
        let fixture = context()
        fixture.setFillColor(CGColor(gray: 0.8, alpha: 1))
        fixture.fill(CGRect(x: 0, y: 0, width: 838, height: 608))
        return BubbleBurstRenderer(image: fixture.makeImage()!, card: card)!
    }
    func testRightEdgeErodesFirstAndDustOnlyTravelsRight() {
        let renderer = renderer(), ctx = context()
        renderer.draw(in: ctx, time: 0.4)
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var leftSolid = 0, rightSolid = 0, escapedRight = 0, escapedLeft = 0
        for y in 0..<608 { for x in 0..<838 {
            let alpha = bytes[(y * 838 + x) * 4 + 3]
            if y >= 240 && y < 368 && alpha > 220 {
                if x >= 240 && x < 359 { leftSolid += 1 }
                if x >= 479 && x < 598 { rightSolid += 1 }
            }
            if alpha > 8 && x > 599 { escapedRight += 1 }
            if alpha > 8 && x < 239 { escapedLeft += 1 }
        } }
        XCTAssertGreaterThan(leftSolid, 14_000)
        XCTAssertLessThan(rightSolid, 1_000)
        XCTAssertGreaterThan(escapedRight, 50)
        XCTAssertEqual(escapedLeft, 0)
    }
    func testAllPixelsGoneWithinOneAndAHalfSeconds() {
        let renderer = renderer()
        XCTAssertLessThanOrEqual(BubbleBurstRenderer.duration, 1.5)
        for time in [BubbleBurstRenderer.duration, 1.5] {
            let ctx = context()
            renderer.draw(in: ctx, time: time)
            let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
            XCTAssertFalse((0..<(838 * 608)).contains { bytes[$0 * 4 + 3] != 0 })
        }
    }
    func testInitialFrameKeepsWholeBubbleAndTailRetainsOnlyDust() {
        let renderer = renderer()
        func opaqueCount(_ time: Double) -> Int {
            let ctx = context(); renderer.draw(in: ctx, time: time)
            let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
            return (0..<(838 * 608)).filter { bytes[$0 * 4 + 3] > 220 }.count
        }
        XCTAssertGreaterThan(opaqueCount(0), 45_000)
        XCTAssertLessThan(opaqueCount(1.0), 100)
    }
}
