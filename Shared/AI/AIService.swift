
import Foundation

enum AIServiceError: Error {
    case invalidURL
    case noAPIKey
    case networkError(Error)
    case apiError(String)
    case decodingError(Error)
    case invalidResponse
}

actor AIService {
    static let shared = AIService()
    private let settings = AISettings.shared
    
    // Simple session
    private let session = URLSession.shared
    
    private init() {}
    
    func summarize(text: String) async throws -> String {
        let summaryPrompt = await settings.summaryPrompt
        let prompt = "\(summaryPrompt)\n\n<article_content>\n\(text)\n</article_content>"
        return try await performChatRequest(systemPrompt: "You are a helpful assistant that summarizes articles.", userPrompt: prompt, usage: .summary)
    }
    
    func translate(text: String, targetLanguage: String) async throws -> String {
        var promptTemplate = await settings.translationPrompt
        promptTemplate = promptTemplate.replacingOccurrences(of: "%TARGET_LANGUAGE%", with: targetLanguage)
        let prompt = "\(promptTemplate)\n\n<text_to_translate>\n\(text)\n</text_to_translate>"
        return try await performChatRequest(systemPrompt: "You are a helpful assistant that translates articles.", userPrompt: prompt, usage: .translation)
    }
    
    func testConnection() async throws -> String {
        let prompt = "Ping"
        return try await performChatRequest(systemPrompt: "You are a helpful assistant.", userPrompt: prompt, usage: .general)
    }
    
    private func performChatRequest(systemPrompt: String, userPrompt: String, usage: AISettings.AIUsage) async throws -> String {
        let apiKey = await settings.apiKey(for: usage)
        guard !apiKey.isEmpty else {
            throw AIServiceError.noAPIKey
        }
        
        // Fetch Base URL based on usage (Summary/Translation/General)
        let baseURLStr = await settings.baseURL(for: usage)
        
        // Ensure URL ends with /v1/chat/completions (generic OpenAI compatible)
        // If user enters "https://api.openai.com/v1", we want "https://api.openai.com/v1/chat/completions"
        // If user enters "https://api.openai.com/v1/", we want "https://api.openai.com/v1/chat/completions"
        // If user enters completely different URL, we assume they know what they are doing if it looks complete, 
        // but typically standard implementations accept a Base URL.
        
        var urlString = baseURLStr
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        if !urlString.hasSuffix("/chat/completions") {
             urlString += "/chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Fetch Model based on usage
        let profileModel = await settings.model(for: usage)
        let model = profileModel.isEmpty ? "gpt-4o-mini" : profileModel
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AIServiceError.decodingError(error)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIServiceError.apiError("Status \(httpResponse.statusCode): \(message)")
            }
            throw AIServiceError.apiError("Status \(httpResponse.statusCode)")
        }
        
        // Parse response
        // OpenAI Response structure:
        // { "choices": [ { "message": { "content": "..." } } ] }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AIServiceError.invalidResponse
            }
            
            // Clean content of XML tags we might have injected
            // Sometimes models echo the tags back
            var cleanedInfo = content
            cleanedInfo = cleanedInfo.replacingOccurrences(of: "<text_to_translate>", with: "")
            cleanedInfo = cleanedInfo.replacingOccurrences(of: "</text_to_translate>", with: "")
            cleanedInfo = cleanedInfo.replacingOccurrences(of: "<article_content>", with: "")
            cleanedInfo = cleanedInfo.replacingOccurrences(of: "</article_content>", with: "")
            cleanedInfo = cleanedInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return cleanedInfo
        } catch {
            throw AIServiceError.decodingError(error)
        }
    }
}
