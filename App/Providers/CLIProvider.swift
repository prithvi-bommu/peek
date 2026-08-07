import Foundation

/// Runs a local command-line tool as the AI backend. The conversation is
/// flattened into a single prompt written to the tool's stdin; stdout is
/// streamed into the panel as it arrives.
///
/// Works with any executable that reads stdin and writes a response to stdout
/// (e.g. `llm`, an `ollama run` wrapper, or a custom script). The command is
/// user-configured in Settings and must be an **absolute path** — GUI apps
/// launch with a minimal PATH, so bare command names won't resolve.
///
/// Text-only: image files (and scanned-PDF page rasters) can't be sent to a
/// stdin/stdout tool, so those produce a clear error instead. Each turn spawns
/// a fresh process (stateless), so follow-ups re-send the whole transcript.
struct CLIProvider: AIProvider {
    let id = ProviderID.cli
    /// Full command line, e.g. "/usr/local/bin/llm -m gpt-4o-mini".
    /// Split on spaces; the first token is the executable path.
    let command: String

    var modelBadge: String { "CLI" }

    enum CLIError: LocalizedError {
        case emptyCommand
        case notAbsolutePath(String)
        case executableNotFound(String)
        case imagesUnsupported
        case nonZeroExit(Int32, stderr: String)

        var errorDescription: String? {
            switch self {
            case .emptyCommand:
                "No command configured. Set one in Peek's settings (e.g. /usr/local/bin/llm)."
            case .notAbsolutePath(let cmd):
                "Command must be an absolute path (got “\(cmd)”). GUI apps have a minimal PATH."
            case .executableNotFound(let path):
                "No executable at \(path)."
            case .imagesUnsupported:
                "The command-line provider is text-only — images and scanned PDFs need Anthropic or OpenAI."
            case .nonZeroExit(let code, let stderr):
                "Command failed (exit \(code)). \(stderr.prefix(200))"
            }
        }
    }

    func stream(system: String, turns: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard turns.allSatisfy({ $0.images.isEmpty }) else {
                        throw CLIError.imagesUnsupported
                    }
                    let parts = command.split(separator: " ").map(String.init)
                    guard let exe = parts.first, !exe.isEmpty else { throw CLIError.emptyCommand }
                    guard exe.hasPrefix("/") else { throw CLIError.notAbsolutePath(exe) }
                    guard FileManager.default.isExecutableFile(atPath: exe) else {
                        throw CLIError.executableNotFound(exe)
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: exe)
                    process.arguments = Array(parts.dropFirst())

                    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr

                    try process.run()

                    // Flatten the conversation into one prompt (stateless tool).
                    var prompt = system + "\n"
                    for turn in turns {
                        switch turn.role {
                        case .user: prompt += "\nUser:\n\(turn.text)\n"
                        case .assistant: prompt += "\nAssistant:\n\(turn.text)\n"
                        }
                    }
                    prompt += "\nAssistant:\n"

                    stdin.fileHandleForWriting.write(Data(prompt.utf8))
                    stdin.fileHandleForWriting.closeFile()

                    // Stream stdout chunks as they arrive, buffering bytes
                    // until they form valid UTF-8.
                    var buffer = Data()
                    var sawOutput = false
                    for try await byte in stdout.fileHandleForReading.bytes {
                        if Task.isCancelled { process.terminate(); return }
                        buffer.append(byte)
                        if let s = String(data: buffer, encoding: .utf8) {
                            sawOutput = sawOutput || !s.isEmpty
                            continuation.yield(s)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                        throw CLIError.nonZeroExit(
                            process.terminationStatus,
                            stderr: String(data: errData, encoding: .utf8) ?? "")
                    }
                    guard sawOutput else { throw ProviderError.emptyResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
