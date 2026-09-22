import Foundation

/// Every balance constant in one place.
///
/// Tuning lives in a value type rather than scattered literals so it can be varied by difficulty,
/// overridden in tests, and eventually exposed to a balance-testing harness.
public struct SimulationTuning {

    // MARK: Needs — rise per game hour

    public var hungerPerHour: Double = 0.140
    public var thirstPerHour: Double = 0.200
    public var tirednessPerHour: Double = 0.055
    public var tirednessRecoveryPerHour: Double = 0.160
    public var boredomPerHour: Double = 0.100
    public var bladderPerHour: Double = 0.130

    // MARK: Needs — thresholds

    public var hungerSeek: Double = 0.62
    public var thirstSeek: Double = 0.60
    public var tirednessSeek: Double = 0.72
    public var boredomSeek: Double = 0.55
    public var bladderSeek: Double = 0.70
    public var urgentThreshold: Double = 0.88

    // MARK: Decisions

    /// Minimum minutes between two decisions for the same guest.
    public var decisionIntervalMinutes: Int = 12
    /// Cooldown after a decision could not be carried out.
    public var failedDecisionCooldownMinutes: Int = 45
    /// Tiles beyond which a guest considers a facility "too far to bother".
    public var maximumComfortableWalkTiles: Int = 70

    // MARK: Holiday rhythm

    public var checkInFromMinute: Int = 15 * 60
    public var checkOutByMinute: Int = 10 * 60
    public var receptionServiceMinutes: Int = 6
    public var unpackingMinutes: Int = 25
    public var packingMinutes: Int = 30
    public var bedtimeEarliestMinute: Int = 21 * 60
    public var wakeMinute: Int = 7 * 60 + 30
    public var sleepMinutesMinimum: Int = 6 * 60

    // MARK: Demand

    /// Daily enquiries per available unit, before every other factor.
    public var enquiriesPerUnitPerDay: Double = 0.62
    public var bookingHorizonDays: Int = 120
    public var cancellationProbabilityPerDay: Double = 0.004
    public var noShowProbability: Double = 0.012

    // MARK: Accommodation

    public var cleanlinessLossPerNight: Double = 0.22
    public var conditionLossPerDay: Double = 0.0018

    // MARK: Economy

    public var electricityPricePerKWh: Money = Money(cents: 28)
    public var waterPricePerCubicMetre: Money = Money(cents: 145)
    public var wasteCostPerGuestPerDay: Money = Money(cents: 35)
    public var insurancePerBuildingPerDay: Money = Money(cents: 120)
    /// Annual corporation-style tax on profit, applied monthly.
    public var profitTaxRate: Double = 0.21
    public var defaultLoanRate: Double = 0.052

    // MARK: Satisfaction

    public var satisfactionMomentCap: Double = 1.2

    public init() {}

    /// Tuning adjusted for a difficulty level.
    public static func forDifficulty(_ difficulty: Difficulty) -> SimulationTuning {
        var tuning = SimulationTuning()
        tuning.enquiriesPerUnitPerDay *= difficulty.demandMultiplier
        return tuning
    }
}
