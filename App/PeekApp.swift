import SwiftUI

/// Peek — LSUIElement background app. Menu bar icon only, no Dock icon.
/// Receives peek:// URLs from the FinderSync extension and drives the
/// coordinator. Settings window hosts provider/key/mode preferences.
@main
struct PeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Peek", systemImage: "eye") {
            MenuBarContent()
        }
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var coordinator: PeekCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.coordinator = PeekCoordinator()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "peek" {
            Self.coordinator.handle(url: url)
        }
    }
}

struct MenuBarContent: View {
    var body: some View {
        Text("Right-click a file in Finder → Peek")
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Peek") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @State private var provider = Preferences.shared.provider
    @State private var defaultAction = Preferences.shared.defaultAction
    @State private var silentMode = Preferences.shared.silentMode
    @State private var apiKey = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $provider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: provider) { _, newValue in
                    Preferences.shared.provider = newValue
                    apiKey = ""
                    keySaved = KeychainStore.apiKey(for: newValue) != nil
                }
                SecureField("API Key", text: $apiKey, prompt: Text(keySaved ? "•••••••• (saved)" : "Paste your API key"))
                Button("Save Key") {
                    KeychainStore.setAPIKey(apiKey, for: provider)
                    apiKey = ""
                    keySaved = true
                }
                .disabled(apiKey.isEmpty)
            }
            Section("Behavior") {
                Picker("Default action", selection: $defaultAction) {
                    ForEach(PeekAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: defaultAction) { _, v in Preferences.shared.defaultAction = v }
                Toggle("Silent mode (copy to clipboard, no popup)", isOn: $silentMode)
                    .onChange(of: silentMode) { _, v in Preferences.shared.silentMode = v }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { keySaved = KeychainStore.apiKey(for: provider) != nil }
    }
}
