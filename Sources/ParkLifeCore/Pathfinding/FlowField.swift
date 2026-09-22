import Foundation

/// A Dijkstra field from one destination over the whole walkable network.
///
/// One sweep serves any number of guests: navigating becomes a single array lookup per step
/// instead of a search. This is the answer to "thousands of guests heading for the pool".
public struct FlowField {

    public let size: GridSize
    /// Accumulated cost to the destination; `Int32.max` means unreachable.
    public private(set) var distance: [Int32]
    /// Index of the `GridDirection` to step next, or `-1`.
    public private(set) var step: [Int8]
    /// Tick the field was built on, used to decide when a rebuild is worthwhile.
    public var builtAtTick: Tick

    private struct Node: Comparable {
        let distance: Int32
        let index: Int32

        static func < (lhs: Node, rhs: Node) -> Bool {
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.index < rhs.index
        }
    }

    public init(size: GridSize) {
        self.size = size
        self.distance = [Int32](repeating: Int32.max, count: size.tileCount)
        self.step = [Int8](repeating: -1, count: size.tileCount)
        self.builtAtTick = 0
    }

    /// Builds the field from a set of destination tiles.
    ///
    /// The field depends only on the *static* walkable network, never on live crowding. That keeps
    /// it a pure function of the map: it can be rebuilt identically after loading a save, and it
    /// does not need rebuilding every time a crowd moves. Congestion still shapes behaviour — it
    /// lowers a facility's appeal and feeds the "too crowded" thought — it just does not reroute
    /// traffic. Congestion-aware routing belongs with the Phase 4 traffic work.
    public mutating func build(
        goals: [GridPoint],
        network: PathNetwork,
        tick: Tick = 0
    ) {
        for index in distance.indices {
            distance[index] = Int32.max
            step[index] = -1
        }
        builtAtTick = tick

        var heap = MinHeap<Node>()
        for goal in goals {
            guard let index = size.index(of: goal), network.walkable[index] else { continue }
            distance[index] = 0
            heap.insert(Node(distance: 0, index: Int32(index)))
        }
        guard !heap.isEmpty else { return }

        while let node = heap.removeMin() {
            let index = Int(node.index)
            if node.distance > distance[index] { continue }
            let x = index % size.width
            let y = index / size.width

            // Direction indices match GridDirection: 0 north, 1 east, 2 south, 3 west.
            // `stepFromNeighbour` is the direction the *neighbour* must walk to reach this tile.
            if x > 0 { relax(index - 1, from: index, stepFromNeighbour: 1, network: network, heap: &heap) }
            if x < size.width - 1 { relax(index + 1, from: index, stepFromNeighbour: 3, network: network, heap: &heap) }
            if y > 0 { relax(index - size.width, from: index, stepFromNeighbour: 2, network: network, heap: &heap) }
            if y < size.height - 1 { relax(index + size.width, from: index, stepFromNeighbour: 0, network: network, heap: &heap) }
        }
    }

    private mutating func relax(
        _ neighbour: Int,
        from index: Int,
        stepFromNeighbour: Int8,
        network: PathNetwork,
        heap: inout MinHeap<Node>
    ) {
        guard network.walkable[neighbour] else { return }
        let edgeCost = Int32(network.cost[neighbour])
        let candidate = distance[index] + edgeCost
        if candidate < distance[neighbour] {
            distance[neighbour] = candidate
            step[neighbour] = stepFromNeighbour
            heap.insert(Node(distance: candidate, index: Int32(neighbour)))
        }
    }

    public func isReachable(from point: GridPoint) -> Bool {
        guard let index = size.index(of: point) else { return false }
        return distance[index] != Int32.max
    }

    public func cost(from point: GridPoint) -> Int? {
        guard let index = size.index(of: point), distance[index] != Int32.max else { return nil }
        return Int(distance[index])
    }

    public func nextStep(from point: GridPoint) -> GridDirection? {
        guard let index = size.index(of: point) else { return nil }
        let raw = step[index]
        guard raw >= 0 else { return nil }
        return GridDirection(rawValue: Int(raw))
    }

    /// Walks the field to produce a concrete path. `limit` guards against a corrupt field.
    public func path(from point: GridPoint, limit: Int = 2_048) -> [GridPoint]? {
        guard isReachable(from: point) else { return nil }
        var tiles: [GridPoint] = [point]
        var cursor = point
        var guardCounter = 0
        while let direction = nextStep(from: cursor) {
            cursor = cursor.neighbour(direction)
            tiles.append(cursor)
            guardCounter += 1
            if guardCounter > limit { return nil }
        }
        return tiles
    }
}
