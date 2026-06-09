import Foundation

/// Server upload configuration, read from the gitignored Secrets.xcconfig via Info.plist.
public struct UploaderConfig: Equatable {
    public let baseURL: URL
    public let apiKey: String
    public init(baseURL: URL, apiKey: String) { self.baseURL = baseURL; self.apiKey = apiKey }
}

struct ServerConfigurationSnapshot: Equatable {
    let baseURL: String?
    let apiKey: String?
    let isBaseURLConfigured: Bool
    let isAPIKeyConfigured: Bool
    let uploaderConfig: UploaderConfig?

    var isFullyConfigured: Bool {
        isBaseURLConfigured && isAPIKeyConfigured && uploaderConfig != nil
    }
}

enum AppConfig {
    /// The device id this build reads/writes under. Read from the gitignored
    /// Secrets.xcconfig (WHOOP_DEVICE_ID) so a personal build can point at its own
    /// history without committing the real id; falls back to "my-whoop".
    static var deviceId: String {
        let v = plistString("WHOOP_DEVICE_ID")
        if let v, !v.isEmpty, v != "$(WHOOP_DEVICE_ID)" { return v }
        return "my-whoop"
    }

    /// Returns nil when unconfigured (missing/placeholder), so the app simply doesn't upload.
    static func uploaderConfig(deviceId: String) -> UploaderConfig? {
        serverConfigurationSnapshot(deviceId: deviceId).uploaderConfig
    }

    static func serverConfigurationSnapshot(deviceId: String = AppConfig.deviceId) -> ServerConfigurationSnapshot {
        let urlStr = plistString("WHOOP_BASE_URL")
        let apiKey = plistString("WHOOP_API_KEY")
        let baseURLConfigured = isConfigured(urlStr, placeholder: "https://whoop.example.com")
        let apiKeyConfigured = isConfigured(apiKey, placeholder: "replace-me")
        let config: UploaderConfig?
        if
            baseURLConfigured,
            apiKeyConfigured,
            let urlStr,
            let apiKey,
            let url = URL(string: urlStr)
        {
            config = UploaderConfig(baseURL: url, apiKey: apiKey)
        } else {
            config = nil
        }
        return ServerConfigurationSnapshot(
            baseURL: urlStr,
            apiKey: apiKey,
            isBaseURLConfigured: baseURLConfigured,
            isAPIKeyConfigured: apiKeyConfigured,
            uploaderConfig: config
        )
    }

    private static func plistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func isConfigured(_ value: String?, placeholder: String) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value != placeholder && !value.hasPrefix("$(")
    }
}
