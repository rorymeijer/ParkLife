import Foundation

/// Fixed-capacity time series.
///
/// Statistics are accumulated as they happen and stored pre-aggregated. Nothing in the game ever
/// answers "what was occupancy last month?" by walking historical entities (brief §37).
public struct TimeSeries: Codable {

    public let capacity: Int
    public private(set) var periodIndices: [Int]
    public private(set) var values: [Double]

    public init(capacity: Int) {
        self.capacity = capacity
        self.periodIndices = []
        self.values = []
    }

    /// Records a sample. Repeated samples for the same period replace the previous value.
    public mutating func record(period: Int, value: Double) {
        if let last = periodIndices.last, last == period {
            values[values.count - 1] = value
            return
        }
        periodIndices.append(period)
        values.append(value)
        if periodIndices.count > capacity {
            let excess = periodIndices.count - capacity
            periodIndices.removeFirst(excess)
            values.removeFirst(excess)
        }
    }

    /// Accumulates into the current period instead of replacing.
    public mutating func accumulate(period: Int, value: Double) {
        if let last = periodIndices.last, last == period {
            values[values.count - 1] += value
            return
        }
        record(period: period, value: value)
    }

    public var latest: Double? { values.last }
    public var count: Int { values.count }

    public func value(forPeriod period: Int) -> Double? {
        guard let index = periodIndices.lastIndex(of: period) else { return nil }
        return values[index]
    }

    /// Most recent `count` values, oldest first — exactly what a chart needs.
    public func recent(_ count: Int) -> [Double] {
        Array(values.suffix(count))
    }

    public func average(lastPeriods count: Int) -> Double? {
        let recent = values.suffix(count)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }
}

public enum StatisticMetric: String, CaseIterable, Codable {
    case occupancy
    case guestsOnSite
    case revenue
    case expenses
    case profit
    case cashBalance
    case satisfaction
    case reviewScore
    case arrivals
    case departures
    case energyKWh
    case waterLitres
    case staffCount

    public var localizationKey: String { "metric.\(rawValue)" }
}

public struct Statistics: Codable {

    public var hourly: [String: TimeSeries]
    public var daily: [String: TimeSeries]
    public var weekly: [String: TimeSeries]

    /// Counters that only ever grow.
    public var totalGuestsHosted: Int
    public var totalNightsSold: Int
    public var totalReviews: Int

    public init() {
        self.hourly = [:]
        self.daily = [:]
        self.weekly = [:]
        self.totalGuestsHosted = 0
        self.totalNightsSold = 0
        self.totalReviews = 0
    }

    // 7 days of hourly detail, 2 years of daily, 20 years of weekly.
    private static let hourlyCapacity = 24 * 7
    private static let dailyCapacity = 730
    private static let weeklyCapacity = 1_040

    public mutating func recordHourly(_ metric: StatisticMetric, period: Int, value: Double) {
        var series = hourly[metric.rawValue] ?? TimeSeries(capacity: Statistics.hourlyCapacity)
        series.record(period: period, value: value)
        hourly[metric.rawValue] = series
    }

    public mutating func recordDaily(_ metric: StatisticMetric, period: Int, value: Double) {
        var series = daily[metric.rawValue] ?? TimeSeries(capacity: Statistics.dailyCapacity)
        series.record(period: period, value: value)
        daily[metric.rawValue] = series
    }

    public mutating func accumulateDaily(_ metric: StatisticMetric, period: Int, value: Double) {
        var series = daily[metric.rawValue] ?? TimeSeries(capacity: Statistics.dailyCapacity)
        series.accumulate(period: period, value: value)
        daily[metric.rawValue] = series
    }

    public mutating func recordWeekly(_ metric: StatisticMetric, period: Int, value: Double) {
        var series = weekly[metric.rawValue] ?? TimeSeries(capacity: Statistics.weeklyCapacity)
        series.record(period: period, value: value)
        weekly[metric.rawValue] = series
    }

    public func dailySeries(_ metric: StatisticMetric) -> TimeSeries? {
        daily[metric.rawValue]
    }

    public func hourlySeries(_ metric: StatisticMetric) -> TimeSeries? {
        hourly[metric.rawValue]
    }

    public func weeklySeries(_ metric: StatisticMetric) -> TimeSeries? {
        weekly[metric.rawValue]
    }
}
