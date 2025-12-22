
import Foundation

final class AISettings: ObservableObject {
    static let shared = AISettings()
    private let defaults = UserDefaults.standard
    
    enum AIUsage {
        case general
        case summary
        case translation
    }

    struct Keys {
        static let aiEnabled = "aiEnabled"
        static let aiProvider = "aiProvider"
        static let aiBaseURL = "aiBaseURL"
        static let aiModel = "aiModel"
        static let aiTargetLanguage = "aiTargetLanguage"
        static let aiAutoTranslate = "aiAutoTranslate"
        static let aiRateLimit = "aiRateLimit"
        static let aiApiKey = "aiApiKey"
        static let aiSummaryPrompt = "aiSummaryPrompt"
        static let aiTranslationPrompt = "aiTranslationPrompt"
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.aiEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.aiEnabled)
            objectWillChange.send()
        }
    }

    var provider: String {
        get { defaults.string(forKey: Keys.aiProvider) ?? "OpenAI" }
        set {
            defaults.set(newValue, forKey: Keys.aiProvider)
            objectWillChange.send()
        }
    }

    var baseURL: String {
        get {
            let url = defaults.string(forKey: Keys.aiBaseURL) ?? ""
            return url.isEmpty ? "https://api.openai.com/v1" : url
        }
        set {
            defaults.set(newValue, forKey: Keys.aiBaseURL)
            objectWillChange.send()
        }
    }

    var model: String {
        get {
            let m = defaults.string(forKey: Keys.aiModel) ?? ""
            return m.isEmpty ? "gpt-4o-mini" : m
        }
        set {
            defaults.set(newValue, forKey: Keys.aiModel)
            objectWillChange.send()
        }
    }

    // "English", "Chinese", etc.
    var outputLanguage: String {
        get { defaults.string(forKey: Keys.aiTargetLanguage) ?? "English" }
        set {
            defaults.set(newValue, forKey: Keys.aiTargetLanguage)
            objectWillChange.send()
        }
    }

    var autoTranslate: Bool {
        get { defaults.bool(forKey: Keys.aiAutoTranslate) }
        set {
            defaults.set(newValue, forKey: Keys.aiAutoTranslate)
            objectWillChange.send()
        }
    }

    var rateLimit: String {
        get { defaults.string(forKey: Keys.aiRateLimit) ?? "2/s" }
        set {
            defaults.set(newValue, forKey: Keys.aiRateLimit)
            objectWillChange.send()
        }
    }

    var apiKey: String {
        get { defaults.string(forKey: Keys.aiApiKey) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.aiApiKey)
            objectWillChange.send()
        }
    }
    
    var summaryApiKey: String {
        get { defaults.string(forKey: "aiSummaryApiKey") ?? "" }
        set { defaults.set(newValue, forKey: "aiSummaryApiKey"); objectWillChange.send() }
    }
    
    var translationApiKey: String {
        get { defaults.string(forKey: "aiTranslationApiKey") ?? "" }
        set { defaults.set(newValue, forKey: "aiTranslationApiKey"); objectWillChange.send() }
    }
    
    func getApiKey(for usage: AIUsage) -> String {
        switch usage {
        case .summary: return summaryApiKey.isEmpty ? apiKey : summaryApiKey
        case .translation: return translationApiKey.isEmpty ? apiKey : translationApiKey
        case .general: return apiKey
        }
    }

    // Helper to get QPS as double
    var qps: Double {
        switch rateLimit {
        case "0.5/s": return 0.5
        case "1/s": return 1.0
        case "2/s": return 2.0
        case "5/s": return 5.0
        case "Unlimited": return Double.greatestFiniteMagnitude
        default: return 2.0
        }
    }
    
    var summaryPrompt: String {
        get { defaults.string(forKey: Keys.aiSummaryPrompt) ?? "Please summarize the following article in a concise manner. Use Markdown for formatting (e.g. **bold**, *italic*, ### Headers, - Lists). Do NOT translate URLs or code blocks." }
        set {
            defaults.set(newValue, forKey: Keys.aiSummaryPrompt)
            objectWillChange.send()
        }
    }
    
    // User requested prompt logic
    var translationPrompt: String {
        get { defaults.string(forKey: Keys.aiTranslationPrompt) ?? """
You are a professional translator who needs to fluently translate text into %TARGET_LANGUAGE%.

## Translation Rules
1. Output only the translated content, without explanations or additional content.
2. The returned translation must maintain exactly the same number of paragraphs as the original text.
3. If the text contains HTML tags, consider where the tags should be placed in the translation while maintaining fluency.
4. For content that should not be translated (such as proper nouns, code, etc.), keep the original text.
5. Use Markdown for formatting (bold, italic, etc) if necessary.
""" }
        set {
            defaults.set(newValue, forKey: Keys.aiTranslationPrompt)
            objectWillChange.send()
        }
    }
    func resetSummaryPrompt() {
        defaults.removeObject(forKey: Keys.aiSummaryPrompt)
        objectWillChange.send()
    }
    
    func resetTranslationPrompt() {
        defaults.removeObject(forKey: Keys.aiTranslationPrompt)
        objectWillChange.send()
    }
}
