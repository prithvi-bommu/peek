import Foundation

/// What kind of understanding the user wants (PRD §6.5).
enum PeekAction: String, CaseIterable, Codable {
    case summary, explanation, insights

    var displayName: String {
        switch self {
        case .summary: "Summary"
        case .explanation: "Explanation"
        case .insights: "Key Insights"
        }
    }

    /// Task-appropriate system prompt (PRD §6.3).
    var systemPrompt: String {
        switch self {
        case .summary:
            "You are Peek, a macOS utility. Summarize the provided file content concisely. Lead with the single most important point. Use short paragraphs or bullets. No preamble."
        case .explanation:
            "You are Peek, a macOS utility. Explain what the provided file content is and means, as if to a smart colleague unfamiliar with it. No preamble."
        case .insights:
            "You are Peek, a macOS utility. Extract the key insights from the provided file content as a short bulleted list, most important first. No preamble."
        }
    }
}

/// Content extracted from a file, ready to send to a provider.
/// Text and images are both optional so the PDF hybrid path (PRD §9)
/// can send either or both.
struct PromptContent {
    var fileName: String
    var text: String?
    /// (mimeType, base64Data) pairs — page rasters or the image file itself.
    var images: [(mimeType: String, base64: String)] = []

    var isEmpty: Bool { (text?.isEmpty ?? true) && images.isEmpty }
}

enum ProviderID: String, CaseIterable, Codable {
    case anthropic, openai

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        }
    }
}

enum ProviderError: LocalizedError {
    case missingAPIKey(ProviderID)
    case httpError(status: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            "No API key set for \(p.displayName). Add one in Peek's settings."
        case .httpError(let status, let body):
            "Provider returned HTTP \(status): \(body.prefix(200))"
        case .emptyResponse:
            "The provider returned an empty response."
        }
    }
}

/// A streaming AI provider. Implementations: AnthropicProvider, OpenAIProvider.
protocol AIProvider {
    var id: ProviderID { get }
    /// Human-readable model name for the panel's provider badge.
    var modelBadge: String { get }
    /// Stream the response for the given content + action, yielding text deltas.
    func stream(content: PromptContent, action: PeekAction) -> AsyncThrowingStream<String, Error>
}
