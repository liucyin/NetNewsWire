
import Foundation

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
