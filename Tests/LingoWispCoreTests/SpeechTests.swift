import XCTest
import AppKit
@testable import LingoWispCore

@MainActor final class SpeechTests: XCTestCase {
    private final class Engine: SpeechEngine {
        var onCompletion: ((UUID) -> Void)?
        var requests: [SpeechPlayback] = []
        var stops = 0
        var available = true
        func speak(_ playback: SpeechPlayback) -> Bool { requests.append(playback); return available }
        func stop() { stops += 1 }
    }
    func testSourceAndTranslationUseTheirOwnTextAndLanguage() {
        let engine = Engine()
        let player = SpeechController(engine: engine)
        player.toggle(.original, text: "beautiful", language: "en")
        XCTAssertEqual(engine.requests.last?.text, "beautiful")
        XCTAssertEqual(engine.requests.last?.language, "en")
        player.toggle(.translation, text: "美丽的", language: "zh-Hans")
        XCTAssertEqual(engine.requests.last?.text, "美丽的")
        XCTAssertEqual(engine.requests.last?.language, "zh-Hans")
        XCTAssertEqual(player.playing, .translation)
    }
    func testEachSidePrefersOnlyItsOwnSelectedWord() {
        let engine = Engine()
        let speech = SpeechController(engine: engine)
        speech.select(" beautiful ", in: .original)
        speech.select("学习", in: .translation)
        speech.toggle(.original, text: "A beautiful day.", language: "en")
        XCTAssertEqual(engine.requests.last?.text, "beautiful")
        speech.toggle(.translation, text: "今天学习新知识。", language: "zh-Hans")
        XCTAssertEqual(engine.requests.last?.text, "学习")
    }
    func testSecondClickStopsAndSwitchingDoesNotQueue() {
        let engine = Engine()
        let player = SpeechController(engine: engine)
        player.toggle(.original, text: "Hello", language: "en")
        let stops = engine.stops
        player.toggle(.original, text: "Hello", language: "en")
        XCTAssertNil(player.playing)
        XCTAssertEqual(engine.requests.count, 1)
        XCTAssertEqual(engine.stops, stops + 1)
        player.toggle(.original, text: "Hello", language: "en")
        let switches = engine.stops
        player.toggle(.translation, text: "你好", language: "zh-Hans")
        XCTAssertEqual(engine.stops, switches + 1)
        XCTAssertEqual(player.playing, .translation)
    }
    func testCompletionFromStoppedSpeechCannotClearNewPlayback() {
        let engine = Engine()
        let player = SpeechController(engine: engine)
        player.toggle(.original, text: "Hello", language: "en")
        let old = engine.requests.last!.id
        player.toggle(.translation, text: "你好", language: "zh-Hans")
        engine.onCompletion?(old)
        XCTAssertEqual(player.playing, .translation)
        engine.onCompletion?(engine.requests.last!.id)
        XCTAssertNil(player.playing)
    }
    func testUnavailableVoiceAndEmptyInputDoNotLeaveStopButton() {
        let engine = Engine()
        let speech = SpeechController(engine: engine)
        speech.toggle(.original, text: "", language: "en")
        speech.toggle(.original, text: "hello", language: nil)
        XCTAssertTrue(engine.requests.isEmpty)
        engine.available = false
        speech.toggle(.original, text: "hello", language: "en")
        XCTAssertNil(speech.playing)
        XCTAssertNotNil(speech.error)
        speech.reset()
        XCTAssertNil(speech.error)
    }
    func testClearedSelectionReadsWholeParagraphAndResetDropsOldWord() {
        let engine = Engine()
        let player = SpeechController(engine: engine)
        player.select("old", in: .original)
        player.select("", in: .original)
        player.toggle(.original, text: "whole paragraph", language: "en")
        XCTAssertEqual(engine.requests.last?.text, "whole paragraph")
        player.select("old", in: .original)
        player.reset()
        player.toggle(.original, text: "new paragraph", language: "en")
        XCTAssertEqual(engine.requests.last?.text, "new paragraph")
    }
    func testOriginalAndTranslationNativeSelectionsReachSpeechWithoutClipboard() {
        _ = NSApplication.shared
        let engine = Engine(), speech = SpeechController(engine: engine)
        for part in [SpeechPart.original, .translation] {
            let view = TranslationTextView()
            let original = part == .original
            view.configure(fontSize: original ? 12 : 15, secondary: original, name: original ? "原文" : "译文")
            view.selectionChanged = { speech.select($0, in: part) }
            let text = original ? "A beautiful day." : "学习新事物 🌍。"
            let selected = original ? "beautiful" : "新事物 🌍"
            view.setTranslation(text)
            view.setSelectedRange((text as NSString).range(of: selected))
            speech.toggle(part, text: text, language: original ? "en" : "zh-Hans")
            XCTAssertEqual(engine.requests.last?.text, selected)
            XCTAssertFalse(view.isEditable)
        }
    }
    func testClosingBubbleAndNewTranslationStopSpeech() {
        _ = NSApplication.shared
        let engine = Engine(), speech = SpeechController(engine: engine)
        let model = TranslationModel(speech: speech)
        let suite = "LingoWispSpeechTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bubble = BubbleController(model: model, preferences: Preferences(defaults: defaults), reduceMotion: { true })
        bubble.show(anchor: CGRect(x: 200, y: 200, width: 1, height: 1))
        speech.toggle(.original, text: "hello", language: "en")
        bubble.hide()
        XCTAssertNil(speech.playing)
        speech.select("old", in: .original)
        speech.toggle(.original, text: "old paragraph", language: "en")
        model.begin(text: "A new day.", target: .automatic)
        XCTAssertNil(speech.playing)
        speech.toggle(.original, text: "new paragraph", language: "en")
        XCTAssertEqual(engine.requests.last?.text, "new paragraph")
        model.reset()
    }
    func testChineseScriptsMapToMatchingVoicesAndUtterancesKeepSelectedText() {
        XCTAssertEqual(SystemSpeechEngine.voiceLanguage("zh-Hans"), "zh-CN")
        XCTAssertEqual(SystemSpeechEngine.voiceLanguage("zh-Hant"), "zh-TW")
        XCTAssertEqual(SystemSpeechEngine.voiceLanguage("en-GB"), "en-GB")
        let utterance = SystemSpeechEngine.utterance(text: "beautiful", language: "en")
        XCTAssertNotNil(utterance)
        XCTAssertEqual(utterance?.speechString, "beautiful")
        XCTAssertTrue(utterance?.voice?.language.hasPrefix("en") == true)
    }
}
