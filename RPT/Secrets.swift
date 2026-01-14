import Foundation

/// Access to development-only secrets. Do not ship provider keys in Release builds.
enum Secrets {
    /// Reads the AI API key from Info.plist key `AIAPIKey` in Debug builds.
    /// Configure via a Debug-only xcconfig: AI_API_KEY, then map Info.plist value to $(AI_API_KEY).
    static var aiAPIKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "AIAPIKey") as? String, !key.isEmpty {
            return key
        } else {
            // Return empty string in Debug if not configured (won't crash, just features disabled)
            return ""
        }
        #else
        // Never ship provider keys in Release builds.
        return ""
        #endif
    }

    /// Reads the API Ninjas key from Info.plist key `API_NINJAS_KEY` in Debug builds.
    static var apiNinjasKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "API_NINJAS_KEY") as? String, !key.isEmpty {
            return key
        } else {
            // Return empty string in Debug if not configured (won't crash, just features disabled)
            return ""
        }
        #else
        // Never ship provider keys in Release builds.
        return ""
        #endif
    }

    /// Reads the Wger API key from Info.plist key `Wger_API` in Debug builds.
    static var wgerAPIKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "Wger_API") as? String, !key.isEmpty {
            return key
        } else {
            return ""
        }
        #else
        return ""
        #endif
    }

    /// Reads the Chomp API key from Info.plist key `Chomp_API` in Debug builds.
    static var chompAPIKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "Chomp_API") as? String, !key.isEmpty {
            return key
        } else {
            return ""
        }
        #else
        return ""
        #endif
    }

    /// Reads the WeatherStack API key from Info.plist key `WeatherStack_API` in Debug builds.
    static var weatherstackAPIKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "WeatherStack_API") as? String, !key.isEmpty {
            return key
        } else {
            return ""
        }
        #else
        return ""
        #endif
    }

    /// Reads the OneSignal API key from Info.plist key `OneSignal_API` in Debug builds.
    static var oneSignalAPIKey: String {
        #if DEBUG
        if let key = Bundle.main.object(forInfoDictionaryKey: "OneSignal_API") as? String, !key.isEmpty {
            return key
        } else {
            return ""
        }
        #else
        return ""
        #endif
    }
}
