import Foundation

/// Stable personality traits, `0...1`. Sampled once per guest from the group archetype.
public struct Personality: Codable, Hashable {

    public var sociability: Double
    public var adventurousness: Double
    public var patience: Double
    public var frugality: Double
    public var tidiness: Double
    public var activityLevel: Double

    public init(
        sociability: Double,
        adventurousness: Double,
        patience: Double,
        frugality: Double,
        tidiness: Double,
        activityLevel: Double
    ) {
        self.sociability = sociability
        self.adventurousness = adventurousness
        self.patience = patience
        self.frugality = frugality
        self.tidiness = tidiness
        self.activityLevel = activityLevel
    }

    public static let neutral = Personality(
        sociability: 0.5, adventurousness: 0.5, patience: 0.5,
        frugality: 0.5, tidiness: 0.5, activityLevel: 0.5
    )
}

/// Long-term tastes, `0...1`.
public struct Interests: Codable, Hashable {

    public var swimming: Double
    public var nature: Double
    public var sport: Double
    public var food: Double
    public var shopping: Double
    public var entertainment: Double

    public init(
        swimming: Double,
        nature: Double,
        sport: Double,
        food: Double,
        shopping: Double,
        entertainment: Double
    ) {
        self.swimming = swimming
        self.nature = nature
        self.sport = sport
        self.food = food
        self.shopping = shopping
        self.entertainment = entertainment
    }

    public static let neutral = Interests(
        swimming: 0.5, nature: 0.5, sport: 0.5, food: 0.5, shopping: 0.5, entertainment: 0.5
    )

    public subscript(kind: InterestKind) -> Double {
        get {
            switch kind {
            case .swimming: return swimming
            case .nature: return nature
            case .sport: return sport
            case .food: return food
            case .shopping: return shopping
            case .entertainment: return entertainment
            }
        }
        set {
            switch kind {
            case .swimming: swimming = newValue
            case .nature: nature = newValue
            case .sport: sport = newValue
            case .food: food = newValue
            case .shopping: shopping = newValue
            case .entertainment: entertainment = newValue
            }
        }
    }

    /// Best match between this guest's tastes and a facility's tags.
    public func affinity(for tags: [InterestKind]) -> Double {
        guard !tags.isEmpty else { return 0.5 }
        var best = 0.0
        for tag in tags {
            best = Swift.max(best, self[tag])
        }
        return best
    }
}

/// Need pressures, `0...1`, where higher means more urgent.
public struct NeedState: Codable, Hashable {

    public var hunger: Double
    public var thirst: Double
    public var tiredness: Double
    public var boredom: Double
    public var bladder: Double

    public init(
        hunger: Double = 0.1,
        thirst: Double = 0.1,
        tiredness: Double = 0.1,
        boredom: Double = 0.2,
        bladder: Double = 0.1
    ) {
        self.hunger = hunger
        self.thirst = thirst
        self.tiredness = tiredness
        self.boredom = boredom
        self.bladder = bladder
    }

    public subscript(kind: NeedKind) -> Double {
        get {
            switch kind {
            case .hunger: return hunger
            case .thirst: return thirst
            case .tiredness: return tiredness
            case .boredom: return boredom
            case .bladder: return bladder
            }
        }
        set {
            let value = clamp01(newValue)
            switch kind {
            case .hunger: hunger = value
            case .thirst: thirst = value
            case .tiredness: tiredness = value
            case .boredom: boredom = value
            case .bladder: bladder = value
            }
        }
    }

    /// The need currently pressing hardest, with its value.
    public var dominant: (kind: NeedKind, value: Double) {
        var bestKind = NeedKind.hunger
        var bestValue = -1.0
        for kind in NeedKind.allCases {
            let value = self[kind]
            if value > bestValue {
                bestValue = value
                bestKind = kind
            }
        }
        return (bestKind, bestValue)
    }

    /// Mean discomfort, used when folding needs into happiness.
    public var averagePressure: Double {
        (hunger + thirst + tiredness + boredom + bladder) / 5.0
    }
}

/// Simulation level of detail — the mechanism behind brief §43.
public enum SimulationDetail: String, Codable {
    /// On screen and moving: full position update every tick.
    case full
    /// Off screen and moving: position updated every few ticks.
    case reduced
    /// Sleeping, queueing or inside a facility: **no per-tick work at all**; woken by the
    /// schedule queue on an exact future tick.
    case dormant
}

/// What a guest is doing right now.
public enum GuestActivity: Codable, Hashable {
    case offPark
    case arriving
    case walkingToReception
    case queueingAtReception
    case checkingIn
    case walkingToUnit
    case unpacking
    case idle
    case walkingTo(BuildingID)
    case queueing(BuildingID)
    case using(BuildingID)
    case sleeping
    case packing
    case walkingToExit
    case departed

    public var isWalking: Bool {
        switch self {
        case .arriving, .walkingToReception, .walkingToUnit, .walkingTo, .walkingToExit:
            return true
        default:
            return false
        }
    }

    public var isDormant: Bool {
        switch self {
        case .sleeping, .using, .unpacking, .checkingIn, .packing, .offPark, .departed:
            return true
        default:
            return false
        }
    }

    public var localizationKey: String {
        switch self {
        case .offPark: return "activity.offPark"
        case .arriving: return "activity.arriving"
        case .walkingToReception: return "activity.walkingToReception"
        case .queueingAtReception: return "activity.queueingAtReception"
        case .checkingIn: return "activity.checkingIn"
        case .walkingToUnit: return "activity.walkingToUnit"
        case .unpacking: return "activity.unpacking"
        case .idle: return "activity.idle"
        case .walkingTo: return "activity.walkingTo"
        case .queueing: return "activity.queueing"
        case .using: return "activity.using"
        case .sleeping: return "activity.sleeping"
        case .packing: return "activity.packing"
        case .walkingToExit: return "activity.walkingToExit"
        case .departed: return "activity.departed"
        }
    }
}

/// A route the guest is following, tile by tile.
public struct MovementPath: Codable, Hashable {

    public var tiles: [GridPoint]
    public var index: Int
    /// Progress from `tiles[index]` to `tiles[index + 1]`, `0...1`.
    public var progress: Double

    public init(tiles: [GridPoint]) {
        self.tiles = tiles
        self.index = 0
        self.progress = 0
    }

    public var isFinished: Bool { index >= tiles.count - 1 }

    public var destination: GridPoint? { tiles.last }

    public var remainingTiles: Int { max(0, tiles.count - 1 - index) }

    public var currentPosition: WorldPoint {
        guard !tiles.isEmpty else { return WorldPoint(x: 0, y: 0) }
        guard index < tiles.count - 1 else { return WorldPoint(tiles[tiles.count - 1]) }
        return WorldPoint.lerp(WorldPoint(tiles[index]), WorldPoint(tiles[index + 1]), progress)
    }
}

public struct Guest: StoredEntity, Codable {

    public typealias Identifier = GuestID

    public let id: GuestID
    public var groupID: GroupID
    public var firstName: String
    public var age: Int
    public var ageBand: AgeBand
    public var personality: Personality
    public var interests: Interests
    public var needs: NeedState

    /// `0...1`, higher is better.
    public var happiness: Double
    public var comfort: Double

    public var position: WorldPoint
    public var activity: GuestActivity
    public var detail: SimulationDetail
    public var path: MovementPath?
    public var moneySpent: Money
    public var thoughts: [GuestThought]
    /// Rolling congestion exposure over recently walked tiles, `0...1`.
    public var congestionExposure: Double
    public var lastDecisionTick: Tick
    /// Has this guest already settled into their cottage on arrival?
    public var hasUnpacked: Bool
    /// Tick the guest joined the queue they are currently in.
    public var queueJoinedTick: Tick
    /// Tick at which needs were last advanced. Dormant guests are not touched per tick; their
    /// drift is applied in one go when they wake, which is what makes LOD free rather than lossy.
    public var lastNeedsTick: Tick
    /// Set when a decision could not be acted on, so the AI can back off rather than retry
    /// every single tick.
    public var decisionCooldownUntilTick: Tick

    public init(
        id: GuestID,
        groupID: GroupID,
        firstName: String,
        age: Int,
        personality: Personality,
        interests: Interests,
        position: WorldPoint
    ) {
        self.id = id
        self.groupID = groupID
        self.firstName = firstName
        self.age = age
        self.ageBand = AgeBand.band(forAge: age)
        self.personality = personality
        self.interests = interests
        self.needs = NeedState()
        self.happiness = 0.7
        self.comfort = 0.7
        self.position = position
        self.activity = .offPark
        self.detail = .dormant
        self.path = nil
        self.moneySpent = .zero
        self.thoughts = []
        self.congestionExposure = 0
        self.lastDecisionTick = 0
        self.hasUnpacked = false
        self.queueJoinedTick = 0
        self.lastNeedsTick = 0
        self.decisionCooldownUntilTick = 0
    }

    public var walkSpeed: Double {
        ageBand.walkSpeed * (0.9 + 0.2 * personality.activityLevel)
    }

    public var tile: GridPoint { position.tile }

    /// Keeps the last few thoughts only — guests are not a log file.
    public mutating func remember(_ thought: GuestThought) {
        thoughts.append(thought)
        if thoughts.count > 8 {
            thoughts.removeFirst(thoughts.count - 8)
        }
    }
}
