import Foundation

struct SupabaseConfiguration {
    enum ConfigurationError: LocalizedError {
        case missingFile
        case invalidFormat
        case invalidURL(String)
        case missingAnonKey
        case placeholderValue

        var errorDescription: String? {
            switch self {
            case .missingFile:
                return L10n.Auth.configurationMissingFile
            case .invalidFormat:
                return L10n.Auth.configurationInvalidFormat
            case .invalidURL(let value):
                return L10n.Auth.configurationInvalidURL(value)
            case .missingAnonKey:
                return L10n.Auth.configurationMissingAnonKey
            case .placeholderValue:
                return L10n.Auth.configurationPlaceholder
            }
        }
    }

    let url: URL
    let anonKey: String

    static func loadFromBundle() throws -> SupabaseConfiguration {
        guard let resourceURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist") else {
            throw ConfigurationError.missingFile
        }

        let data = try Data(contentsOf: resourceURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        guard let dictionary = plist as? [String: Any] else {
            throw ConfigurationError.invalidFormat
        }

        guard let rawURL = dictionary["url"] as? String else {
            throw ConfigurationError.invalidURL("<missing>")
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let supabaseURL = URL(string: trimmedURL), supabaseURL.scheme?.hasPrefix("http") == true else {
            throw ConfigurationError.invalidURL(trimmedURL)
        }

        guard let anonKey = dictionary["anonKey"] as? String else {
            throw ConfigurationError.missingAnonKey
        }

        let trimmedAnonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedAnonKey.isEmpty == false else {
            throw ConfigurationError.missingAnonKey
        }

        if trimmedURL.contains("YOUR_SUPABASE") || trimmedAnonKey.contains("YOUR_SUPABASE") {
            throw ConfigurationError.placeholderValue
        }

        return SupabaseConfiguration(url: supabaseURL, anonKey: trimmedAnonKey)
    }
}
