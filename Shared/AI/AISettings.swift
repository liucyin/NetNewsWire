
import Foundation

final class AISettings: ObservableObject {
    static let shared = AISettings()
    private let defaults = UserDefaults.standard

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
        get { defaults.string(forKey: Keys.aiSummaryPrompt) ?? "Please summarize the following article in a concise manner. Output your response as a single HTML snippet (using <b>, <i>, <br> tags) suitable for direct injection into a div. Do NOT use Markdown (no #, *, etc). Do NOT translate URLs or code blocks." }
        set {
            defaults.set(newValue, forKey: Keys.aiSummaryPrompt)
            objectWillChange.send()
        }
    }
    
    var translationPrompt: String {
        get { defaults.string(forKey: Keys.aiTranslationPrompt) ?? "Please translate the following text to %TARGET_LANGUAGE%. Maintain the original tone. Output your response as a single HTML snippet (using <b>, <i>, <br> tags). Do NOT use Markdown. Do NOT translate URLs, code blocks, or technical terms that should remain in English." }
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
