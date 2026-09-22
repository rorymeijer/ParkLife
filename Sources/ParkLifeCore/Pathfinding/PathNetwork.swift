import Foundation

/// The walkable graph, derived from the tile map.
///
/// Stored as flat arrays indexed row-major, which is what makes A* and the Dijkstra sweeps fast
/// enough to run inside a tick budget. This is derived state: it is rebuilt from the tile map and
/// never saved.
public struct PathNetwork {

    public let size: GridSize

    public private(set) var walkable: [Bool]
    /// Traversal cost per tile, in the same units as `SurfaceType.movementCost`.
    public private(set) var cost: [UInt16]
    /// Connectivity label per tile; `-1` when not walkable.
    public private(set) var component: [Int32]
    public private(set) var componentCount: Int

    public init(size: GridSize) {
        self.size = size
        let count = size.tileCount
        self.walkable = [Bool](repeating: false, count: count)
        self.cost = [UInt16](repeating: 0, count: count)
        self.component = [Int32](repeating: -1, count: count)
        self.componentCount = 0
    }

    // MARK: - Queries

    public func isWalkable(_ point: GridPoint) -> Bool {
        guard let index = size.index(of: point) else { return false }
        return walkable[index]
    }

    public func cost(at point: GridPoint) -> Int {
        guard let index = size.index(of: point) else { return Int(UInt16.max) }
        return Int(cost[index])
    }

    public func component(at point: GridPoint) -> Int32 {
        guard let index = size.index(of: point) else { return -1 }
        return component[index]
    }

    /// Instant reachability test. Guests use this to notice an unreachable destination without
    /// running — and failing — a full search (brief §10).
    public func areConnected(_ a: GridPoint, _ b: GridPoint) -> Bool {
        let left = component(at: a)
        guard left >= 0 else { return false }
        return left == component(at: b)
    }

    /// Walkable tiles next to `point`, e.g. the tiles a guest can stand on to enter a building.
    public func walkableNeighbours(of point: GridPoint) -> [GridPoint] {
        point.orthogonalNeighbours.filter { isWalkable($0) }
    }

    // MARK: - Rebuilding

    /// Recomputes walkability/cost for `region` only.
    ///
    /// Connectivity labelling is then recomputed globally, because removing a single path tile can
    /// split one component into two — there is no cheap local answer to that. The labelling pass is
    /// a linear flood fill and is measured in microseconds at slice-map sizes.
    public mutating func update(
        tiles: TileMap,
        region: GridRect?,
        additionalWalkable: Set<Int> = []
    ) {
        let rect = (region ?? GridRect(x: 0, y: 0, width: size.width, height: size.height))
            .clamped(to: size)
        if !rect.isEmpty {
            for y in rect.minY...rect.maxY {
                for x in rect.minX...rect.maxX {
                    let point = GridPoint(x: x, y: y)
                    guard let index = size.index(of: point) else { continue }
                    let isPath = tiles.isWalkable(at: point) || additionalWalkable.contains(index)
                    walkable[index] = isPath
                    cost[index] = isPath ? UInt16(tiles.surface(at: point).movementCost) : 0
                }
            }
        }
        labelComponents()
    }

    private mutating func labelComponents() {
        let count = size.tileCount
        for index in 0..<count {
            component[index] = walkable[index] ? -2 : -1
        }
        var label: Int32 = 0
        var stack: [Int] = []
        stack.reserveCapacity(256)

        for start in 0..<count where component[start] == -2 {
            component[start] = label
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            while let index = stack.popLast() {
                let x = index % size.width
                let y = index / size.width
                if x > 0 {
                    let neighbour = index - 1
                    if component[neighbour] == -2 { component[neighbour] = label; stack.append(neighbour) }
                }
                if x < size.width - 1 {
                    let neighbour = index + 1
                    if component[neighbour] == -2 { component[neighbour] = label; stack.append(neighbour) }
                }
                if y > 0 {
                    let neighbour = index - size.width
                    if component[neighbour] == -2 { component[neighbour] = label; stack.append(neighbour) }
                }
                if y < size.height - 1 {
                    let neighbour = index + size.width
                    if component[neighbour] == -2 { component[neighbour] = label; stack.append(neighbour) }
                }
            }
            label += 1
        }
        componentCount = Int(label)
    }

    /// Number of walkable tiles — used by tests and the debug overlay.
    public var walkableCount: Int {
        walkable.reduce(0) { $0 + ($1 ? 1 : 0) }
    }
}
