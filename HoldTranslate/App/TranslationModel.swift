import SwiftUI
@preconcurrency import Translation

struct TranslationRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let pair: LanguagePair
}

enum BubbleState: Equatable {
    case loading, result(String), message(String), needsDownload
}

@MainActor final class TranslationModel: ObservableObject {
    @Published var request: TranslationRequest?
    @Published var state: BubbleState = .loading
    @Published var original = ""
    @Published var pair: LanguagePair?
    var onChange: (() -> Void)?
    var onFinished: (() -> Void)?
    var openPreparation: ((LanguagePair) -> Void)?
    private var availabilityTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()

    func begin(text: String, target: TargetChoice) {
        reset()
        original = text
        state = .loading
        let token = generation
        availabilityTask = Task {
            do {
                let pair = try LanguagePolicy.pair(for: text, target: target)
                self.pair = pair
                let availability: LanguageAvailability
                if #available(macOS 26.4, *) { availability = LanguageAvailability(preferredStrategy: .lowLatency) }
                else { availability = LanguageAvailability() }
                let status = await availability.status(from: Locale.Language(identifier: pair.source), to: Locale.Language(identifier: pair.target))
                guard !Task.isCancelled, generation == token else { return }
                switch status {
                case .installed:
                    request = TranslationRequest(text: text, pair: pair)
                    timeoutTask = Task {
                        try? await Task.sleep(for: .seconds(30))
                        guard !Task.isCancelled, self.generation == token, self.state == .loading else { return }
                        self.request = nil
                        self.finish(.message("翻译暂时没有响应，请重试。"))
                    }
                case .supported: finish(.needsDownload)
                case .unsupported: finish(.message("系统暂不支持这个语言组合。"))
                @unknown default: finish(.message("暂时无法确认语言包状态。"))
                }
            } catch { finish(.message(error.localizedDescription)) }
        }
    }
    func complete(_ result: String, id: UUID) {
        guard request?.id == id else { return }
        finish(.result(result))
    }
    func fail(id: UUID) {
        guard request?.id == id else { return }
        finish(.message("翻译未完成。请在设置中检查语言包，然后重试。"))
    }
    func message(_ message: String) { reset(); finish(.message(message)) }
    private func finish(_ state: BubbleState) {
        timeoutTask?.cancel(); timeoutTask = nil
        self.state = state
        onChange?(); onFinished?()
    }
    func reset() {
        generation = UUID()
        availabilityTask?.cancel(); availabilityTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        request = nil; original = ""; pair = nil
    }
}

/// A request owns a SwiftUI translation task. Removing this view cancels its task;
/// results also carry an ID, so a stale response cannot overwrite a newer selection.
struct TranslationWorker: View {
    let request: TranslationRequest
    @ObservedObject var model: TranslationModel
    private var configuration: TranslationSession.Configuration {
        let source = Locale.Language(identifier: request.pair.source)
        let target = Locale.Language(identifier: request.pair.target)
        if #available(macOS 26.4, *) {
            return .init(source: source, target: target, preferredStrategy: .lowLatency)
        }
        return .init(source: source, target: target)
    }
    var body: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            .translationTask(configuration) { session in
                do {
                    let response = try await session.translate(request.text)
                    guard !Task.isCancelled else { return }
                    model.complete(response.targetText, id: request.id)
                } catch {
                    guard !Task.isCancelled else { return }
                    model.fail(id: request.id)
                }
            }
    }
}
