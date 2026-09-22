import Foundation

/// The entire simulated state of a park and its company.
///
/// A value type with one owner at a time — which is what makes saving a snapshot, hashing for
/// determinism and reasoning about concurrency straightforward. Derived state (`navigation`,
/// `index`) is rebuilt rather than saved.
public struct World {

    // MARK: Content

    /// Immutable game content. Not part of the save: definitions ship with the build.
    public let catalog: ContentCatalog

    // MARK: Identity & configuration

    public var seed: UInt64
    public var random: RandomStreams
    public var ids: IDAllocator
    public var difficulty: Difficulty
    public var scenarioID: String?
    public var parkID: String
    public var parkName: String
    public var companyName: String
    public var mapID: String
    public var regionID: String

    // MARK: Time

    public var clock: SimulationClock
    public var schedule: ScheduleQueue

    // MARK: Space

    public var tiles: TileMap
    public var entranceTile: GridPoint

    // MARK: Entities

    public var buildings: EntityStore<BuildingInstance>
    public var guests: EntityStore<Guest>
    public var groups: EntityStore<GuestGroup>
    public var reservations: EntityStore<Reservation>
    public var staff: EntityStore<StaffMember>
    public var tasks: EntityStore<StaffTask>
    /// Newest last, capped.
    public var reviews: [Review]

    // MARK: Economy & standing

    public var cash: Money
    public var loans: [Loan]
    public var ledger: Ledger
    public var reputation: Reputation
    public var pricing: PricingSettings
    /// Sorted for deterministic iteration.
    public var completedResearch: [String]
    public var activeResearchID: String?
    public var researchWeeksElapsed: Int

    public var weather: Weather
    public var statistics: Statistics
    public var notifications: NotificationCentre
    /// Per-system "have I already run today?" bookkeeping. Saved, so a reloaded game does not
    /// re-run a daily settlement it already performed.
    public var bookkeeping: SimulationBookkeeping

    // MARK: Derived (never saved — rebuilt by `rebuildDerivedState()`)

    public var navigation: NavigationState
    public var index: WorldIndex

    /// Guests currently inside the park. Maintained incrementally.
    public var guestsOnSite: Int

    /// Groups that are currently arriving or staying.
    ///
    /// The tick loop walks this rather than every group that has ever booked, so per-tick cost is
    /// proportional to who is actually in the park, not to how long the game has been running.
    public var activeGroupIDs: [GroupID]

    public init(
        catalog: ContentCatalog,
        map: MapDefinition,
        seed: UInt64,
        difficulty: Difficulty,
        startDate: GameDate,
        startingCash: Money,
        parkName: String,
        companyName: String
    ) {
        self.catalog = catalog
        self.seed = seed
        self.random = RandomStreams(masterSeed: seed)
        self.ids = IDAllocator()
        self.difficulty = difficulty
        self.scenarioID = nil
        self.parkID = map.id
        self.parkName = parkName
        self.companyName = companyName
        self.mapID = map.id
        self.regionID = map.regionID
        self.clock = SimulationClock(startDate: startDate)
        self.schedule = ScheduleQueue()
        self.tiles = MapGenerator.generate(map: map)
        self.entranceTile = map.entrance
        self.buildings = EntityStore<BuildingInstance>()
        self.guests = EntityStore<Guest>()
        self.groups = EntityStore<GuestGroup>()
        self.reservations = EntityStore<Reservation>()
        self.staff = EntityStore<StaffMember>()
        self.tasks = EntityStore<StaffTask>()
        self.reviews = []
        self.cash = startingCash
        self.loans = []
        self.ledger = Ledger()
        self.reputation = Reputation()
        self.pricing = PricingSettings()
        self.completedResearch = []
        self.activeResearchID = nil
        self.researchWeeksElapsed = 0
        self.weather = Weather()
        self.statistics = Statistics()
        self.notifications = NotificationCentre()
        self.bookkeeping = SimulationBookkeeping()
        self.navigation = NavigationState(size: map.size)
        self.index = WorldIndex()
        self.guestsOnSite = 0
        self.activeGroupIDs = []
        rebuildDerivedState()
    }

    // MARK: - Convenience lookups

    public var date: GameDate { clock.date }
    public var tick: Tick { clock.tick }

    public func definition(of building: BuildingInstance) -> BuildingDefinition? {
        catalog.buildings[building.definitionID]
    }

    public func definition(ofBuilding id: BuildingID) -> BuildingDefinition? {
        guard let instance = buildings[id] else { return nil }
        return catalog.buildings[instance.definitionID]
    }

    public var reception: BuildingInstance? {
        guard let id = index.receptionID else { return nil }
        return buildings[id]
    }

    /// Tiles a guest can stand on to use a building.
    public func accessTiles(for id: BuildingID) -> [GridPoint] {
        guard let instance = buildings[id], let definition = definition(of: instance) else { return [] }
        var result: [GridPoint] = []
        for entrance in instance.entranceTiles(definition: definition) {
            for neighbour in navigation.network.walkableNeighbours(of: entrance) where !result.contains(neighbour) {
                result.append(neighbour)
            }
        }
        // A building with no entrance offsets (decoration) is approached from any adjacent path.
        if result.isEmpty, definition.entranceOffsets.isEmpty {
            let rect = instance.footprintRect(definition: definition).expanded(by: 1).clamped(to: tiles.size)
            for point in rect.points where navigation.network.isWalkable(point) {
                result.append(point)
            }
        }
        return result
    }

    /// Tiles guests stand on to enter or leave the park. The entrance tile itself when it is a
    /// path, otherwise any walkable tile beside it.
    public var parkEntranceTiles: [GridPoint] {
        if navigation.network.isWalkable(entranceTile) { return [entranceTile] }
        return navigation.network.walkableNeighbours(of: entranceTile)
    }

    /// Is this building usable right now: connected to paths, open, and in working order?
    public func isOperational(_ id: BuildingID) -> Bool {
        guard let instance = buildings[id], let definition = definition(of: instance) else { return false }
        guard let facility = definition.facility else { return false }
        guard let state = instance.facility, state.isOpen else { return false }
        guard instance.condition > 0.25 else { return false }
        guard facility.openingHours.isOpen(atMinuteOfDay: date.minuteOfDay) else { return false }
        return !accessTiles(for: id).isEmpty
    }

    // MARK: - Money

    /// Records revenue and credits cash.
    public mutating func earn(_ amount: Money, category: RevenueCategory, reference: UInt32? = nil) {
        guard amount.cents > 0 else { return }
        cash += amount
        ledger.record(.revenue, category: category.rawValue, amount: amount, tick: tick, reference: reference)
    }

    /// Records an expense and debits cash. Cash is allowed to go negative — the player sees a
    /// warning and pays interest rather than the simulation silently refusing to work.
    public mutating func spend(_ amount: Money, category: ExpenseCategory, reference: UInt32? = nil) {
        guard amount.cents > 0 else { return }
        cash -= amount
        ledger.record(.expense, category: category.rawValue, amount: amount, tick: tick, reference: reference)
    }

    public var netWorth: Money {
        var value = cash
        for building in buildings.items {
            guard let definition = catalog.buildings[building.definitionID] else { continue }
            value += definition.constructionCost.scaled(by: 0.6 * building.condition)
        }
        for loan in loans {
            value -= loan.outstanding
        }
        return value
    }

    // MARK: - Occupancy

    public var totalUnitCapacity: Int {
        var total = 0
        for id in index.accommodationIDs {
            guard let instance = buildings[id],
                  let definition = catalog.buildings[instance.definitionID],
                  let accommodation = definition.accommodation else { continue }
            total += accommodation.capacity
        }
        return total
    }

    public var totalUnits: Int { index.accommodationIDs.count }

    public var occupiedUnits: Int {
        index.accommodationIDs.reduce(0) { partial, id in
            partial + ((buildings[id]?.accommodation?.state == .occupied) ? 1 : 0)
        }
    }

    /// Occupancy right now, `0...1`.
    public var occupancyRate: Double {
        guard totalUnits > 0 else { return 0 }
        return Double(occupiedUnits) / Double(totalUnits)
    }

    /// Mean happiness of guests on site, `0...1`.
    public var averageGuestHappiness: Double {
        var total = 0.0
        var count = 0
        for guest in guests.items where guest.activity != .offPark && guest.activity != .departed {
            total += guest.happiness
            count += 1
        }
        return count > 0 ? total / Double(count) : reputation.guestSatisfaction
    }

    // MARK: - Derived state

    /// Rebuilds everything that is computed rather than stored. Called on construction, after a
    /// build action and after loading a save.
    public mutating func rebuildDerivedState() {
        index.rebuild(buildings: buildings, catalog: catalog)
        index.rebuildReservations(reservations)
        index.rebuildGuests(guests)
        navigation.rebuildNetwork(tiles: tiles, region: nil)
        tiles.clearDirtyRegion()
        registerSharedDestinations()
        recomputeScenery()
        guestsOnSite = guests.items.reduce(0) { partial, guest in
            partial + ((guest.activity == .offPark || guest.activity == .departed) ? 0 : 1)
        }
        activeGroupIDs = groups.items
            .filter { $0.state == .arriving || $0.state == .checkedIn }
            .map(\.id)
            .sorted()
    }

    /// Marks a group as present in the park.
    public mutating func activate(group id: GroupID) {
        guard !activeGroupIDs.contains(id) else { return }
        activeGroupIDs.append(id)
    }

    /// Removes a group from the active list once its stay is over.
    public mutating func deactivate(group id: GroupID) {
        activeGroupIDs.removeAll { $0 == id }
    }

    /// Registers a flow field for every destination many guests will share.
    ///
    /// Private destinations (a guest's own cottage) deliberately do *not* get a field — they go
    /// through the budgeted A* queue instead.
    public mutating func registerSharedDestinations() {
        for id in navigation.registeredDestinations where buildings[id] == nil {
            navigation.removeDestination(id)
        }
        var shared: [BuildingID] = []
        if let reception = index.receptionID { shared.append(reception) }
        if let entrance = index.entranceID { shared.append(entrance) }
        shared.append(contentsOf: index.facilityIDs.filter { id in
            guard let instance = buildings[id], let definition = catalog.buildings[instance.definitionID],
                  let facility = definition.facility else { return false }
            switch facility.kind {
            case .reception, .entrance: return false
            default: return true
            }
        })
        for id in shared {
            let goals = accessTiles(for: id)
            guard !goals.isEmpty else {
                navigation.removeDestination(id)
                continue
            }
            navigation.registerDestination(id, goals: goals, tick: tick)
        }
    }

    /// Recomputes per-tile beauty from terrain and scenery-bearing objects.
    public mutating func recomputeScenery() {
        let size = tiles.size
        var accumulated = [Double](repeating: 0, count: size.tileCount)
        for index in 0..<size.tileCount {
            accumulated[index] = tiles.terrain(at: size.point(at: index)).sceneryValue
        }
        for building in buildings.items {
            guard let definition = catalog.buildings[building.definitionID], definition.scenery != 0 else { continue }
            let rect = building.footprintRect(definition: definition)
                .expanded(by: definition.sceneryRadius)
                .clamped(to: size)
            guard !rect.isEmpty else { continue }
            let centreX = Double(rect.minX + rect.maxX) / 2.0
            let centreY = Double(rect.minY + rect.maxY) / 2.0
            let radius = Double(max(1, definition.sceneryRadius))
            for y in rect.minY...rect.maxY {
                for x in rect.minX...rect.maxX {
                    guard let index = size.index(of: GridPoint(x: x, y: y)) else { continue }
                    let distance = ((Double(x) - centreX) * (Double(x) - centreX)
                        + (Double(y) - centreY) * (Double(y) - centreY)).squareRoot()
                    let falloff = max(0.0, 1.0 - distance / (radius + 1.0))
                    accumulated[index] += definition.scenery * falloff
                }
            }
        }
        for index in 0..<size.tileCount {
            tiles.setScenery(clamp(accumulated[index], -1.0, 1.0), at: size.point(at: index))
        }
    }

    /// Parks a guest until a future tick. Dormant guests do no per-tick work at all.
    public mutating func sleep(guest id: GuestID, untilTick wakeTick: Tick, activity: GuestActivity) {
        guests.modify(id) { guest in
            guest.activity = activity
            guest.detail = .dormant
            guest.path = nil
        }
        schedule.schedule(.guestWake, entity: id.raw, at: max(wakeTick, tick + 1))
    }

    /// Appends a review, keeping the ring bounded.
    public mutating func record(review: Review) {
        reviews.append(review)
        if reviews.count > 500 {
            reviews.removeFirst(reviews.count - 500)
        }
        reputation.apply(review: review)
        statistics.totalReviews += 1
    }
}
