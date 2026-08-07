import AppKit
import UserNotifications

/// Orchestrates one Peek request: parse URL → load file → stream from
/// provider → drive the panel (popup mode) or clipboard+notification
/// (silent mode). Owned by the app; one panel reused across requests.
@MainActor
final class PeekCoordinator {
    private let model = ResultViewModel()
    private lazy var panel = ResultPanel(model: model)
    private var streamTask: Task<Void, Never>?
    private var lastRequest: (url: URL, action: PeekAction)?

    init() {
        model.onClose = { [weak self] in self?.dismiss() }
        model.onRetry = { [weak self] in
            guard let last = self?.lastRequest else { return }
            self?.run(fileURL: last.url, action: last.action)
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

    func run(fileURL: URL, action: PeekAction) {
        streamTask?.cancel()
        lastRequest = (fileURL, action)
        let silent = Preferences.shared.silentMode

        model.fileName = fileURL.lastPathComponent
        model.text = ""
        model.errorMessage = nil
        model.isStreaming = true

        if !silent { panel.showNearCursor() }

        streamTask = Task { [model] in
            do {
                let provider = try Preferences.shared.makeProvider()
                model.badge = provider.modelBadge
                let content = try FileContentLoader.load(url: fileURL)
                var full = ""
                for try await delta in provider.stream(content: content, action: action) {
                    if Task.isCancelled { return }
                    full += delta
                    model.text = full
                }
                guard !full.isEmpty else { throw ProviderError.emptyResponse }
                model.isStreaming = false
                if silent {
                    // Silent mode: clipboard IS the output channel (PRD §6.3).
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(full, forType: .string)
                    Self.notify(title: "Peek", body: "Result copied to clipboard.")
                }
            } catch {
                model.isStreaming = false
                if silent {
                    Self.notify(title: "Peek failed", body: error.localizedDescription)
                } else {
                    model.errorMessage = error.localizedDescription
                }
            }
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
