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
    private func context() -> CGContext {
        CGContext(data: nil, width: 578, height: 348, bitsPerComponent: 8, bytesPerRow: 578 * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    func testRuptureActuallyRemovesFilmAndEmitsParticlesOutsideCard() {
        let fixture = context()
        fixture.setFillColor(CGColor(gray: 0.6, alpha: 1))
        fixture.fill(CGRect(x: 0, y: 0, width: 578, height: 348))
        let image = fixture.makeImage()!
        let card = CGRect(x: 110, y: 110, width: 358, height: 128)
        func pixels(_ time: Double) -> (inside: Int, outside: Int) {
            let ctx = context()
            BubbleBurstRenderer.draw(in: ctx, image: image, card: card, time: time)
            let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
            var inside = 0, outside = 0
            for y in 0..<348 { for x in 0..<578 where bytes[(y * 578 + x) * 4 + 3] > 0 {
                if card.contains(CGPoint(x: x, y: y)) { inside += 1 } else { outside += 1 }
            } }
            return (inside, outside)
        }
        let intact = pixels(0), torn = pixels(0.13), scattered = pixels(0.30), ended = pixels(0.62)
        XCTAssertGreaterThan(intact.inside, 40_000)
        XCTAssertLessThan(torn.inside, intact.inside / 2)
        XCTAssertGreaterThan(scattered.outside, 50)
        XCTAssertLessThan(scattered.inside, 500)
        XCTAssertEqual(ended.inside + ended.outside, 0)
    }
    func testRimParticlesStartOnRoundedBoundary() {
        let rect = CGRect(x: 110, y: 110, width: 358, height: 128)
        for index in 0..<100 {
            let point = BubbleBurstRenderer.boundaryPoint(fraction: CGFloat(index) / 100, rect: rect)
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(point))
            XCTAssertFalse(rect.insetBy(dx: 16.1, dy: 16.1).contains(point))
        }
    }
}
