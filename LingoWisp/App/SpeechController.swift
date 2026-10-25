import AppKit
@preconcurrency import AVFoundation

// A single player owns both buttons, so source and translation never overlap.
enum SpeechPart: String, Sendable { case original, translation }
struct SpeechPlayback: Equatable, Sendable {
    let id: UUID
    let part: SpeechPart
    let text: String
    let language: String
}

@MainActor protocol SpeechEngine: AnyObject {
    var onCompletion: ((UUID) -> Void)? { get set }
    func speak(_ playback: SpeechPlayback) -> Bool
    func stop()
}

@MainActor final class SpeechController: ObservableObject {
    @Published private(set) var playing: SpeechPart?
    @Published private(set) var error: String?
    private var selection: [SpeechPart: String] = [:]
    private var playbackID: UUID?
    private let engine: any SpeechEngine

    init(engine: (any SpeechEngine)? = nil) {
        self.engine = engine ?? SystemSpeechEngine()
        self.engine.onCompletion = { [weak self] id in
            guard let self, self.playbackID == id else { return }
            self.playbackID = nil; self.playing = nil
        }
    }
    func select(_ text: String, in part: SpeechPart) { selection[part] = text }
    func toggle(_ part: SpeechPart, text: String, language: String?) {
        if playing == part { stop(); return }
        stop(); error = nil
        guard let language else { return }
        let selected = selection[part]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let spoken = selected.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : selected
        guard !spoken.isEmpty else { return }
        let playback = SpeechPlayback(id: UUID(), part: part, text: spoken, language: language)
        playbackID = playback.id; playing = part
        if !engine.speak(playback) {
            playbackID = nil; playing = nil
            error = "没有可用的对应语言声音。请在系统设置 → 辅助功能 → 朗读与语音中下载声音后重试。"
        }
    }
    func stop() {
        playbackID = nil; playing = nil
        engine.stop()
    }
    func reset() { stop(); selection.removeAll(); error = nil }
}

private final class IdentifiedSpeechUtterance: AVSpeechUtterance {
    let token = UUID()
}

@MainActor final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    var onCompletion: ((UUID) -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var current: (id: UUID, utterance: IdentifiedSpeechUtterance)?
    override init() { super.init(); synthesizer.delegate = self }

    static func voiceLanguage(_ language: String) -> String {
        if language.hasPrefix("zh-Hant") { return "zh-TW" }
        if language.hasPrefix("zh-Hans") || language == "zh" { return "zh-CN" }
        return language
    }
    static func utterance(text: String, language: String) -> AVSpeechUtterance? {
        let code = voiceLanguage(language)
        guard let voice = AVSpeechSynthesisVoice(language: code),
              voice.language.split(separator: "-").first == code.split(separator: "-").first else { return nil }
        let utterance = IdentifiedSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }
    func speak(_ playback: SpeechPlayback) -> Bool {
        guard let utterance = Self.utterance(text: playback.text, language: playback.language) as? IdentifiedSpeechUtterance else { return false }
        current = (playback.id, utterance)
        synthesizer.speak(utterance)
        return true
    }
    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let utterance = utterance as? IdentifiedSpeechUtterance { completed(utterance.token) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let utterance = utterance as? IdentifiedSpeechUtterance { completed(utterance.token) }
    }
    private nonisolated func completed(_ token: UUID) {
        Task { @MainActor [weak self] in
            guard let self, let current = self.current, current.utterance.token == token else { return }
            self.current = nil
            self.onCompletion?(current.id)
        }
    }
}
