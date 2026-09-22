import Foundation

/// Daily weather with persistence, plus an hourly temperature curve.
///
/// Seasonal sinusoid + an AR(1) anomaly means warm spells and wet weeks hang together instead of
/// the weather resampling itself from scratch every morning.
public enum WeatherSystem: SimulationSystem {

    public static let systemName = "Weather"

    public static func update(world: inout World, context: inout TickContext) {
        let day = context.date.dayOfYear
        if world.weather.generatedForDay != context.date.dayIndex {
            generateDay(world: &world, context: context, dayOfYear: day)
        }
        applyDiurnalCurve(world: &world, minuteOfDay: context.date.minuteOfDay)
    }

    private static func generateDay(world: inout World, context: TickContext, dayOfYear: Int) {
        guard let map = world.catalog.maps[world.mapID] else { return }
        // Seasonal mean: coldest around day 20, warmest around day 202.
        let phase = (Double(dayOfYear) - 20.0) / 365.0 * 2.0 * Double.pi
        let seasonalMean = map.climateMeanTemperature - map.climateSeasonalAmplitude * cos(phase)

        // AR(1): today's anomaly remembers yesterday's.
        let previousAnomaly = world.weather.temperatureAnomaly
        let shock = world.random.weather.gaussian(mean: 0, standardDeviation: 2.4)
        let anomaly = previousAnomaly * 0.62 + shock

        let mean = seasonalMean + anomaly
        let condition = sampleCondition(
            world: &world,
            previous: world.weather.condition,
            season: context.date.season,
            rainProbability: map.climateRainProbability,
            temperature: mean
        )

        world.weather.temperatureAnomaly = anomaly
        world.weather.dailyMeanTemperature = mean
        world.weather.condition = condition
        world.weather.generatedForDay = context.date.dayIndex
        world.weather.precipitation = precipitation(for: condition, random: &world.random.weather)
        world.weather.windKph = wind(for: condition, random: &world.random.weather)
        ParkLog.shared.debug(.sim, "Weather for day \(context.date.dayIndex): \(condition.rawValue) \(Int(mean))°C")
    }

    private static func sampleCondition(
        world: inout World,
        previous: WeatherCondition,
        season: Season,
        rainProbability: Double,
        temperature: Double
    ) -> WeatherCondition {
        var weights: [Double] = []
        for condition in WeatherCondition.allCases {
            var weight: Double
            switch condition {
            case .clear: weight = season == .summer ? 0.30 : 0.18
            case .partlyCloudy: weight = 0.26
            case .cloudy: weight = 0.24
            case .lightRain: weight = rainProbability * 0.55
            case .rain: weight = rainProbability * 0.40
            case .storm: weight = rainProbability * 0.07
            case .fog: weight = (season == .autumn || season == .winter) ? 0.09 : 0.02
            case .snow: weight = temperature < 1.5 ? 0.22 : 0.0
            }
            // Weather persists: yesterday's condition is more likely to continue.
            if condition == previous { weight *= 2.1 }
            weights.append(weight)
        }
        let index = world.random.weather.weightedIndex(weights) ?? 1
        return WeatherCondition.allCases[index]
    }

    private static func precipitation(for condition: WeatherCondition, random: inout SeededRandom) -> Double {
        switch condition {
        case .clear, .partlyCloudy: return 0
        case .cloudy: return random.nextDouble(in: 0...0.08)
        case .fog: return random.nextDouble(in: 0...0.1)
        case .lightRain: return random.nextDouble(in: 0.15...0.4)
        case .rain: return random.nextDouble(in: 0.4...0.8)
        case .storm: return random.nextDouble(in: 0.7...1.0)
        case .snow: return random.nextDouble(in: 0.3...0.7)
        }
    }

    private static func wind(for condition: WeatherCondition, random: inout SeededRandom) -> Double {
        switch condition {
        case .storm: return random.nextDouble(in: 55...95)
        case .rain, .lightRain: return random.nextDouble(in: 12...38)
        case .fog: return random.nextDouble(in: 0...8)
        default: return random.nextDouble(in: 4...25)
        }
    }

    /// Cool at dawn, warmest mid-afternoon.
    private static func applyDiurnalCurve(world: inout World, minuteOfDay: Int) {
        let hours = Double(minuteOfDay) / 60.0
        let swing = 5.0
        let curve = -cos((hours - 4.0) / 24.0 * 2.0 * Double.pi)
        world.weather.temperature = world.weather.dailyMeanTemperature + swing * curve * 0.5
    }
}
