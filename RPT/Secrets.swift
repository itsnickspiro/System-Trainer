import Foundation

/// Runtime access to API keys stored in Info.plist.
///
/// Keys are read from Info.plist at runtime so they are available in both
/// Debug and Release builds. Info.plist ships inside the app bundle, so these
/// keys are not truly secret from a determined extractor — before shipping to
/// the App Store, consider moving high-value keys behind a backend proxy.
enum Secrets {
    /// AI API key (unused in the current on-device FoundationModels integration,
    /// kept for any future cloud AI fallback).
    static var aiAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "AIAPIKey") as? String ?? ""
    }

    /// API Ninjas key — used by NutritionAPI for food/nutrition lookups.
    static var apiNinjasKey: String {
        Bundle.main.object(forInfoDictionaryKey: "API_NINJAS_KEY") as? String ?? ""
    }

    /// WeatherStack API key — used by WeatherstackAPI for weather data on HomeView.
    static var weatherstackAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "WeatherStack_API") as? String ?? ""
    }
}
