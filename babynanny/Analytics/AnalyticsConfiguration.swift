import Foundation

/// Defines the runtime configuration needed to send analytics events to PostHog.
struct AnalyticsConfiguration {
    enum ConfigurationError: LocalizedError {
        case missingFile
        case invalidFormat
        case missingAPIKey
        case missingHost
        case invalidHost(String)
        case placeholderValue

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return "Analytics configuration file is missing."
            case .invalidFormat:
                return "Analytics configuration is not a valid plist dictionary."
            case .missingAPIKey:
                return "Analytics API key is missing."
            case .missingHost:
                return "Analytics host is missing."
            case .invalidHost(let value):
                return "Analytics host is invalid: \(value)."
            case .placeholderValue:
                return "Analytics configuration still contains placeholder values."
            }
        }
    }

    let apiKey: String
    let host: String
    let autocapture: Bool

    static func loadFromBundle() throws -> AnalyticsConfiguration {
        guard let resourceURL = Bundle.main.url(forResource: "PostHogConfig", withExtension: "plist") else {
            throw ConfigurationError.missingFile
        }

        let data = try Data(contentsOf: resourceURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dictionary = plist as? [String: Any] else {
            throw ConfigurationError.invalidFormat
        }

        guard let rawAPIKey = dictionary["apiKey"] as? String else {
            throw ConfigurationError.missingAPIKey
        }

        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else {
            throw ConfigurationError.missingAPIKey
        }

        guard let rawHost = dictionary["host"] as? String else {
            throw ConfigurationError.missingHost
        }

        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.hasPrefix("http") else {
            throw ConfigurationError.invalidHost(host)
        }

        if apiKey.contains("YOUR_POSTHOG") || host.contains("YOUR_POSTHOG") {
            throw ConfigurationError.placeholderValue
        }

        let autocapture = dictionary["autocapture"] as? Bool ?? true

        return AnalyticsConfiguration(apiKey: apiKey, host: host, autocapture: autocapture)
    }
}
