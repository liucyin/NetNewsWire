
import Foundation

struct AIProviderProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var baseURL: String
    var apiKey: String
    var model: String
    var rateLimit: String // "2/s", etc.
    
    // Default initializer
    init(id: UUID = UUID(), name: String, baseURL: String, apiKey: String, model: String, rateLimit: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.rateLimit = rateLimit
    }
}

@MainActor
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
        static let aiProfiles = "aiProfiles"
        static let aiSummaryProfileID = "aiSummaryProfileID"
        static let aiTranslationProfileID = "aiTranslationProfileID"
        static let aiTargetLanguage = "aiTargetLanguage"
        static let aiAutoTranslate = "aiAutoTranslate"
        static let aiAutoTranslateTitles = "aiAutoTranslateTitles"
        
        static let aiSummaryPrompt = "aiSummaryPrompt"
        static let aiTranslationPrompt = "aiTranslationPrompt"
        static let aiHoverModifier = "aiHoverModifier"
        static let aiHoverTranslationEnabled = "aiHoverTranslationEnabled"
        
        // Legacy keys for migration
        static let aiProvider = "aiProvider"
        static let aiBaseURL = "aiBaseURL"
        static let aiModel = "aiModel"
        static let aiRateLimit = "aiRateLimit"
        static let aiApiKey = "aiApiKey"
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.aiEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.aiEnabled)
            objectWillChange.send()
        }
    }
    
    // MARK: - Profiles
    
    @Published var profiles: [AIProviderProfile] = [] {
        didSet {
            saveProfiles()
        }
    }
    
    var summaryProfileID: UUID? {
        get {
            if let str = defaults.string(forKey: Keys.aiSummaryProfileID),
               let uuid = UUID(uuidString: str),
               profiles.contains(where: { $0.id == uuid }) {
                return uuid
            }
            return preferredDefaultProfileID()
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.aiSummaryProfileID)
            objectWillChange.send()
        }
    }
    
    var translationProfileID: UUID? {
        get {
            if let str = defaults.string(forKey: Keys.aiTranslationProfileID),
               let uuid = UUID(uuidString: str),
               profiles.contains(where: { $0.id == uuid }) {
                return uuid
            }
            return preferredDefaultProfileID()
        }
        set {
            defaults.set(newValue?.uuidString, forKey: Keys.aiTranslationProfileID)
            objectWillChange.send()
        }
    }
    
    init() {
        loadProfiles()
        ensureProfileSelections()
    }

    private func loadProfiles() {
        if let data = defaults.data(forKey: Keys.aiProfiles),
           let decoded = try? JSONDecoder().decode([AIProviderProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            // Migrate legacy settings if no profiles exist
            let legacyBaseURL = defaults.string(forKey: Keys.aiBaseURL) ?? "https://api.openai.com/v1"
            let legacyAPIKey = defaults.string(forKey: Keys.aiApiKey) ?? ""
            let legacyModel = defaults.string(forKey: Keys.aiModel) ?? "gpt-4o-mini"
            let legacyRateLimit = defaults.string(forKey: Keys.aiRateLimit) ?? "2/s"
            
            let defaultProfile = AIProviderProfile(
                name: "Default (OpenAI)",
                baseURL: legacyBaseURL.isEmpty ? "https://api.openai.com/v1" : legacyBaseURL,
                apiKey: legacyAPIKey,
                model: legacyModel.isEmpty ? "gpt-4o-mini" : legacyModel,
                rateLimit: legacyRateLimit
            )
            
            self.profiles = [defaultProfile]
            // We don't save immediately to avoid overwriting unless user modifies? 
            // Better to save so persistent.
            saveProfiles()
            
            // Set defaults
            self.summaryProfileID = defaultProfile.id
            self.translationProfileID = defaultProfile.id
        }
    }

    private func ensureProfileSelections() {
        guard !profiles.isEmpty else { return }

        let preferredID = preferredDefaultProfileID()

        if storedProfileID(forKey: Keys.aiSummaryProfileID) == nil {
            summaryProfileID = preferredID
        }

        if storedProfileID(forKey: Keys.aiTranslationProfileID) == nil {
            translationProfileID = preferredID
        }
    }

    private func storedProfileID(forKey key: String) -> UUID? {
        guard let stringValue = defaults.string(forKey: key), let uuid = UUID(uuidString: stringValue) else {
            return nil
        }
        guard profiles.contains(where: { $0.id == uuid }) else {
            return nil
        }
        return uuid
    }

    private func preferredDefaultProfileID() -> UUID? {
        if let openAIByURL = profiles.first(where: { $0.baseURL.lowercased().contains("openai.com") }) {
            return openAIByURL.id
        }

        if let openAIByName = profiles.first(where: { $0.name.lowercased().contains("openai") }) {
            return openAIByName.id
        }

        return profiles.first?.id
    }
    
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            defaults.set(encoded, forKey: Keys.aiProfiles)
        }
    }
    
    func addProfile(_ profile: AIProviderProfile) {
        profiles.append(profile)
    }
    
    func updateProfile(_ profile: AIProviderProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
    }
    
    func deleteProfile(at index: Int) {
        let profile = profiles[index]
        let removedID = profile.id

        let selectedSummaryID = storedProfileID(forKey: Keys.aiSummaryProfileID)
        let selectedTranslationID = storedProfileID(forKey: Keys.aiTranslationProfileID)

        profiles.remove(at: index)
        
        // Reset selection if deleted
        if selectedSummaryID == removedID { summaryProfileID = preferredDefaultProfileID() }
        if selectedTranslationID == removedID { translationProfileID = preferredDefaultProfileID() }
    }

    // MARK: - Usage Helpers
    
    func getProfile(for usage: AIUsage) -> AIProviderProfile? {
        // General usage might default to summary profile or just the first one
        let id: UUID?
        switch usage {
        case .summary: id = summaryProfileID
        case .translation: id = translationProfileID
        case .general: id = summaryProfileID ?? profiles.first?.id
        }
        
        guard let targetID = id else { return profiles.first }
        return profiles.first(where: { $0.id == targetID }) ?? profiles.first
    }
    
    // Provide direct accessors for backward compatibility or simple usage
    
    var baseURL: String { getProfile(for: .general)?.baseURL ?? "" }
    var apiKey: String { getProfile(for: .general)?.apiKey ?? "" }
    var model: String { getProfile(for: .general)?.model ?? "" }
    
    // Retrieve specifically for a context
    func baseURL(for usage: AIUsage) -> String { getProfile(for: usage)?.baseURL ?? "" }
    func apiKey(for usage: AIUsage) -> String { getProfile(for: usage)?.apiKey ?? "" }
    func model(for usage: AIUsage) -> String { getProfile(for: usage)?.model ?? "" }
    
    // MARK: - Other Settings

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

    var autoTranslateTitles: Bool {
        get { defaults.bool(forKey: Keys.aiAutoTranslateTitles) }
        set {
            defaults.set(newValue, forKey: Keys.aiAutoTranslateTitles)
            objectWillChange.send()
        }
    }

    var hoverTranslationEnabled: Bool {
        get { defaults.object(forKey: Keys.aiHoverTranslationEnabled) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Keys.aiHoverTranslationEnabled)
            objectWillChange.send()
        }
    }

    // Helper to get QPS as double from a specific profile or rate limit string
    func getQPS(for usage: AIUsage) -> Double {
        guard let profile = getProfile(for: usage) else { return 2.0 }
        return qps(from: profile.rateLimit)
    }
    
    private func qps(from string: String) -> Double {
        switch string {
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
4. Translate all text including headlines, titles, and headers.
5. Do NOT translate: URLs, Code blocks, or specific technical Variable Names.
6. Use Markdown for formatting (bold, italic, etc) if necessary.
""" }
        set {
            defaults.set(newValue, forKey: Keys.aiTranslationPrompt)
            objectWillChange.send()
        }
    }

    var translationIsRewriteMode: Bool {
        let language = outputLanguage.lowercased()
        if language.contains("simplified english") || language.contains("a2") || language.contains("a2-b1") {
            return true
        }

        let prompt = translationPrompt.lowercased()
        if language == "english" && (prompt.contains("simplified english") || prompt.contains("a2") || prompt.contains("a2-b1") || prompt.contains("english learning")) {
            return true
        }

        return false
    }
    
    func resetSummaryPrompt() {
        defaults.removeObject(forKey: Keys.aiSummaryPrompt)
        objectWillChange.send()
    }
    
    enum ModifierKey: String, CaseIterable, Identifiable {
        case control = "Control"
        case option = "Option"
        case command = "Command"
        
        var id: String { rawValue }
        
        // JS event property to check
        var jsProperty: String {
            switch self {
            case .control: return "ctrlKey"
            case .option: return "altKey"
            case .command: return "metaKey"
            }
        }
    }

    var hoverModifier: ModifierKey {
        get {
            let raw = defaults.string(forKey: Keys.aiHoverModifier) ?? "Control"
            return ModifierKey(rawValue: raw) ?? .control
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.aiHoverModifier)
            objectWillChange.send()
        }
    }
    
    func resetTranslationPrompt() {
        defaults.removeObject(forKey: Keys.aiTranslationPrompt)
        objectWillChange.send()
    }
}
