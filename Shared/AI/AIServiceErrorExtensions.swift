
import Foundation

// Improved Error Handling
extension AIServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString("Invalid URL configuration.", comment: "AI Error")
        case .noAPIKey:
            return NSLocalizedString("No API Key provided. Please check settings.", comment: "AI Error")
        case .networkError(let error):
            return NSLocalizedString("Network Error: \(error.localizedDescription)", comment: "AI Error")
        case .apiError(let message):
            return NSLocalizedString("API Error: \(message). Check your API Key and Base URL.", comment: "AI Error")
        case .decodingError(let error):
            return NSLocalizedString("Failed to decode response: \(error.localizedDescription)", comment: "AI Error")
        case .invalidResponse:
            return NSLocalizedString("Invalid response from server.", comment: "AI Error")
        }
    }
}
