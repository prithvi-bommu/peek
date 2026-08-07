import Foundation
import Security

/// Keychain-backed API key storage (ADR-003). Keys never touch disk in plaintext.
enum KeychainStore {
    private static let service = "dev.pbommu.peek"

    static func apiKey(for provider: ProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String, for provider: ProviderID) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return true } // empty = delete
        var add = base
        add[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// Non-secret preferences (PRD §6.5), UserDefaults-backed.
struct Preferences {
    static var shared = Preferences()
    private let d = UserDefaults.standard

    var provider: ProviderID {
        get { ProviderID(rawValue: d.string(forKey: "provider") ?? "") ?? .anthropic }
        set { d.set(newValue.rawValue, forKey: "provider") }
    }

    var defaultAction: PeekAction {
        get { PeekAction(rawValue: d.string(forKey: "defaultAction") ?? "") ?? .summary }
        set { d.set(newValue.rawValue, forKey: "defaultAction") }
    }

    /// Popup mode (default) vs silent mode (clipboard-only, PRD §6.3 amendment).
    var silentMode: Bool {
        get { d.bool(forKey: "silentMode") }
        set { d.set(newValue, forKey: "silentMode") }
    }

    /// Hidden override for OpenAI-compatible endpoints (ADR in PRD §4).
    /// Set via: defaults write dev.pbommu.peek openAIBaseURL http://localhost:11434/v1
    var openAIBaseURL: URL? {
        get { d.string(forKey: "openAIBaseURL").flatMap(URL.init(string:)) }
        set { d.set(newValue?.absoluteString, forKey: "openAIBaseURL") }
    }

    /// Build the active provider from preferences + Keychain.
    func makeProvider() throws -> AIProvider {
        guard let key = KeychainStore.apiKey(for: provider), !key.isEmpty else {
            throw ProviderError.missingAPIKey(provider)
        }
        switch provider {
        case .anthropic:
            return AnthropicProvider(apiKey: key)
        case .openai:
            var p = OpenAIProvider(apiKey: key)
            if let base = openAIBaseURL { p.baseURL = base }
            return p
        }
    }
}
