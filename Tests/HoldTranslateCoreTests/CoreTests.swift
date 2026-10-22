import XCTest
import CoreGraphics
@testable import HoldTranslateCore

final class GestureTests: XCTestCase {
    func testClickNeverTriggers() {
        var tracker = GestureTracker()
        tracker.down(at: .zero, time: 0, matches: true)
        XCTAssertFalse(tracker.up(at: .zero, time: 1, matches: true))
    }
    func testRealDragTriggersOnce() {
        var tracker = GestureTracker()
        tracker.down(at: .zero, time: 0, matches: true)
        tracker.drag(to: CGPoint(x: 40, y: 0), matches: true)
        XCTAssertTrue(tracker.up(at: CGPoint(x: 40, y: 0), time: 0.5, matches: true))
        XCTAssertFalse(tracker.up(at: CGPoint(x: 40, y: 0), time: 0.6, matches: true))
    }
    func testModifierMustBeHeldFromStart() {
        var tracker = GestureTracker()
        tracker.down(at: .zero, time: 0, matches: false)
        tracker.drag(to: CGPoint(x: 40, y: 0), matches: true)
        XCTAssertFalse(tracker.up(at: CGPoint(x: 40, y: 0), time: 1, matches: true))
    }
    func testReleaseOrModifierChangeCancelsDrag() {
        var tracker = GestureTracker()
        tracker.down(at: .zero, time: 0, matches: true)
        tracker.drag(to: CGPoint(x: 40, y: 0), matches: false)
        XCTAssertFalse(tracker.up(at: CGPoint(x: 40, y: 0), time: 1, matches: true))
    }
    func testTinyOrVeryFastMovementDoesNotTrigger() {
        var tracker = GestureTracker()
        tracker.down(at: .zero, time: 0, matches: true)
        tracker.drag(to: CGPoint(x: 3, y: 0), matches: true)
        XCTAssertFalse(tracker.up(at: CGPoint(x: 3, y: 0), time: 1, matches: true))
        tracker.down(at: .zero, time: 0, matches: true)
        tracker.drag(to: CGPoint(x: 40, y: 0), matches: true)
        XCTAssertFalse(tracker.up(at: CGPoint(x: 40, y: 0), time: 0.01, matches: true))
    }
}

final class PlacementTests: XCTestCase {
    func testAllEdgesAcrossNegativeAndVerticalScreens() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 50, width: 1920, height: 1080), CGRect(x: 0, y: 900, width: 2560, height: 1440)]
        for screen in screens {
            for x in stride(from: screen.minX, through: screen.maxX, by: 120) {
                for y in stride(from: screen.minY, through: screen.maxY, by: 90) {
                    let frame = BubblePlacement.frame(anchor: CGRect(x: x, y: y, width: 1, height: 1), size: CGSize(width: 358, height: 420), visibleFrame: screen)
                    XCTAssertTrue(screen.insetBy(dx: 11, dy: 11).contains(frame), "\(frame) outside \(screen)")
                }
            }
        }
    }
    func testAXCoordinatesUsePrimaryDisplayNotTargetDisplayHeight() {
        let rect = BubblePlacement.appKitRect(fromAX: CGRect(x: -1200, y: -500, width: 100, height: 20), primaryHeight: 900)
        XCTAssertEqual(rect, CGRect(x: -1200, y: 1380, width: 100, height: 20))
    }
    func testSmallScreenClampsSize() {
        let screen = CGRect(x: 0, y: 0, width: 320, height: 240)
        let frame = BubblePlacement.frame(anchor: .zero, size: CGSize(width: 358, height: 420), visibleFrame: screen)
        XCTAssertTrue(screen.contains(frame))
    }
}

final class LanguageTests: XCTestCase {
    func testRulesForSimplifiedAndTraditionalChinese() throws {
        for text in ["今天的天气很好，我们一起出去散步吧。", "今天的天氣很好，我們一起出去散步吧。"] {
            let pair = try LanguagePolicy.pair(for: text, target: .automatic)
            XCTAssertTrue(pair.source.hasPrefix("zh")); XCTAssertEqual(pair.target, "en")
        }
    }
    func testEnglishAndOtherLanguages() throws {
        for (text, source) in [("This is a beautiful day to learn something new.", "en"), ("今日はとても良い天気です。", "ja"), ("오늘 날씨가 정말 좋습니다.", "ko"), ("Bonjour, je suis heureux de vous rencontrer.", "fr")] {
            let pair = try LanguagePolicy.pair(for: text, target: .automatic)
            XCTAssertEqual(pair.source, source); XCTAssertEqual(pair.target, "zh-Hans")
        }
    }
    func testWordAndMultipleParagraphs() throws {
        XCTAssertEqual(try LanguagePolicy.pair(for: "hello", target: .automatic).target, "zh-Hans")
        XCTAssertEqual(try LanguagePolicy.cleaned("  First paragraph.\n\nSecond paragraph.  "), "First paragraph.\n\nSecond paragraph.")
    }
    func testRejectNonLinguisticText() {
        for text in ["", " \n ", "1234", "!?…", "https://example.com", "user@example.com", "let x = { value };", String(repeating: "a", count: 5001)] {
            XCTAssertThrowsError(try LanguagePolicy.cleaned(text), text)
        }
    }
    func testExplicitTargetAndSameLanguage() throws {
        XCTAssertEqual(try LanguagePolicy.pair(for: "This is an English sentence.", target: .japanese).target, "ja")
        XCTAssertThrowsError(try LanguagePolicy.pair(for: "This is an English sentence.", target: .english))
        XCTAssertThrowsError(try LanguagePolicy.pair(for: "這是繁體中文句子。", target: .simplifiedChinese))
    }
}
