import XCTest
import AppKit
@testable import HoldTranslateCore

final class LifecycleTests: XCTestCase {
    @MainActor func testLateResponsesNeverOverwriteCurrentRequest() async {
        let model = TranslationModel()
        let old = TranslationRequest(text: "Old selection", pair: .init(source: "en", target: "zh-Hans"))
        let current = TranslationRequest(text: "New selection", pair: .init(source: "en", target: "zh-Hans"))
        model.request = old
        model.request = current
        model.complete("old result", id: old.id)
        XCTAssertEqual(model.state, .loading)
        model.complete("new result", id: current.id)
        XCTAssertEqual(model.state, .result("new result"))
        model.fail(id: old.id)
        XCTAssertEqual(model.state, .result("new result"))
    }
    @MainActor func testResetDropsSelectionAndRejectsLateCompletion() async {
        let model = TranslationModel()
        let request = TranslationRequest(text: "Private selection", pair: .init(source: "en", target: "zh-Hans"))
        model.request = request; model.original = request.text; model.pair = request.pair
        model.reset()
        model.complete("late result", id: request.id)
        XCTAssertNil(model.request); XCTAssertNil(model.pair)
        XCTAssertEqual(model.original, "")
        XCTAssertEqual(model.state, .loading)
    }
    @MainActor func testCancelBeforeLanguageCheckCompletesDoesNotReviveRequest() async {
        let model = TranslationModel()
        model.begin(text: "This is a sentence to translate.", target: .automatic)
        model.reset()
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(model.request); XCTAssertNil(model.pair); XCTAssertEqual(model.original, "")
    }
    @MainActor func testResetAlsoErasesTranslatedText() async {
        let model = TranslationModel()
        model.state = .result("Sensitive result")
        model.reset()
        XCTAssertEqual(model.state, .loading)
    }
    @MainActor func testMissingAndUnsupportedPackagesNeverStartTranslation() async {
        let supported = TranslationModel(availability: { _ in .supported })
        supported.begin(text: "This is an English sentence.", target: .automatic)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(supported.state, .needsDownload); XCTAssertNil(supported.request)
        let unsupported = TranslationModel(availability: { _ in .unsupported })
        unsupported.begin(text: "This is an English sentence.", target: .automatic)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(unsupported.state, .message("系统暂不支持这个语言组合。"))
        XCTAssertNil(unsupported.request)
    }
    @MainActor func testTimeoutIncludesLanguageAvailabilityAndRejectsLateResponse() async {
        let model = TranslationModel(timeout: .milliseconds(40), availability: { _ in
            // Deliberately ignore cancellation to mimic an uncooperative system service.
            try? await Task.sleep(for: .seconds(1))
            return .installed
        })
        model.begin(text: "This is an English sentence.", target: .automatic)
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.state, .message("翻译暂时没有响应，请重试。"))
        XCTAssertNil(model.request)
    }
    @MainActor func testExactModifierMatching() async {
        XCTAssertTrue(TriggerKey.option.matches(.option))
        XCTAssertTrue(TriggerKey.option.matches([.option, .capsLock]))
        XCTAssertFalse(TriggerKey.option.matches([.option, .shift]))
        XCTAssertFalse(TriggerKey.option.matches([.option, .command]))
        XCTAssertTrue(TriggerKey.optionCommand.matches([.option, .command]))
    }
    @MainActor func testPreferencesPersistWithoutTextHistory() async {
        let name = "HoldTranslateTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.trigger = .control; preferences.enabled = false; preferences.target = .japanese
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.trigger, .control); XCTAssertFalse(restored.enabled)
        XCTAssertEqual(restored.target, .japanese)
        XCTAssertEqual(Set(defaults.persistentDomain(forName: name)!.keys), Set(["trigger", "enabled", "target"]))
    }
    @MainActor func testPanelCannotTakeKeyboardFocus() async {
        let panel = TranslationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }
}
