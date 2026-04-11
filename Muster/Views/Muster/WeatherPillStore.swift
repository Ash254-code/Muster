import Foundation
import CoreLocation
import Combine
import WeatherKit

@MainActor
final class WeatherPillStore: ObservableObject {

    @Published private(set) var temperatureText: String = "--°"
    @Published private(set) var symbolName: String = "nosign"
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var debugErrorText: String? = nil

    @Published private(set) var windText: String = "--"
    @Published private(set) var windDirectionDegrees: Double = 0
    @Published private(set) var windDirectionCardinal: String = "--"

    private var lastFetchLocation: CLLocation?
    private var lastFetchTime: Date?

    private let minFetchInterval: TimeInterval = 60 * 10
    private let minDistanceForRefresh: CLLocationDistance = 1000

    func refreshIfNeeded(for location: CLLocation?) async {
        guard let location else {
            debugErrorText = "No location yet"
            return
        }

        guard location.horizontalAccuracy >= 0 else {
            debugErrorText = "Invalid GPS fix"
            return
        }

        let shouldRefresh: Bool = {
            guard let lastLoc = lastFetchLocation,
                  let lastTime = lastFetchTime else { return true }

            let movedFarEnough = lastLoc.distance(from: location) >= minDistanceForRefresh
            let oldEnough = Date().timeIntervalSince(lastTime) >= minFetchInterval
            return movedFarEnough || oldEnough
        }()

        guard shouldRefresh else { return }

        await refresh(for: location)
    }

    func forceRefresh(for location: CLLocation?) async {
        guard let location else {
            debugErrorText = "No location for force refresh"
            return
        }

        await refresh(for: location)
    }

    func refresh(for location: CLLocation) async {
        guard !isLoading else { return }

        isLoading = true
        debugErrorText = nil

        defer { isLoading = false }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let current = weather.currentWeather

            let temperatureC = current.temperature.converted(to: .celsius).value
            temperatureText = formattedTemperature(temperatureC)
            symbolName = sanitizedSymbolName(current.symbolName)

            let windSpeedKmh = current.wind.speed.converted(to: .kilometersPerHour).value
            windText = formattedWindSpeed(windSpeedKmh)

            // Meteorological wind direction = where wind comes FROM.
            windDirectionDegrees = normalizeDegrees(current.wind.direction.value)
            windDirectionCardinal = cardinalDirection(for: windDirectionDegrees)

            lastFetchLocation = location
            lastFetchTime = Date()

            print(
                "✅ Weather success:",
                temperatureText,
                symbolName,
                windText,
                windDirectionDegrees,
                windDirectionCardinal
            )

        } catch {
            let nsError = error as NSError
            debugErrorText = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
            print("Weather fetch failed:", nsError)

            temperatureText = "--°"
            symbolName = "exclamationmark.triangle.fill"
            windText = "--"
            windDirectionDegrees = 0
            windDirectionCardinal = "--"
        }
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        UnitFormatting.formattedTemperature(celsius)
    }

    private func formattedWindSpeed(_ kmh: Double) -> String {
        let metersPerSecond = kmh / 3.6
        return UnitFormatting.formattedSpeed(fromMetersPerSecond: metersPerSecond, decimals: 0)
    }

    private func sanitizedSymbolName(_ symbolName: String) -> String {
        symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "cloud.fill"
            : symbolName
    }

    private func normalizeDegrees(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    private func cardinalDirection(for degrees: Double) -> String {
        let normalized = normalizeDegrees(degrees)
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized + 22.5) / 45.0) % directions.count
        return directions[index]
    }
}
