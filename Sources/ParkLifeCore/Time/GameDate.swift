import Foundation

/// One simulation tick is one simulated minute.
public typealias Tick = Int

public enum Season: Int, CaseIterable, Codable {
    case spring = 0
    case summer = 1
    case autumn = 2
    case winter = 3

    public var localizationKey: String {
        switch self {
        case .spring: return "season.spring"
        case .summer: return "season.summer"
        case .autumn: return "season.autumn"
        case .winter: return "season.winter"
        }
    }
}

public enum Weekday: Int, CaseIterable, Codable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    public var isWeekend: Bool { self == .saturday || self == .sunday }

    public var localizationKey: String { "weekday.\(self.shortName)" }

    public var shortName: String {
        switch self {
        case .monday: return "mon"
        case .tuesday: return "tue"
        case .wednesday: return "wed"
        case .thursday: return "thu"
        case .friday: return "fri"
        case .saturday: return "sat"
        case .sunday: return "sun"
        }
    }
}

/// Calendar arithmetic for the simulation.
///
/// Pure integer maths over "minutes since the epoch". The simulation never reads `Date()`, because
/// a save must replay identically regardless of when it is loaded.
public struct GameDate: Hashable, Comparable, Codable, CustomStringConvertible {

    /// The in-game epoch: 1 January 2026, 00:00. 2026-01-01 was a Thursday.
    public static let epochYear = 2026

    public static let minutesPerHour = 60
    public static let minutesPerDay = 1_440
    public static let minutesPerWeek = 10_080

    public var minutesSinceEpoch: Int

    public init(minutesSinceEpoch: Int) {
        self.minutesSinceEpoch = minutesSinceEpoch
    }

    public init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) {
        let days = GameDate.daysFromCivil(year: year, month: month, day: day)
            - GameDate.daysFromCivil(year: GameDate.epochYear, month: 1, day: 1)
        self.minutesSinceEpoch = days * GameDate.minutesPerDay + hour * 60 + minute
    }

    // MARK: - Components

    /// Whole days since the epoch (day 0 is 1 January of the epoch year).
    public var dayIndex: Int {
        Int(floor(Double(minutesSinceEpoch) / Double(GameDate.minutesPerDay)))
    }

    /// Minutes elapsed within the current day, `0..<1440`.
    public var minuteOfDay: Int {
        minutesSinceEpoch - dayIndex * GameDate.minutesPerDay
    }

    public var hour: Int { minuteOfDay / 60 }
    public var minute: Int { minuteOfDay % 60 }

    private var civil: (year: Int, month: Int, day: Int) {
        let absoluteDays = GameDate.daysFromCivil(year: GameDate.epochYear, month: 1, day: 1) + dayIndex
        return GameDate.civilFromDays(absoluteDays)
    }

    public var year: Int { civil.year }
    public var month: Int { civil.month }
    public var dayOfMonth: Int { civil.day }

    /// Year number as presented to the player: the first played year is "Year 1".
    public var gameYear: Int { year - GameDate.epochYear + 1 }

    public var weekday: Weekday {
        let absoluteDays = GameDate.daysFromCivil(year: GameDate.epochYear, month: 1, day: 1) + dayIndex
        // 1970-01-01 was a Thursday, which is index 3 in a Monday-first week.
        let index = ((absoluteDays + 3) % 7 + 7) % 7
        return Weekday(rawValue: index) ?? .monday
    }

    public var isWeekend: Bool { weekday.isWeekend }

    public var dayOfYear: Int {
        let components = civil
        let start = GameDate.daysFromCivil(year: components.year, month: 1, day: 1)
        let today = GameDate.daysFromCivil(year: components.year, month: components.month, day: components.day)
        return today - start + 1
    }

    public var season: Season {
        switch month {
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        case 9, 10, 11: return .autumn
        default: return .winter
        }
    }

    /// ISO-like week number, good enough for statistics bucketing.
    public var weekIndex: Int {
        Int(floor(Double(minutesSinceEpoch) / Double(GameDate.minutesPerWeek)))
    }

    public var monthIndex: Int {
        let components = civil
        return (components.year - GameDate.epochYear) * 12 + (components.month - 1)
    }

    /// Start of the current day.
    public var startOfDay: GameDate {
        GameDate(minutesSinceEpoch: dayIndex * GameDate.minutesPerDay)
    }

    // MARK: - Arithmetic

    public func adding(minutes: Int) -> GameDate {
        GameDate(minutesSinceEpoch: minutesSinceEpoch + minutes)
    }

    public func adding(hours: Int) -> GameDate {
        adding(minutes: hours * 60)
    }

    public func adding(days: Int) -> GameDate {
        adding(minutes: days * GameDate.minutesPerDay)
    }

    /// Whole nights between two dates, as a hotel would count them.
    public func nights(until other: GameDate) -> Int {
        max(0, other.dayIndex - dayIndex)
    }

    public static func < (lhs: GameDate, rhs: GameDate) -> Bool {
        lhs.minutesSinceEpoch < rhs.minutesSinceEpoch
    }

    public var description: String {
        let components = civil
        return String(
            format: "%04d-%02d-%02d %02d:%02d",
            components.year, components.month, components.day, hour, minute
        )
    }

    // MARK: - Civil calendar (Howard Hinnant's days_from_civil / civil_from_days)

    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        y -= month <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civilFromDays(_ daysSinceUnixEpoch: Int) -> (year: Int, month: Int, day: Int) {
        var z = daysSinceUnixEpoch
        z += 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        return (year + (month <= 2 ? 1 : 0), month, day)
    }
}
