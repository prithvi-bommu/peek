import Foundation

/// OpenAI Chat Completions adapter with SSE streaming and multi-turn support.
/// Supports an optional baseURL override so any OpenAI-compatible endpoint
/// (Ollama, gateways) works with zero UI cost.
struct OpenAIProvider: AIProvider {
    let id = ProviderID.openai
    let apiKey: String
    var model = "gpt-4o-mini"
    /// Override via Preferences.openAIBaseURL — hidden from primary UI.
    var baseURL = URL(string: "https://api.openai.com/v1")!

    var modelBadge: String { baseURL.host == "api.openai.com" ? "OpenAI" : "Custom" }

    func stream(system: String, turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var messages: [[String: Any]] = [["role": "system", "content": system]]
                    for turn in turns {
                        if turn.images.isEmpty {
                            messages.append(["role": turn.role.rawValue, "content": turn.text])
                        } else {
                            var parts: [[String: Any]] = [["type": "text", "text": turn.text]]
                            for image in turn.images {
                                parts.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:\(image.mimeType);base64,\(image.base64)"],
                                ])
                            }
                            messages.append(["role": turn.role.rawValue, "content": parts])
                        }
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages,
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
