import Foundation

enum TelegramConfig {
    private static let apiIdKey = "TELEGRAM_API_ID"
    private static let apiHashKey = "TELEGRAM_API_HASH"

    static var apiId: Int {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: apiIdKey) as? String,
            let apiId = Int(value),
            apiId > 0
        else {
            return 0
        }
        return apiId
    }

    static var apiHash: String {
        (Bundle.main.object(forInfoDictionaryKey: apiHashKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static let appVersion: String = "1.0"
    static let deviceModel: String = "iPhone"
    static let languageCode: String = "zh-Hans"

    static var isConfigured: Bool {
        apiId > 0 && !apiHash.isEmpty
    }
}

enum CloudflareConfig {
    private static let accountIdKey = "cloudflare_account_id"
    private static let apiTokenKey = "cloudflare_api_token"

    static var accountId: String {
        get { UserDefaults.standard.string(forKey: accountIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: accountIdKey) }
    }

    static var apiToken: String {
        get { UserDefaults.standard.string(forKey: apiTokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiTokenKey) }
    }

    static var isConfigured: Bool {
        !accountId.isEmpty && !apiToken.isEmpty
    }
}
