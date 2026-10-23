import SwiftUI
@preconcurrency import Translation

struct TranslationRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let pair: LanguagePair
}

enum BubbleState: Equatable {
    case loading, result(String), message(String), needsDownload, selectionUnavailable
}

@MainActor final class TranslationModel: ObservableObject {
    @Published var request: TranslationRequest?
    @Published var state: BubbleState = .loading
    @Published var original = ""
    @Published var pair: LanguagePair?
    var onChange: (() -> Void)?
    var onFinished: (() -> Void)?
    var copySelection: (() -> Void)?
    var openPreparation: ((LanguagePair) -> Void)?
    private var availabilityTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var generation = UUID()
    private let analyzer = LanguageAnalyzer()
    private let availability: @Sendable (LanguagePair) async -> LanguageAvailability.Status
    private let timeout: Duration

    init(timeout: Duration = .seconds(30), availability: @escaping @Sendable (LanguagePair) async -> LanguageAvailability.Status = { pair in await TranslationModel.languageStatus(pair) }) {
        self.timeout = timeout
        self.availability = availability
    }

    nonisolated static func languageStatus(_ pair: LanguagePair) async -> LanguageAvailability.Status {
        let service: LanguageAvailability
        if #available(macOS 26.4, *) { service = LanguageAvailability(preferredStrategy: .lowLatency) }
        else { service = LanguageAvailability() }
        return await service.status(from: Locale.Language(identifier: pair.source), to: Locale.Language(identifier: pair.target))
    }

    func begin(text: String, target: TargetChoice) {
        reset()
        original = text
        state = .loading
        let token = generation
        timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, generation == token, state == .loading else { return }
            generation = UUID()
            availabilityTask?.cancel()
            finish(.message("翻译暂时没有响应，请重试。"))
        }
        availabilityTask = Task {
            guard !Task.isCancelled, generation == token else { return }
            do {
                let pair = try await analyzer.pair(for: text, target: target)
                guard !Task.isCancelled, generation == token else { return }
                self.pair = pair
                let status = await availability(pair)
                guard !Task.isCancelled, generation == token else { return }
                switch status {
                case .installed: request = TranslationRequest(text: text, pair: pair)
                case .supported: finish(.needsDownload)
                case .unsupported: finish(.message("系统暂不支持这个语言组合。"))
                @unknown default: finish(.message("暂时无法确认语言包状态。"))
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                finish(.message(error.localizedDescription))
            }
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
    func unavailable(copy: @escaping () -> Void) { reset(); copySelection = copy; finish(.selectionUnavailable) }
    func message(_ message: String) { reset(); finish(.message(message)) }
    private func finish(_ state: BubbleState) {
        timeoutTask?.cancel(); timeoutTask = nil
        request = nil
        self.state = state
        onChange?(); onFinished?()
    }
    func reset() {
        generation = UUID()
        availabilityTask?.cancel(); availabilityTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        request = nil; original = ""; pair = nil; state = .loading; copySelection = nil
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
