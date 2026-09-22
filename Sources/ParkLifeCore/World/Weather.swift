import Foundation

public enum WeatherCondition: String, CaseIterable, Codable {
    case clear
    case partlyCloudy
    case cloudy
    case lightRain
    case rain
    case storm
    case fog
    case snow

    public var localizationKey: String { "weather.\(rawValue)" }

    /// Multiplier on the appeal of outdoor activities.
    public var outdoorAppealMultiplier: Double {
        switch self {
        case .clear: return 1.20
        case .partlyCloudy: return 1.05
        case .cloudy: return 0.90
        case .lightRain: return 0.55
        case .rain: return 0.30
        case .storm: return 0.10
        case .fog: return 0.70
        case .snow: return 0.45
        }
    }

    /// Multiplier on the appeal of indoor facilities — rain drives everyone to the pool.
    public var indoorAppealMultiplier: Double {
        switch self {
        case .clear: return 0.85
        case .partlyCloudy: return 0.95
        case .cloudy: return 1.05
        case .lightRain: return 1.25
        case .rain: return 1.40
        case .storm: return 1.45
        case .fog: return 1.15
        case .snow: return 1.30
        }
    }

    public var isSevere: Bool { self == .storm }
}

public struct Weather: Codable {

    public var condition: WeatherCondition
    /// °C at the current hour.
    public var temperature: Double
    public var windKph: Double
    /// `0...1`.
    public var precipitation: Double
    /// Daily mean, used for energy and demand maths.
    public var dailyMeanTemperature: Double
    /// Day index this weather was generated for.
    public var generatedForDay: Int
    /// AR(1) anomaly carried between days so weather has persistence.
    public var temperatureAnomaly: Double

    public init() {
        self.condition = .partlyCloudy
        self.temperature = 15
        self.windKph = 10
        self.precipitation = 0
        self.dailyMeanTemperature = 15
        self.generatedForDay = Int.min
        self.temperatureAnomaly = 0
    }

    /// How pleasant it feels for a holiday, `0...1`.
    public var comfortIndex: Double {
        let temperatureScore = 1.0 - clamp01(abs(temperature - 21.0) / 18.0)
        let wetScore = 1.0 - clamp01(precipitation)
        let windScore = 1.0 - clamp01((windKph - 15.0) / 50.0)
        return clamp01(temperatureScore * 0.5 + wetScore * 0.35 + windScore * 0.15)
    }
}
