import Foundation

/// Run-length encoded terrain grids.
///
/// A 96×96 map is 9 216 cells of mostly the same value; RLE collapses that to a few hundred
/// numbers and keeps save files small without a binary format.
public struct TerrainPayload: Codable {

    public static let currentEncoding = "rle-v1"

    public let encoding: String
    public let width: Int
    public let height: Int
    public let elevation: [Int]
    public let terrain: [Int]
    public let surface: [Int]
    public let building: [Int]
    public let scenery: [Int]

    public init(tileMap: TileMap) {
        self.encoding = TerrainPayload.currentEncoding
        self.width = tileMap.size.width
        self.height = tileMap.size.height
        self.elevation = RunLength.encode(tileMap.elevation.map { Int($0) })
        self.terrain = RunLength.encode(tileMap.terrainRaw.map { Int($0) })
        self.surface = RunLength.encode(tileMap.surfaceRaw.map { Int($0) })
        self.building = RunLength.encode(tileMap.buildingRaw.map { Int($0) })
        self.scenery = RunLength.encode(tileMap.sceneryRaw.map { Int($0) })
    }

    public func makeTileMap() throws -> TileMap {
        guard encoding == TerrainPayload.currentEncoding else {
            throw SaveError.corrupted("Unknown terrain encoding '\(encoding)'")
        }
        let size = GridSize(width: width, height: height)
        let count = size.tileCount
        let elevationValues = try RunLength.decode(elevation, expectedCount: count)
        let terrainValues = try RunLength.decode(terrain, expectedCount: count)
        let surfaceValues = try RunLength.decode(surface, expectedCount: count)
        let buildingValues = try RunLength.decode(building, expectedCount: count)
        let sceneryValues = try RunLength.decode(scenery, expectedCount: count)
        return TileMap(
            size: size,
            elevation: elevationValues.map { Int8(clamp($0, -128, 127)) },
            terrainRaw: terrainValues.map { UInt8(clamp($0, 0, 255)) },
            surfaceRaw: surfaceValues.map { UInt8(clamp($0, 0, 255)) },
            buildingRaw: buildingValues.map { UInt32(max(0, $0)) },
            sceneryRaw: sceneryValues.map { Int8(clamp($0, -128, 127)) }
        )
    }
}

/// The saved world.
///
/// Derived state — the path network, flow fields, connectivity labels and the world index
/// — is deliberately absent: it is rebuilt on load, so a save can never carry a stale cache.
public struct SaveGame: Codable {

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

    public var clock: SimulationClock
    public var schedule: ScheduleQueue

    public var terrain: TerrainPayload
    public var entranceX: Int
    public var entranceY: Int
    /// Crowding per tile, run-length encoded. Accumulated state rather than derived, so it is
    /// saved: without it a reloaded game would diverge from the one that was saved.
    public var congestion: [Int]

    public var buildings: EntityStore<BuildingInstance>
    public var guests: EntityStore<Guest>
    public var groups: EntityStore<GuestGroup>
    public var reservations: EntityStore<Reservation>
    public var staff: EntityStore<StaffMember>
    public var tasks: EntityStore<StaffTask>
    public var reviews: [Review]

    public var cash: Money
    public var loans: [Loan]
    public var ledger: Ledger
    public var reputation: Reputation
    public var pricing: PricingSettings
    public var completedResearch: [String]
    public var activeResearchID: String?
    public var researchWeeksElapsed: Int

    public var weather: Weather
    public var statistics: Statistics
    public var notifications: NotificationCentre
    public var bookkeeping: SimulationBookkeeping
    public var guestsOnSite: Int

    public init(world: World) throws {
        self.seed = world.seed
        self.random = world.random
        self.ids = world.ids
        self.difficulty = world.difficulty
        self.scenarioID = world.scenarioID
        self.parkID = world.parkID
        self.parkName = world.parkName
        self.companyName = world.companyName
        self.mapID = world.mapID
        self.regionID = world.regionID
        self.clock = world.clock
        self.schedule = world.schedule
        self.terrain = TerrainPayload(tileMap: world.tiles)
        self.entranceX = world.entranceTile.x
        self.entranceY = world.entranceTile.y
        self.congestion = RunLength.encode(world.navigation.congestion.map { Int($0) })
        self.buildings = world.buildings
        self.guests = world.guests
        self.groups = world.groups
        self.reservations = world.reservations
        self.staff = world.staff
        self.tasks = world.tasks
        self.reviews = world.reviews
        self.cash = world.cash
        self.loans = world.loans
        self.ledger = world.ledger
        self.reputation = world.reputation
        self.pricing = world.pricing
        self.completedResearch = world.completedResearch
        self.activeResearchID = world.activeResearchID
        self.researchWeeksElapsed = world.researchWeeksElapsed
        self.weather = world.weather
        self.statistics = world.statistics
        self.notifications = world.notifications
        self.bookkeeping = world.bookkeeping
        self.guestsOnSite = world.guestsOnSite
    }

    /// Rebuilds a playable world. Content comes from the running build, not from the save.
    public func makeWorld(catalog: ContentCatalog) throws -> World {
        guard let map = catalog.maps[mapID] else {
            throw SaveError.contentMissing("map '\(mapID)'")
        }
        var world = World(
            catalog: catalog,
            map: map,
            seed: seed,
            difficulty: difficulty,
            startDate: clock.date,
            startingCash: cash,
            parkName: parkName,
            companyName: companyName
        )
        world.random = random
        world.ids = ids
        world.scenarioID = scenarioID
        world.parkID = parkID
        world.regionID = regionID
        world.clock = clock
        world.schedule = schedule
        world.tiles = try terrain.makeTileMap()
        world.entranceTile = GridPoint(x: entranceX, y: entranceY)
        world.buildings = buildings
        world.guests = guests
        world.groups = groups
        world.reservations = reservations
        world.staff = staff
        world.tasks = tasks
        world.reviews = reviews
        world.cash = cash
        world.loans = loans
        world.ledger = ledger
        world.reputation = reputation
        world.pricing = pricing
        world.completedResearch = completedResearch
        world.activeResearchID = activeResearchID
        world.researchWeeksElapsed = researchWeeksElapsed
        world.weather = weather
        world.statistics = statistics
        world.notifications = notifications
        world.bookkeeping = bookkeeping
        world.guestsOnSite = guestsOnSite
        world.rebuildDerivedState()
        let congestionValues = try RunLength.decode(congestion, expectedCount: world.tiles.size.tileCount)
        world.navigation.restoreCongestion(congestionValues.map { UInt8(clamp($0, 0, 255)) })
        return world
    }
}
