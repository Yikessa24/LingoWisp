// Fixed synthetic speech fixtures only; never linked into the released app.
import AppKit
@preconcurrency import AVFoundation

@MainActor final class SpeechProbeEngine: SpeechEngine {
    var onCompletion: ((UUID) -> Void)?
    private let system = SystemSpeechEngine()
    private var events: [[String: Any]] = []
    init() {
        system.onCompletion = { [weak self] id in
            self?.record(["event": "finished", "id": id.uuidString])
            self?.onCompletion?(id)
        }
    }
    func speak(_ playback: SpeechPlayback) -> Bool {
        let accepted = system.speak(playback)
        record(["event": "speak", "id": playback.id.uuidString, "part": playback.part.rawValue,
                "text": playback.text, "language": playback.language, "accepted": accepted])
        return accepted
    }
    func stop() { system.stop(); record(["event": "stop"]) }
    private func record(_ event: [String: Any]) { events.append(event); SpeechVerification.save(events) }
}

private final class PCMResult: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var peak: Float = 0
    private var finished = false
    private let completion: @Sendable (Int, Float, Bool) -> Void
    init(completion: @escaping @Sendable (Int, Float, Bool) -> Void) { self.completion = completion }
    func accept(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 { finish(timedOut: false); return }
        var samplePeak: Float = 0
        if let values = pcm.floatChannelData?[0] {
            for i in 0..<Int(pcm.frameLength) { samplePeak = max(samplePeak, abs(values[i])) }
        } else if let values = pcm.int16ChannelData?[0] {
            for i in 0..<Int(pcm.frameLength) { samplePeak = max(samplePeak, abs(Float(values[i])) / 32768) }
        }
        lock.lock(); frames += Int(pcm.frameLength); peak = max(peak, samplePeak); lock.unlock()
    }
    func finish(timedOut: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let count = frames, amplitude = peak
        lock.unlock()
        completion(count, amplitude, timedOut)
    }
}

@MainActor enum SpeechVerification {
    static func save(_ value: Any) {
        guard let index = CommandLine.arguments.firstIndex(of: "--speech-report"),
              CommandLine.arguments.indices.contains(index + 1),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
    }
    static func checkAudio() async -> Bool {
        var results: [[String: Any]] = []
        for (language, text) in [("en", "beautiful"), ("zh-Hans", "学习新事物")] {
            guard let utterance = SystemSpeechEngine.utterance(text: text, language: language) else { return false }
            let synthesizer = AVSpeechSynthesizer()
            let metrics: (Int, Float, Bool) = await withCheckedContinuation { continuation in
                let result = PCMResult { count, peak, timedOut in continuation.resume(returning: (count, peak, timedOut)) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { result.finish(timedOut: true) }
                synthesizer.write(utterance) { buffer in result.accept(buffer) }
            }
            withExtendedLifetime(synthesizer) {}
            results.append(["language": language, "voice": utterance.voice?.language ?? "",
                            "frames": metrics.0, "peak": metrics.1, "timedOut": metrics.2])
        }
        save(results)
        return results.allSatisfy { ($0["frames"] as? Int ?? 0) > 0 && ($0["peak"] as? Float ?? 0) > 0.001 && $0["timedOut"] as? Bool == false }
    }
}
