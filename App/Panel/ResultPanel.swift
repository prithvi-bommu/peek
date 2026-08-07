import AppKit
import SwiftUI

/// One message in the panel's transcript.
struct DisplayMessage: Identifiable, Equatable {
    let id = UUID()
    var role: ChatTurn.Role
    var text: String
}

/// Observable state for one Peek conversation, driven by PeekCoordinator.
@MainActor
final class ResultViewModel: ObservableObject {
    @Published var fileName = ""
    @Published var badge = ""
    @Published var messages: [DisplayMessage] = []
    @Published var isStreaming = false
    @Published var errorMessage: String?
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?
    var onFollowUp: ((String) -> Void)?

    /// The most recent assistant text (for the Copy button).
    var lastAssistantText: String {
        messages.last(where: { $0.role == .assistant })?.text ?? ""
    }
}

/// The floating result panel (PRD §6.4): non-activating, frosted glass,
/// appears near the cursor, dismissed by Esc / close control.
@MainActor
final class ResultPanel: NSPanel {
    private let model: ResultViewModel

    init(model: ResultViewModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false

        let host = NSHostingView(rootView: ResultView(model: model))
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    /// Show near the current mouse location, clamped to the screen.
    func showNearCursor() {
        let mouse = NSEvent.mouseLocation
        let size = frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            origin.x = min(max(origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - size.height)
        }
        setFrameOrigin(origin)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: { self.orderOut(nil) })
    }

    override func cancelOperation(_ sender: Any?) { // Esc
        model.onClose?()
    }
}

/// SwiftUI content for the panel: header, transcript, follow-up input.
struct ResultView: View {
    @ObservedObject var model: ResultViewModel
    @State private var followUpText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().opacity(0.4)
            if let error = model.errorMessage {
                errorState(error)
            } else {
                transcript
                followUpBar
            }
        }
        .padding(14)
        .frame(width: 440, height: 380, alignment: .topLeading)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye").font(.system(size: 12, weight: .semibold))
            Text(model.fileName).font(.system(.caption, design: .rounded).weight(.semibold))
                .lineLimit(1)
            Spacer()
            if !model.badge.isEmpty {
                Text(model.badge)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.2)))
            }
            Button { copyToClipboard() } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy last response")
            .disabled(model.lastAssistantText.isEmpty)
            Button { model.onClose?() } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .foregroundStyle(.secondary)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { message in
                        messageView(message)
                    }
                    if model.isStreaming && model.messages.last?.text.isEmpty != false {
                        Text("Thinking…")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.messages) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: DisplayMessage) -> some View {
        if message.role == .user {
            Text(message.text)
                .font(.system(.callout, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.secondary.opacity(0.15)))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Text(message.text)
                .font(.system(.body, design: .rounded))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var followUpBar: some View {
        HStack(spacing: 6) {
            TextField("Ask a follow-up…", text: $followUpText)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .rounded))
                .focused($inputFocused)
                .onSubmit(sendFollowUp)
                .disabled(model.isStreaming)
            Button(action: sendFollowUp) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(followUpText.trimmingCharacters(in: .whitespaces).isEmpty || model.isStreaming)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.12))
        )
    }

    private func sendFollowUp() {
        let question = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isStreaming else { return }
        followUpText = ""
        model.onFollowUp?(question)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22)).foregroundStyle(.orange)
            Text(message)
                .font(.system(.callout, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") { model.onRetry?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.lastAssistantText, forType: .string)
    }
}

/// HUD-material frosted glass background (PRD §7).
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
