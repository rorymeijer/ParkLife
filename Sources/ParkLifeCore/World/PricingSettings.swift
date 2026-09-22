import Foundation

/// Player-controlled pricing.
///
/// Prices are expressed as multipliers over the definition's base price plus optional explicit
/// overrides, so a balance change to the catalog still flows through to a saved game.
public struct PricingSettings: Codable {

    /// Global multiplier on accommodation prices.
    public var accommodationMultiplier: Double
    /// Global multiplier on facility prices.
    public var facilityMultiplier: Double
    /// Automatically charge more in peak season and less off-peak.
    public var seasonalPricingEnabled: Bool
    /// Explicit nightly price per accommodation definition id.
    public var accommodationOverrides: [String: Money]
    /// Explicit price per facility building definition id.
    public var facilityOverrides: [String: Money]
    /// Discount applied to bookings made within a week of arrival, `0...1`.
    public var lastMinuteDiscount: Double

    public init() {
        self.accommodationMultiplier = 1.0
        self.facilityMultiplier = 1.0
        self.seasonalPricingEnabled = true
        self.accommodationOverrides = [:]
        self.facilityOverrides = [:]
        self.lastMinuteDiscount = 0.0
    }

    /// Seasonal price factor. Summer and school holidays carry the year.
    public static func seasonalFactor(for date: GameDate) -> Double {
        switch date.season {
        case .summer: return 1.25
        case .spring: return 1.00
        case .autumn: return 0.88
        case .winter: return 0.80
        }
    }

    public static func weekdayFactor(for date: GameDate) -> Double {
        switch date.weekday {
        case .friday, .saturday: return 1.15
        case .sunday: return 1.05
        case .monday, .tuesday, .wednesday: return 0.90
        case .thursday: return 0.95
        }
    }

    /// Nightly price for a unit on a given date.
    public func nightlyPrice(
        definition: BuildingDefinition,
        instance: BuildingInstance,
        date: GameDate
    ) -> Money {
        guard let accommodation = definition.accommodation else { return .zero }
        if let override = instance.accommodation?.nightlyPriceOverride {
            return override
        }
        let base = accommodationOverrides[definition.id] ?? accommodation.baseNightlyPrice
        var factor = accommodationMultiplier
        if seasonalPricingEnabled {
            factor *= PricingSettings.seasonalFactor(for: date)
            factor *= PricingSettings.weekdayFactor(for: date)
        }
        return base.scaled(by: factor)
    }

    /// Price a guest pays at a facility.
    public func facilityPrice(
        definition: BuildingDefinition,
        instance: BuildingInstance
    ) -> Money {
        guard let facility = definition.facility else { return .zero }
        if let override = instance.facility?.priceOverride {
            return override
        }
        let base = facilityOverrides[definition.id] ?? facility.basePrice
        return base.scaled(by: facilityMultiplier)
    }
}
