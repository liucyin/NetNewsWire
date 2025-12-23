
import Foundation

@MainActor
final class AICacheManager {
    static let shared = AICacheManager()
    
    private let defaults = UserDefaults.standard
    private let summaryKey = "AICache_Summaries"
    private let translationKey = "AICache_Translations"
    private let titleTranslationKey = "AICache_TitleTranslations"
    
    // In-memory cache for speed, backed by UserDefaults
    private var summaryCache: [String: String]
    private var translationCache: [String: [String: String]] // ArticleID -> [NodeID: TranslatedText]
    private var titleTranslationCache: [String: String] // ArticleID -> TranslatedTitle
    private var activeTitleTasks: [String: Task<String, Error>] = [:]
    
    private init() {
        self.summaryCache = defaults.dictionary(forKey: summaryKey) as? [String: String] ?? [:]
        
        // Complex objects need JSON decoding potentially, but [String: [String:String]] is plist compatible
        self.translationCache = defaults.dictionary(forKey: translationKey) as? [String: [String: String]] ?? [:]
        
        self.titleTranslationCache = defaults.dictionary(forKey: titleTranslationKey) as? [String: String] ?? [:]
    }
    
    // MARK: - Summary
    func getSummary(for articleID: String) -> String? {
        return summaryCache[articleID]
    }
    
    func saveSummary(_ text: String, for articleID: String) {
        summaryCache[articleID] = text
        defaults.set(summaryCache, forKey: summaryKey)
    }
    
    func clearSummaryCache() {
        summaryCache.removeAll()
        defaults.removeObject(forKey: summaryKey)
    }
    
    // MARK: - Title Translation
    func getTitleTranslation(for articleID: String) -> String? {
        return titleTranslationCache[articleID]
    }
    
    func fetchOrTranslateTitle(articleID: String, title: String, targetLang: String) async throws -> String {
        print("AICache: Fetching Title for \(articleID.prefix(8))...")
        // 1. Check persistent cache
        if let cached = getTitleTranslation(for: articleID) {
            print("AICache: Found cached title for \(articleID.prefix(8))")
            return cached
        }
        
        // 2. Check in-flight task
        if let existingTask = activeTitleTasks[articleID] {
            print("AICache: Joining inflight title task for \(articleID.prefix(8))")
            return try await existingTask.value
        }
        
        // 3. Create new task
        print("AICache: Starting new title task for \(articleID.prefix(8))")
        let task = Task.detached(priority: .userInitiated) {
            let translated = try await AIService.shared.translate(text: title, targetLanguage: targetLang)
            
            // Save to cache (MainActor isolated)
            await AICacheManager.shared.saveTitleTranslation(translated, for: articleID)
            
            print("AICache: Saved title for \(articleID.prefix(8))")
            return translated
        }
        
        activeTitleTasks[articleID] = task
        
        do {
            let result = try await task.value
            if activeTitleTasks[articleID] == task {
                activeTitleTasks[articleID] = nil
            }
            return result
        } catch {
            print("AICache: Title task failed for \(articleID.prefix(8)): \(error)")
            if activeTitleTasks[articleID] == task {
                activeTitleTasks[articleID] = nil
            }
            throw error
        }
    }
    
    func saveTitleTranslation(_ text: String, for articleID: String) {
        titleTranslationCache[articleID] = text
        defaults.set(titleTranslationCache, forKey: titleTranslationKey)
    }
    
    func clearTitleTranslationCache() {
        titleTranslationCache.removeAll()
        defaults.removeObject(forKey: titleTranslationKey)
    }
    
    // MARK: - Translation
    func getTranslation(for articleID: String) -> [String: String]? {
        return translationCache[articleID]
    }
    
    func saveTranslation(_ map: [String: String], for articleID: String) {
        // Merge with existing if needed, or overwrite? User said "re-click button regenerates", implying overwrite.
        // But since we might translate incrementally... let's just save the map provided.
        // Actually, if we translate incrementally, we might want to merge.
        // For simplicity: We will likely save the *accumulated* translations for the article.
        
        var existing = translationCache[articleID] ?? [:]
        for (k, v) in map {
            existing[k] = v
        }
        translationCache[articleID] = existing
        defaults.set(translationCache, forKey: translationKey)
    }
    
    func clearTranslationCache() {
        translationCache.removeAll()
        defaults.removeObject(forKey: translationKey)
    }
}
