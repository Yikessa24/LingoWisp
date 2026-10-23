import Foundation
import NaturalLanguage
import CoreServices

enum TargetChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, simplifiedChinese = "zh-Hans", english = "en", japanese = "ja", korean = "ko", french = "fr"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动 · 中文 ⇄ 外语"
        case .simplifiedChinese: "简体中文"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        case .french: "法语"
        }
    }
}

struct LanguagePair: Equatable, Sendable {
    let source: String
    let target: String
    var label: String {
        let locale = Locale(identifier: "zh-Hans")
        return "\(locale.localizedString(forIdentifier: source) ?? source) → \(locale.localizedString(forIdentifier: target) ?? target)"
    }
}

enum TextIssue: Error, Equatable, LocalizedError {
    case empty, tooLong, nonLinguistic, uncertain, sameLanguage
    var errorDescription: String? {
        switch self {
        case .empty: "没有可翻译的选中文字。"
        case .tooLong: "选区较长，请选取 5,000 字以内的内容。"
        case .nonLinguistic: "这段内容似乎是数字、网址或代码。"
        case .uncertain: "无法可靠判断语言，请选择更完整的词句。"
        case .sameLanguage: "原文已经是目标语言。"
        }
    }
}

struct LanguagePolicy {
    static func cleaned(_ raw: String) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TextIssue.empty }
        guard text.count <= 5_000 else { throw TextIssue.tooLong }
        guard text.unicodeScalars.contains(where: CharacterSet.letters.contains) else { throw TextIssue.nonLinguistic }
        if text.range(of: #"^(https?://|www\.|\S+@\S+\.\S+|file://|/Users/|/usr/)"#, options: .regularExpression) != nil {
            throw TextIssue.nonLinguistic
        }
        let codeSignals = ["=>", "func ", "let ", "var ", "import ", "#include", "console.", "</", "{", "}", ";"]
        if codeSignals.filter({ text.contains($0) }).count >= 2 { throw TextIssue.nonLinguistic }
        return text
    }

    static func pair(for text: String, target: TargetChoice) throws -> LanguagePair {
        let text = try cleaned(text)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3).sorted { $0.value > $1.value }
        guard let best = hypotheses.first else { throw TextIssue.uncertain }
        let hasKana = text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        let hasHangul = text.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) }
        let hanCount = text.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let letterCount = text.unicodeScalars.filter(CharacterSet.letters.contains).count
        let source: String
        if hasKana { source = "ja" }
        else if hasHangul { source = "ko" }
        else if hanCount > 0 && Double(hanCount) / Double(max(letterCount, 1)) >= 0.5 {
            source = best.key == .traditionalChinese ? "zh-Hant" : "zh-Hans"
        } else {
            // Keep a conservative escape hatch for real English words (e.g. hello),
            // whose language probabilities are spread across many Latin languages.
            // Never assume every ASCII token is English. Dictionary lookup is local.
            let word = text.trimmingCharacters(in: .punctuationCharacters)
            let isLatinWord = word.range(of: "^[A-Za-z]{2,40}$", options: .regularExpression) != nil
            let dictionaryConfirmsEnglish = best.key == .english && isLatinWord &&
                DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: (word as NSString).length)) != nil
            guard best.value >= 0.45 || dictionaryConfirmsEnglish else { throw TextIssue.uncertain }
            source = best.key.rawValue
        }
        let destination = target == .automatic ? (source.hasPrefix("zh") ? "en" : "zh-Hans") : target.rawValue
        guard source != destination && !(source.hasPrefix("zh") && destination.hasPrefix("zh")) else { throw TextIssue.sameLanguage }
        return LanguagePair(source: source, target: destination)
    }
}

/// Isolates NaturalLanguage and DictionaryServices work from the UI thread.
actor LanguageAnalyzer {
    func pair(for text: String, target: TargetChoice) throws -> LanguagePair {
        try LanguagePolicy.pair(for: text, target: target)
    }
}
