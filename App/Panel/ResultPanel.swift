import AppKit
import SwiftUI

/// Observable state for one Peek request, driven by PeekCoordinator.
@MainActor
final class ResultViewModel: ObservableObject {
    @Published var fileName = ""
    @Published var badge = ""
    @Published var text = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?
}

/// The floating result panel (PRD §6.4): non-activating, frosted glass,
/// appears near the cursor, dismissed by Esc / click-outside / close control.
@MainActor
final class ResultPanel: NSPanel {
    private let model: ResultViewModel

    init(model: ResultViewModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
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

/// SwiftUI content for the panel.
struct ResultView: View {
    @ObservedObject var model: ResultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider().opacity(0.4)
            if let error = model.errorMessage {
                errorState(error)
            } else {
                responseBody
            }
        }
        .padding(14)
        .frame(width: 420, height: 320, alignment: .topLeading)
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
            .help("Copy response")
            .disabled(model.text.isEmpty)
            Button { model.onClose?() } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .foregroundStyle(.secondary)
    }

    private var responseBody: some View {
        ScrollView {
            HStack(alignment: .bottom, spacing: 4) {
                Text(model.text.isEmpty && model.isStreaming ? "Thinking…" : model.text)
                    .font(.system(.body, design: .rounded))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.isStreaming && !model.text.isEmpty {
                    Circle().fill(.secondary).frame(width: 6, height: 6)
                        .padding(.bottom, 4)
                }
            }
        }
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
        NSPasteboard.general.setString(model.text, forType: .string)
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
