import Foundation

public enum UnitState: String, CaseIterable, Codable {
    /// Clean, empty and bookable.
    case ready
    /// Guests are in it.
    case occupied
    /// Guests have left; needs housekeeping before the next arrival.
    case dirty
    /// Being cleaned right now.
    case cleaning
    /// Out of service (breakdown or renovation).
    case maintenance

    public var localizationKey: String { "unitState.\(rawValue)" }

    public var acceptsCheckIn: Bool { self == .ready }
}

/// Runtime state of an accommodation unit.
public struct AccommodationState: Codable {

    public var state: UnitState
    /// `0...1`, higher is cleaner.
    public var cleanliness: Double
    public var currentReservationID: ReservationID?
    public var nightlyPriceOverride: Money?
    public var lastCleanedTick: Tick
    /// When an in-progress turnaround finishes.
    public var turnaroundEndsTick: Tick?
    public var totalNightsSold: Int
    public var lifetimeRevenue: Money

    public init() {
        self.state = .ready
        self.cleanliness = 1.0
        self.currentReservationID = nil
        self.nightlyPriceOverride = nil
        self.lastCleanedTick = 0
        self.turnaroundEndsTick = nil
        self.totalNightsSold = 0
        self.lifetimeRevenue = .zero
    }
}

/// Runtime state of a facility.
public struct FacilityState: Codable {

    /// Guests currently being served.
    public var occupants: [GuestID]
    /// Guests waiting to be served, in arrival order.
    public var queue: [GuestID]
    public var priceOverride: Money?
    public var isOpen: Bool
    public var closedReasonKey: String?
    /// `0...1`.
    public var cleanliness: Double
    public var visitsToday: Int
    public var revenueToday: Money
    public var lifetimeVisits: Int
    public var lifetimeRevenue: Money
    /// Rolling mean wait in minutes, used both for guest expectations and the UI.
    public var averageWaitMinutes: Double

    public init() {
        self.occupants = []
        self.queue = []
        self.priceOverride = nil
        self.isOpen = true
        self.closedReasonKey = nil
        self.cleanliness = 1.0
        self.visitsToday = 0
        self.revenueToday = .zero
        self.lifetimeVisits = 0
        self.lifetimeRevenue = .zero
        self.averageWaitMinutes = 0
    }

    public func hasSpace(capacity: Int) -> Bool { occupants.count < capacity }
    public func hasQueueSpace(queueCapacity: Int) -> Bool { queue.count < queueCapacity }
}

/// A placed object in the park.
public struct BuildingInstance: StoredEntity, Codable {

    public typealias Identifier = BuildingID

    public let id: BuildingID
    public let definitionID: String
    public var origin: GridPoint
    public var rotation: Rotation
    /// `0...1`, degrades over time and is restored by maintenance.
    public var condition: Double
    public var builtAtTick: Tick
    public var accommodation: AccommodationState?
    public var facility: FacilityState?

    public init(
        id: BuildingID,
        definitionID: String,
        origin: GridPoint,
        rotation: Rotation,
        builtAtTick: Tick,
        accommodation: AccommodationState?,
        facility: FacilityState?
    ) {
        self.id = id
        self.definitionID = definitionID
        self.origin = origin
        self.rotation = rotation
        self.condition = 1.0
        self.builtAtTick = builtAtTick
        self.accommodation = accommodation
        self.facility = facility
    }

    /// Footprint in world space, after rotation.
    public func footprintRect(definition: BuildingDefinition) -> GridRect {
        let size = rotation.apply(to: definition.footprint)
        return GridRect(origin: origin, size: size)
    }

    /// Tiles that must touch the path network for the building to be usable.
    public func entranceTiles(definition: BuildingDefinition) -> [GridPoint] {
        let base = definition.footprint
        return definition.entranceOffsets.map { offset in
            let rotated = rotation.apply(to: offset, in: base)
            return GridPoint(x: origin.x + rotated.x, y: origin.y + rotated.y)
        }
    }
}
