import Foundation
import CoreLocation
import Combine
import SwiftUI

/// Weatherstack API Client
/// Provides current weather data and forecasts
/// API Docs: https://weatherstack.com/documentation
@MainActor
class WeatherstackAPI: ObservableObject {
    static let shared = WeatherstackAPI()

    @Published var isLoading = false
    @Published var error: WeatherstackError?
    @Published var currentWeather: WeatherData?

    private init() {}

    // MARK: - Private proxy call

    private func fetchWeather(query: String) async throws -> WeatherData {
        guard let url = URL(string: "\(Secrets.supabaseURL)/functions/v1/weather-proxy") else {
            throw WeatherstackError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.appSecret, forHTTPHeaderField: "X-App-Secret")
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(["query": query])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherstackError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw WeatherstackError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(WeatherResponse.self, from: data)

        if let error = result.error {
            throw WeatherstackError.apiError(message: error.info ?? "Unknown error")
        }

        guard let weather = result.current, let location = result.location else {
            throw WeatherstackError.invalidData
        }

        return WeatherData(
            location: location.name,
            region: location.region,
            country: location.country,
            temperature: weather.temperature,
            feelsLike: weather.feelslike,
            weatherDescription: weather.weatherDescriptions.first ?? "Unknown",
            weatherIcon: weather.weatherIcons.first,
            windSpeed: weather.windSpeed,
            humidity: weather.humidity,
            uvIndex: weather.uvIndex,
            visibility: weather.visibility,
            precipitation: weather.precip,
            cloudCover: weather.cloudcover,
            observationTime: weather.observationTime
        )
    }

    // MARK: - Current Weather

    /// Fetch current weather by city name
    func fetchCurrentWeather(city: String) async throws -> WeatherData {
        try await fetchWeather(query: city)
    }

    /// Fetch current weather by coordinates
    func fetchCurrentWeather(latitude: Double, longitude: Double) async throws -> WeatherData {
        try await fetchWeather(query: "\(latitude),\(longitude)")
    }

    // MARK: - Workout Suggestions

    /// Get workout recommendation based on current weather
    func getWorkoutSuggestion(for weather: WeatherData) -> WorkoutSuggestion {
        let rc = RemoteConfigService.shared
        let maxTempF    = rc.int("weather_outdoor_max_temp_f",    default: 90)
        let minTempF    = rc.int("weather_outdoor_min_temp_f",    default: 32)
        let uvThreshold = rc.int("weather_high_uv_threshold",     default: 7)
        let idealTempLo = rc.int("weather_ideal_temp_low_f",      default: 60)
        let idealTempHi = rc.int("weather_ideal_temp_high_f",     default: 80)

        // Rain or snow
        if weather.precipitation > 0 {
            return WorkoutSuggestion(
                type: "Indoor",
                suggestion: "Rainy conditions - try an indoor workout",
                icon: "cloud.rain.fill",
                color: .blue
            )
        }

        // Too hot
        if weather.temperature > maxTempF {
            return WorkoutSuggestion(
                type: "Indoor",
                suggestion: "Very hot outside (\(weather.temperature)°F) - stay indoors",
                icon: "sun.max.fill",
                color: .orange
            )
        }

        // Too cold
        if weather.temperature < minTempF {
            return WorkoutSuggestion(
                type: "Indoor",
                suggestion: "Freezing conditions (\(weather.temperature)°F) - indoor workout recommended",
                icon: "snowflake",
                color: .cyan
            )
        }

        // High UV
        if weather.uvIndex > uvThreshold {
            return WorkoutSuggestion(
                type: "Morning/Evening",
                suggestion: "High UV index (\(weather.uvIndex)) - workout early morning or evening",
                icon: "sun.max.fill",
                color: .red
            )
        }

        // Perfect conditions
        if weather.temperature >= idealTempLo && weather.temperature <= idealTempHi {
            return WorkoutSuggestion(
                type: "Outdoor",
                suggestion: "Perfect weather (\(weather.temperature)°F) - great for outdoor exercise!",
                icon: "figure.run",
                color: .green
            )
        }

        // Default
        return WorkoutSuggestion(
            type: "Flexible",
            suggestion: "Current temp: \(weather.temperature)°F - dress appropriately",
            icon: "thermometer.medium",
            color: .gray
        )
    }
}

// MARK: - Models

struct WeatherData: Identifiable {
    let id = UUID()
    let location: String
    let region: String?
    let country: String
    let temperature: Int
    let feelsLike: Int
    let weatherDescription: String
    let weatherIcon: String?
    let windSpeed: Int
    let humidity: Int
    let uvIndex: Int
    let visibility: Int
    let precipitation: Double
    let cloudCover: Int
    let observationTime: String
}

struct WorkoutSuggestion {
    let type: String
    let suggestion: String
    let icon: String
    let color: Color
}

// API Response Models
struct WeatherResponse: Codable {
    let request: RequestInfo?
    let location: LocationInfo?
    let current: CurrentWeather?
    let error: WeatherAPIError?
}

struct RequestInfo: Codable {
    let type: String
    let query: String
    let language: String
    let unit: String
}

struct LocationInfo: Codable {
    let name: String
    let country: String
    let region: String?
    let lat: String
    let lon: String
    let timezoneId: String
    let localtime: String
    let localtimeEpoch: Int
    let utcOffset: String
}

struct CurrentWeather: Codable {
    let observationTime: String
    let temperature: Int
    let weatherCode: Int
    let weatherIcons: [String]
    let weatherDescriptions: [String]
    let windSpeed: Int
    let windDegree: Int
    let windDir: String
    let pressure: Int
    let precip: Double
    let humidity: Int
    let cloudcover: Int
    let feelslike: Int
    let uvIndex: Int
    let visibility: Int
}

struct WeatherAPIError: Codable {
    let code: Int?
    let type: String?
    let info: String?
}

// MARK: - Error Types

enum WeatherstackError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case httpError(statusCode: Int)
    case apiError(message: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidData:
            return "Invalid weather data received"
        case .httpError(let statusCode):
            return "HTTP Error: \(statusCode)"
        case .apiError(let message):
            return "API Error: \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
