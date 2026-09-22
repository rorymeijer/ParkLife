import Foundation

public enum BuildingCategory: String, CaseIterable, Codable {
    case path
    case accommodation
    case food
    case retail
    case activity
    case pool
    case service
    case staff
    case decoration
    case infrastructure

    public var localizationKey: String { "buildingCategory.\(rawValue)" }
}

public enum FacilityKind: String, CaseIterable, Codable {
    case entrance
    case reception
    case restaurant
    case snackBar
    case cafe
    case supermarket
    case shop
    case pool
    case playground
    case activity
    case toilet

    public var localizationKey: String { "facilityKind.\(rawValue)" }

    /// Revenue bucket this facility books its takings into.
    public var revenueCategory: RevenueCategory {
        switch self {
        case .restaurant, .snackBar, .cafe: return .food
        case .supermarket, .shop: return .retail
        case .pool, .playground, .activity: return .activities
        case .entrance, .reception, .toilet: return .extras
        }
    }
}

public enum AccommodationTier: String, CaseIterable, Codable, Comparable {
    case basic
    case comfort
    case premium
    case vip

    public var localizationKey: String { "tier.\(rawValue)" }

    public var order: Int {
        switch self {
        case .basic: return 0
        case .comfort: return 1
        case .premium: return 2
        case .vip: return 3
        }
    }

    /// Multiplier applied to a guest's baseline expectation of quality.
    public var expectationMultiplier: Double {
        switch self {
        case .basic: return 0.80
        case .comfort: return 1.00
        case .premium: return 1.18
        case .vip: return 1.35
        }
    }

    public static func < (lhs: AccommodationTier, rhs: AccommodationTier) -> Bool {
        lhs.order < rhs.order
    }
}

/// Pressures that build up and push a guest to act.
public enum NeedKind: String, CaseIterable, Codable {
    case hunger
    case thirst
    case tiredness
    case boredom
    case bladder

    public var localizationKey: String { "need.\(rawValue)" }
}

/// Long-term tastes, used to match guests to facilities.
public enum InterestKind: String, CaseIterable, Codable {
    case swimming
    case nature
    case sport
    case food
    case shopping
    case entertainment

    public var localizationKey: String { "interest.\(rawValue)" }
}

public enum AgeBand: String, CaseIterable, Codable {
    case child
    case teen
    case adult
    case senior

    public var localizationKey: String { "ageBand.\(rawValue)" }

    /// Tiles walked per simulated minute. Tuned for pacing and readability, not realism —
    /// see docs/SIMULATION.md §3.
    public var walkSpeed: Double {
        switch self {
        case .child: return 1.15
        case .teen: return 1.50
        case .adult: return 1.40
        case .senior: return 1.00
        }
    }

    public static func band(forAge age: Int) -> AgeBand {
        switch age {
        case ..<13: return .child
        case 13..<20: return .teen
        case 20..<66: return .adult
        default: return .senior
        }
    }
}

public enum RevenueCategory: String, CaseIterable, Codable {
    case accommodation
    case food
    case retail
    case activities
    case rentals
    case extras

    public var localizationKey: String { "revenue.\(rawValue)" }
}

public enum ExpenseCategory: String, CaseIterable, Codable {
    case construction
    case wages
    case maintenance
    case electricity
    case water
    case waste
    case ingredients
    case inventory
    case marketing
    case research
    case insurance
    case tax
    case interest
    case repairs
    case landPurchase

    public var localizationKey: String { "expense.\(rawValue)" }
}

public enum Difficulty: String, CaseIterable, Codable {
    case relaxed
    case normal
    case hard
    case custom

    public var localizationKey: String { "difficulty.\(rawValue)" }

    public var startingCash: Money {
        switch self {
        case .relaxed: return Money(euros: 750_000)
        case .normal: return Money(euros: 400_000)
        case .hard: return Money(euros: 250_000)
        case .custom: return Money(euros: 400_000)
        }
    }

    /// Multiplier on generated demand. Never below 1.0 for the player's *costs* — the game does
    /// not cheat, it only changes the starting position and market conditions (brief §34).
    public var demandMultiplier: Double {
        switch self {
        case .relaxed: return 1.25
        case .normal: return 1.00
        case .hard: return 0.82
        case .custom: return 1.00
        }
    }

    public var operatingCostMultiplier: Double {
        switch self {
        case .relaxed: return 0.85
        case .normal: return 1.00
        case .hard: return 1.15
        case .custom: return 1.00
        }
    }

    /// How demanding guests are before they are satisfied.
    public var expectationMultiplier: Double {
        switch self {
        case .relaxed: return 0.88
        case .normal: return 1.00
        case .hard: return 1.14
        case .custom: return 1.00
        }
    }
}
