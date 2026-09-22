import Foundation

/// How much a facility visit relieves one need.
public struct NeedRelief: Codable, Hashable {
    public let need: NeedKind
    public let amount: Double

    public init(need: NeedKind, amount: Double) {
        self.need = need
        self.amount = amount
    }
}

/// Opening hours as minutes from midnight. `opens == closes` means "always open".
public struct OpeningHours: Codable, Hashable {

    public let opensAtMinute: Int
    public let closesAtMinute: Int

    public init(opensAtMinute: Int, closesAtMinute: Int) {
        self.opensAtMinute = opensAtMinute
        self.closesAtMinute = closesAtMinute
    }

    public static let alwaysOpen = OpeningHours(opensAtMinute: 0, closesAtMinute: 0)

    public var isAlwaysOpen: Bool { opensAtMinute == closesAtMinute }

    public func isOpen(atMinuteOfDay minute: Int) -> Bool {
        if isAlwaysOpen { return true }
        if closesAtMinute > opensAtMinute {
            return minute >= opensAtMinute && minute < closesAtMinute
        }
        // Wraps past midnight.
        return minute >= opensAtMinute || minute < closesAtMinute
    }

    /// Minutes until closing time, or `nil` when always open.
    public func minutesUntilClose(fromMinuteOfDay minute: Int) -> Int? {
        guard !isAlwaysOpen else { return nil }
        let close = closesAtMinute > opensAtMinute ? closesAtMinute : closesAtMinute + GameDate.minutesPerDay
        let now = minute < opensAtMinute && closesAtMinute <= opensAtMinute ? minute + GameDate.minutesPerDay : minute
        return max(0, close - now)
    }
}

/// Accommodation capability attached to a building definition.
public struct AccommodationDefinition: Codable {

    public let capacity: Int
    public let bedrooms: Int
    public let bathrooms: Int
    public let hasKitchen: Bool
    public let tier: AccommodationTier
    /// Intrinsic quality, `0...1`, before condition and cleanliness are applied.
    public let baseQuality: Double
    public let baseNightlyPrice: Money
    public let dailyOperatingCost: Money
    /// Simulated minutes a housekeeper needs to turn the unit around.
    public let cleaningMinutes: Int
    public let energyPerNightKWh: Double
    public let waterPerNightLitres: Double

    public init(
        capacity: Int,
        bedrooms: Int,
        bathrooms: Int,
        hasKitchen: Bool,
        tier: AccommodationTier,
        baseQuality: Double,
        baseNightlyPrice: Money,
        dailyOperatingCost: Money,
        cleaningMinutes: Int,
        energyPerNightKWh: Double,
        waterPerNightLitres: Double
    ) {
        self.capacity = capacity
        self.bedrooms = bedrooms
        self.bathrooms = bathrooms
        self.hasKitchen = hasKitchen
        self.tier = tier
        self.baseQuality = baseQuality
        self.baseNightlyPrice = baseNightlyPrice
        self.dailyOperatingCost = dailyOperatingCost
        self.cleaningMinutes = cleaningMinutes
        self.energyPerNightKWh = energyPerNightKWh
        self.waterPerNightLitres = waterPerNightLitres
    }
}

/// Facility capability attached to a building definition.
public struct FacilityDefinition: Codable {

    public let kind: FacilityKind
    /// How many guests can be served at the same time.
    public let capacity: Int
    public let queueCapacity: Int
    public let minimumServiceMinutes: Int
    public let maximumServiceMinutes: Int
    public let basePrice: Money
    public let openingHours: OpeningHours
    /// Intrinsic attractiveness, `0...1`.
    public let appeal: Double
    /// How well it suits children, `0...1`.
    public let childSuitability: Double
    public let isIndoor: Bool
    public let staffRequired: Int
    public let staffRoleID: String?
    public let relief: [NeedRelief]
    public let interests: [InterestKind]
    /// Share of the price that is variable cost (ingredients, stock).
    public let variableCostFraction: Double

    public init(
        kind: FacilityKind,
        capacity: Int,
        queueCapacity: Int,
        minimumServiceMinutes: Int,
        maximumServiceMinutes: Int,
        basePrice: Money,
        openingHours: OpeningHours,
        appeal: Double,
        childSuitability: Double,
        isIndoor: Bool,
        staffRequired: Int,
        staffRoleID: String?,
        relief: [NeedRelief],
        interests: [InterestKind],
        variableCostFraction: Double
    ) {
        self.kind = kind
        self.capacity = capacity
        self.queueCapacity = queueCapacity
        self.minimumServiceMinutes = minimumServiceMinutes
        self.maximumServiceMinutes = maximumServiceMinutes
        self.basePrice = basePrice
        self.openingHours = openingHours
        self.appeal = appeal
        self.childSuitability = childSuitability
        self.isIndoor = isIndoor
        self.staffRequired = staffRequired
        self.staffRoleID = staffRoleID
        self.relief = relief
        self.interests = interests
        self.variableCostFraction = variableCostFraction
    }

    public func reliefAmount(for need: NeedKind) -> Double {
        relief.first(where: { $0.need == need })?.amount ?? 0
    }
}

/// Everything the game knows about a placeable object.
///
/// Adding a new cottage, restaurant or attraction is a JSON edit — no Swift changes, no switch
/// statements in the build system, the renderer or the UI (brief §40, Rule 4).
public struct BuildingDefinition: Codable {

    public let id: String
    public let nameKey: String
    public let summaryKey: String
    public let category: BuildingCategory
    public let footprintWidth: Int
    public let footprintHeight: Int
    /// Tiles (relative to the origin) that must be reachable from the path network.
    public let entranceOffsets: [GridPoint]
    public let constructionCost: Money
    public let dailyOperatingCost: Money
    public let demolitionRefundFraction: Double
    /// Art identifier. Deliberately distinct from `id` so artwork can be re-themed without
    /// touching simulation data (ASSET POLICY §54).
    public let art: String
    public let requiresPathAdjacency: Bool
    /// Contribution to the beauty of surrounding tiles, `-1...1`.
    public let scenery: Double
    public let sceneryRadius: Int
    public let researchID: String?
    public let accommodation: AccommodationDefinition?
    public let facility: FacilityDefinition?

    public var footprint: GridSize {
        GridSize(width: footprintWidth, height: footprintHeight)
    }

    public var tileCount: Int { footprintWidth * footprintHeight }

    public var isAccommodation: Bool { accommodation != nil }
    public var isFacility: Bool { facility != nil }
}

public struct StaffRoleDefinition: Codable {
    public let id: String
    public let nameKey: String
    public let monthlySalary: Money
    public let handlesTasks: [String]
    public let walkSpeed: Double
    public let art: String
}

public struct ResearchDefinition: Codable {
    public let id: String
    public let nameKey: String
    public let summaryKey: String
    public let category: String
    public let costPerWeek: Money
    public let weeksRequired: Int
    public let prerequisites: [String]
    public let unlocksBuildings: [String]
}

/// A data-driven objective. Objectives are never hardcoded into UI logic (brief §33).
public struct ObjectiveDefinition: Codable {

    public enum Metric: String, Codable {
        case cash
        case annualRevenue
        case occupancyPercent
        case guestSatisfaction
        case reviewScore
        case totalGuestsHosted
        case consecutiveProfitableMonths
        case reputation
        case sustainabilityRating
    }

    public enum Comparison: String, Codable {
        case atLeast
        case atMost
    }

    public let id: String
    public let titleKey: String
    public let metric: Metric
    public let comparison: Comparison
    public let target: Double
    /// Must hold for this many consecutive days before it counts as met (0 = instantaneous).
    public let sustainedDays: Int
}

public struct ScenarioDefinition: Codable {
    public let id: String
    public let nameKey: String
    public let summaryKey: String
    public let mapID: String
    public let startingCash: Money
    public let startDate: ScenarioDate
    public let difficulty: Difficulty
    public let objectives: [ObjectiveDefinition]
    public let deadlineDays: Int?
    public let prebuilt: [PrebuiltPlacement]

    public struct ScenarioDate: Codable {
        public let year: Int
        public let month: Int
        public let day: Int
        public let hour: Int

        public var gameDate: GameDate {
            GameDate(year: year, month: month, day: day, hour: hour)
        }
    }

    public struct PrebuiltPlacement: Codable {
        public let definitionID: String
        public let x: Int
        public let y: Int
        public let rotation: Int

        public var origin: GridPoint { GridPoint(x: x, y: y) }
    }
}

/// A kind of travelling party.
public struct GroupArchetypeDefinition: Codable {

    public let id: String
    public let nameKey: String
    public let minimumAdults: Int
    public let maximumAdults: Int
    public let minimumChildren: Int
    public let maximumChildren: Int
    public let adultAgeRange: [Int]
    public let childAgeRange: [Int]
    /// Budget per person per night, before any extras.
    public let budgetPerPersonPerNight: Money
    public let minimumNights: Int
    public let maximumNights: Int
    /// Bias toward each interest, `0...1`, sampled per guest with jitter.
    public let interestBias: [String: Double]
    /// Relative share of the market.
    public let marketShare: Double
    /// Extra pull during school holidays.
    public let schoolHolidaySensitivity: Double
    /// Weighting of each review category when forming an overall score.
    public let reviewWeights: [String: Double]
    public let preferredTiers: [AccommodationTier]
}

/// School and public holiday windows, per region, so other countries differ by data only.
public struct CalendarDefinition: Codable {

    public struct Window: Codable {
        public let id: String
        public let startMonth: Int
        public let startDay: Int
        public let endMonth: Int
        public let endDay: Int
        public let isSchoolHoliday: Bool
        public let demandBoost: Double
    }

    public let regionID: String
    public let windows: [Window]
}

/// A playable location.
public struct MapDefinition: Codable {

    public struct WaterFeature: Codable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
    }

    public struct ForestPatch: Codable {
        public let x: Int
        public let y: Int
        public let radius: Int
        public let density: Double
    }

    public let id: String
    public let nameKey: String
    public let regionID: String
    public let width: Int
    public let height: Int
    public let generationSeed: UInt64
    /// Tile where guests enter the park from the outside world.
    public let entranceX: Int
    public let entranceY: Int
    public let landValuePerTile: Money
    public let water: [WaterFeature]
    public let forests: [ForestPatch]
    /// Average yearly temperature and its seasonal swing, in °C.
    public let climateMeanTemperature: Double
    public let climateSeasonalAmplitude: Double
    public let climateRainProbability: Double
    /// Regional demand multiplier.
    public let localDemand: Double

    public var size: GridSize { GridSize(width: width, height: height) }
    public var entrance: GridPoint { GridPoint(x: entranceX, y: entranceY) }
}
