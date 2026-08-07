import Foundation

/// OpenAI Chat Completions adapter with SSE streaming.
/// Supports an optional baseURL override (PRD §4 amendment) so any
/// OpenAI-compatible endpoint (Ollama, gateways) works with zero UI cost.
struct OpenAIProvider: AIProvider {
    let id = ProviderID.openai
    let apiKey: String
    var model = "gpt-4o-mini"
    /// Override via Preferences.openAIBaseURL — hidden from primary UI.
    var baseURL = URL(string: "https://api.openai.com/v1")!

    var modelBadge: String { baseURL.host == "api.openai.com" ? "OpenAI" : "Custom" }

    func stream(content: PromptContent, action: PeekAction) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var parts: [[String: Any]] = []
                    var userText = "File: \(content.fileName)"
                    if let text = content.text, !text.isEmpty {
                        userText += "\n\n\(text)"
                    }
                    parts.append(["type": "text", "text": userText])
                    for image in content.images {
                        parts.append([
                            "type": "image_url",
                            "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"],
                        ])
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": action.systemPrompt],
                            ["role": "user", "content": parts],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line; if errBody.count > 500 { break } }
                        throw ProviderError.httpError(status: http.statusCode, body: errBody)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let text = delta["content"] as? String
                        else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
