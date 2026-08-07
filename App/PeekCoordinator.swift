import AppKit
import UserNotifications

/// Orchestrates a Peek conversation: parse URL → load file → stream first
/// response → handle follow-up questions, maintaining turn history.
/// Popup mode drives the panel; silent mode goes clipboard+notification
/// (follow-ups are popup-only). Owned by the app; one panel reused.
@MainActor
final class PeekCoordinator {
    private let model = ResultViewModel()
    private lazy var panel = ResultPanel(model: model)
    private var streamTask: Task<Void, Never>?

    /// Conversation state for the current file.
    private var history: [ChatTurn] = []
    private var systemPrompt = ""
    private var lastRequest: (url: URL, action: PeekAction)?

    init() {
        model.onClose = { [weak self] in self?.dismiss() }
        model.onRetry = { [weak self] in
            guard let last = self?.lastRequest else { return }
            self?.run(fileURL: last.url, action: last.action)
        }
        model.onFollowUp = { [weak self] question in
            self?.followUp(question: question)
        }
    }

    /// Entry point for peek:// URLs (ADR-002).
    /// peek://open?file=/path/to/file&action=summary
    func handle(url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host == "open",
              let path = comps.queryItems?.first(where: { $0.name == "file" })?.value
        else { return }

        let action = comps.queryItems?
            .first(where: { $0.name == "action" })?.value
            .flatMap(PeekAction.init(rawValue:))
            ?? Preferences.shared.defaultAction

        let fileURL = URL(fileURLWithPath: path)
        // Validate before acting — any app can open peek:// URLs (ADR-002).
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        run(fileURL: fileURL, action: action)
    }

    /// Start a fresh conversation for a file.
    func run(fileURL: URL, action: PeekAction) {
        streamTask?.cancel()
        lastRequest = (fileURL, action)
        history = []
        systemPrompt = action.systemPrompt

        model.fileName = fileURL.lastPathComponent
        model.messages = []
        model.errorMessage = nil

        if !Preferences.shared.silentMode { panel.showNearCursor() }

        do {
            let content = try FileContentLoader.load(url: fileURL)
            var firstTurn = ChatTurn(role: .user, text: "File: \(content.fileName)")
            if let text = content.text, !text.isEmpty {
                firstTurn.text += "\n\n\(text)"
            }
            firstTurn.images = content.images
            history.append(firstTurn)
        } catch {
            present(error: error)
            return
        }
        streamNextAssistantTurn()
    }

    /// Append a follow-up question to the conversation (popup mode only).
    func followUp(question: String) {
        guard !model.isStreaming else { return }
        history.append(ChatTurn(role: .user, text: question))
        model.messages.append(DisplayMessage(role: .user, text: question))
        streamNextAssistantTurn()
    }

    /// Stream the assistant's next turn into the panel and history.
    private func streamNextAssistantTurn() {
        model.errorMessage = nil
        model.isStreaming = true
        let silent = Preferences.shared.silentMode

        streamTask = Task { [model] in
            do {
                let provider = try Preferences.shared.makeProvider()
                model.badge = provider.modelBadge

                model.messages.append(DisplayMessage(role: .assistant, text: ""))
                let index = model.messages.count - 1

                var full = ""
                for try await delta in provider.stream(system: systemPrompt, turns: history) {
                    if Task.isCancelled { return }
                    full += delta
                    model.messages[index].text = full
                }
                guard !full.isEmpty else { throw ProviderError.emptyResponse }
                history.append(ChatTurn(role: .assistant, text: full))
                model.isStreaming = false

                if silent, history.count <= 2 { // initial response only
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(full, forType: .string)
                    Self.notify(title: "Peek", body: "Result copied to clipboard.")
                }
            } catch {
                // Drop the empty placeholder message if streaming never started.
                if model.messages.last?.role == .assistant, model.messages.last?.text.isEmpty == true {
                    model.messages.removeLast()
                }
                self.present(error: error)
            }
        }
    }

    private func present(error: Error) {
        model.isStreaming = false
        if Preferences.shared.silentMode {
            Self.notify(title: "Peek failed", body: error.localizedDescription)
        } else {
            model.errorMessage = error.localizedDescription
        }
    }

    func dismiss() {
        streamTask?.cancel()
        panel.fadeOut()
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
