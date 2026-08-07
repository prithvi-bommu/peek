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

    /// Task-appropriate system prompt (PRD §6.3). Follow-up questions reuse
    /// the same system prompt so the model stays in "Peek" persona.
    var systemPrompt: String {
        switch self {
        case .summary:
            "You are Peek, a macOS utility. Summarize the provided file content concisely. Lead with the single most important point. Use short paragraphs or bullets. No preamble. Answer any follow-up questions about the file directly and briefly."
        case .explanation:
            "You are Peek, a macOS utility. Explain what the provided file content is and means, as if to a smart colleague unfamiliar with it. No preamble. Answer any follow-up questions about the file directly and briefly."
        case .insights:
            "You are Peek, a macOS utility. Extract the key insights from the provided file content as a short bulleted list, most important first. No preamble. Answer any follow-up questions about the file directly and briefly."
        }
    }
}

/// Content extracted from a file, ready to send to a provider.
struct PromptContent {
    var fileName: String
    var text: String?
    /// (mimeType, base64Data) pairs — page rasters or the image file itself.
    var images: [(mimeType: String, base64: String)] = []

    var isEmpty: Bool { (text?.isEmpty ?? true) && images.isEmpty }
}

/// One turn of a conversation. The first user turn carries the file content
/// (text + images); follow-up turns are plain text.
struct ChatTurn {
    enum Role: String { case user, assistant }
    var role: Role
    var text: String
    var images: [(mimeType: String, base64: String)] = []
}

enum ProviderID: String, CaseIterable, Codable {
    case anthropic, openai, cli

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic (Claude)"
        case .openai: "OpenAI"
        case .cli: "Local command-line tool"
        }
    }

    /// CLI provider needs a command, not an API key.
    var needsAPIKey: Bool { self != .cli }
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

/// A streaming, multi-turn AI provider.
/// Implementations: AnthropicProvider, OpenAIProvider, CLIProvider.
protocol AIProvider {
    var id: ProviderID { get }
    /// Human-readable name for the panel's provider badge.
    var modelBadge: String { get }
    /// Stream the assistant's next response given the conversation so far.
    func stream(system: String, turns: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}
