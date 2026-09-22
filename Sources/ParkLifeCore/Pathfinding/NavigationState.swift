import Foundation

/// A queued request for a private path (one that does not justify its own flow field).
public struct PathRequest {
    public let guestID: GuestID
    public let start: GridPoint
    public let goals: [GridPoint]

    public init(guestID: GuestID, start: GridPoint, goals: [GridPoint]) {
        self.guestID = guestID
        self.start = start
        self.goals = goals
    }
}

public struct PathResult {
    public let guestID: GuestID
    public let tiles: [GridPoint]?
}

/// All navigation-related derived state.
///
/// None of this is saved: it is rebuilt from the tile map on load (`World.rebuildDerivedState`).
/// Keeping it out of the save is what stops save files ballooning and what guarantees a save can
/// never carry a stale path cache.
public struct NavigationState {

    public private(set) var network: PathNetwork
    /// Crowding per tile, `0...255`, decayed each tick.
    public private(set) var congestion: [UInt8]

    /// Cached flow fields keyed by the raw id of the destination building.
    private var fields: [UInt32: FlowField]
    /// Destinations whose field must be rebuilt.
    private var staleFields: Set<UInt32>

    private var requestQueue: [PathRequest]

    /// Budget for A* work per tick, in explored nodes.
    public var nodeBudgetPerTick: Int = 6_000
    /// How many flow fields may be rebuilt in one tick.
    public var fieldRebuildsPerTick: Int = 2

    public private(set) var lastTickNodesExplored: Int = 0
    public private(set) var lastTickFieldRebuilds: Int = 0

    public init(size: GridSize) {
        self.network = PathNetwork(size: size)
        self.congestion = [UInt8](repeating: 0, count: size.tileCount)
        self.fields = [:]
        self.staleFields = []
        self.requestQueue = []
    }

    public var size: GridSize { network.size }

    // MARK: - Network maintenance

    /// Applies a change to the walkable network. `region` is the dirty rect from the tile map.
    public mutating func rebuildNetwork(tiles: TileMap, region: GridRect?) {
        network.update(tiles: tiles, region: region)
        // Any change can alter distances anywhere in the affected component, so every cached
        // field is marked stale and rebuilt lazily, a couple per tick.
        staleFields.formUnion(fields.keys)
    }

    // MARK: - Flow fields

    /// Registers (or refreshes) a destination that many guests will head for.
    public mutating func registerDestination(_ id: BuildingID, goals: [GridPoint], tick: Tick) {
        var field = FlowField(size: network.size)
        field.build(goals: goals, network: network, tick: tick)
        fields[id.raw] = field
        staleFields.remove(id.raw)
    }

    public mutating func removeDestination(_ id: BuildingID) {
        fields[id.raw] = nil
        staleFields.remove(id.raw)
    }

    public func field(for id: BuildingID) -> FlowField? {
        fields[id.raw]
    }

    public var registeredDestinations: [BuildingID] {
        fields.keys.sorted().map { BuildingID(raw: $0) }
    }

    /// Rebuilds at most `fieldRebuildsPerTick` stale fields. Called once per tick.
    public mutating func refreshStaleFields(
        goalsProvider: (BuildingID) -> [GridPoint],
        tick: Tick
    ) {
        lastTickFieldRebuilds = 0
        guard !staleFields.isEmpty else { return }
        // Sorted so rebuild order is deterministic.
        let candidates = staleFields.sorted().prefix(fieldRebuildsPerTick)
        for raw in candidates {
            let id = BuildingID(raw: raw)
            let goals = goalsProvider(id)
            if goals.isEmpty {
                fields[raw] = nil
            } else {
                var field = FlowField(size: network.size)
                field.build(goals: goals, network: network, tick: tick)
                fields[raw] = field
            }
            staleFields.remove(raw)
            lastTickFieldRebuilds += 1
        }
    }

    /// Distance in cost units from a tile to a registered destination.
    public func distance(from point: GridPoint, to destination: BuildingID) -> Int? {
        fields[destination.raw]?.cost(from: point)
    }

    /// Distance expressed in tiles, which is what guest expectations are phrased in.
    public func tileDistance(from point: GridPoint, to destination: BuildingID) -> Int? {
        guard let cost = distance(from: point, to: destination) else { return nil }
        return cost / SurfaceType.footpath.movementCost
    }

    // MARK: - Path requests

    public mutating func enqueue(_ request: PathRequest) {
        requestQueue.append(request)
    }

    public var pendingRequestCount: Int { requestQueue.count }

    /// Services the queue within this tick's node budget.
    ///
    /// Requests that do not fit stay queued, so a burst of guests deciding at the same moment
    /// spreads its cost over several ticks instead of spiking one.
    public mutating func serviceRequests() -> [PathResult] {
        lastTickNodesExplored = 0
        guard !requestQueue.isEmpty else { return [] }
        var results: [PathResult] = []
        var budget = nodeBudgetPerTick

        while budget > 0, !requestQueue.isEmpty {
            let request = requestQueue.removeFirst()
            let result = AStarPathfinder.findPath(
                from: request.start,
                toAnyOf: request.goals,
                network: network,
                nodeBudget: min(budget, 4_000)
            )
            let explored = result?.nodesExplored ?? min(budget, 4_000)
            budget -= max(1, explored)
            lastTickNodesExplored += max(1, explored)
            results.append(PathResult(guestID: request.guestID, tiles: result?.tiles))
        }
        return results
    }

    /// Immediate path, bypassing the queue. Used for short hops and by tests.
    public func immediatePath(from start: GridPoint, toAnyOf goals: [GridPoint]) -> [GridPoint]? {
        AStarPathfinder.findPath(from: start, toAnyOf: goals, network: network, nodeBudget: 4_000)?.tiles
    }

    // MARK: - Congestion

    public mutating func noteOccupancy(at point: GridPoint) {
        guard let index = network.size.index(of: point) else { return }
        congestion[index] = UInt8(min(255, Int(congestion[index]) + 12))
    }

    /// Exponential-ish decay so crowding fades once people move on.
    public mutating func decayCongestion() {
        for index in congestion.indices where congestion[index] > 0 {
            congestion[index] = congestion[index] > 3 ? congestion[index] - 3 : 0
        }
    }

    /// Crowding at a tile, `0...1`.
    public func congestionLevel(at point: GridPoint) -> Double {
        guard let index = network.size.index(of: point) else { return 0 }
        return Double(congestion[index]) / 255.0
    }

    public mutating func resetCongestion() {
        for index in congestion.indices {
            congestion[index] = 0
        }
    }

    /// Restores crowding from a save. Congestion is accumulated state, not something that can be
    /// recomputed, so it travels with the save file.
    public mutating func restoreCongestion(_ values: [UInt8]) {
        guard values.count == congestion.count else { return }
        congestion = values
    }
}
