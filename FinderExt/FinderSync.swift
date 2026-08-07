import Cocoa
import FinderSync

/// Finder Sync extension: injects the "Peek" context-menu item and hands the
/// selected file off to the parent app via the peek:// URL scheme (ADR-002).
/// This process is sandboxed and short-lived — no API calls, no UI here.
class FinderSync: FIFinderSync {

    /// File extensions Peek understands (PRD §6.1). Keep in sync with
    /// SupportedFileType in the parent app.
    private static let supportedExtensions: Set<String> = [
        "txt", "md", "csv", "rtf", "pdf", "png", "jpg", "jpeg", "heic",
    ]

    override init() {
        super.init()
        // Monitor everything so the menu item appears in any folder (ADR-001).
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selection = FIFinderSyncController.default().selectedItemURLs(),
              selection.count == 1, // v1: single file only (PRD §4)
              let file = selection.first,
              Self.supportedExtensions.contains(file.pathExtension.lowercased())
        else { return nil }

        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: "Peek", action: #selector(peek(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Peek")
        menu.addItem(item)
        return menu
    }

    @objc private func peek(_ sender: AnyObject?) {
        guard let file = FIFinderSyncController.default().selectedItemURLs()?.first else { return }
        var comps = URLComponents()
        comps.scheme = "peek"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "file", value: file.path)]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}
