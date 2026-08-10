import AppKit

/// Brings this accessory app's Settings window to the front reliably.
///
/// Peek has no Dock icon (LSUIElement), and macOS's cooperative activation
/// (macOS 14+) routinely declines `NSApplication.activate()` requests from
/// accessory apps — the Settings window then opens BEHIND the frontmost app.
/// This pairs a forceful activation with an explicit order-front of the
/// Settings window, retrying briefly because SwiftUI creates scene windows
/// asynchronously after `SettingsLink` fires.
///
/// Ported from uttr's WindowFocus (same bug class, verified on macOS 26).
@MainActor
enum WindowFocus {
    /// Substrings identifying the SwiftUI Settings scene window across OS
    /// versions (the identifier is private-API shaped, so match loosely).
    private static let settingsMarkers = ["settings", "preferences"]

    static func focusSettingsWindow() {
        // The non-deprecated activate() is exactly the call cooperative
        // activation ignores for accessory apps; ignoringOtherApps is
        // deprecated on macOS 14+ but remains the only reliable way to
        // take focus from a status-item context.
        NSApp.activate(ignoringOtherApps: true)
        attemptOrderFront(retries: 20)
    }

    static func identifierMatches(_ identifier: String?, marker: String) -> Bool {
        guard let identifier else { return false }
        return identifier.lowercased().contains(marker.lowercased())
    }

    private static func attemptOrderFront(retries: Int) {
        let window = NSApp.windows.first { window in
            settingsMarkers.contains {
                identifierMatches(window.identifier?.rawValue, marker: $0)
            }
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            attemptOrderFront(retries: retries - 1)
        }
    }
}
