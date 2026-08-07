import Foundation

/// Anthropic Messages API adapter with SSE streaming.
/// Wire format: POST /v1/messages, x-api-key header, content blocks.
struct AnthropicProvider: AIProvider {
    let id = ProviderID.anthropic
    let apiKey: String
    var model = "claude-sonnet-4-20250514"

    var modelBadge: String { "Claude" }

    func stream(content: PromptContent, action: PeekAction) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var blocks: [[String: Any]] = []
                    for image in content.images {
                        blocks.append([
                            "type": "image",
                            "source": ["type": "base64", "media_type": image.mimeType, "data": image.base64],
                        ])
                    }
                    var userText = "File: \(content.fileName)"
                    if let text = content.text, !text.isEmpty {
                        userText += "\n\n\(text)"
                    }
                    blocks.append(["type": "text", "text": userText])

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 1024,
                        "stream": true,
                        "system": action.systemPrompt,
                        "messages": [["role": "user", "content": blocks]],
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
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              json["type"] as? String == "content_block_delta",
                              let delta = json["delta"] as? [String: Any],
                              let text = delta["text"] as? String
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
