import Foundation

public enum TerrainType: UInt8, CaseIterable, Codable {
    case grass = 0
    case sand = 1
    case water = 2
    case forest = 3
    case rock = 4
    case paved = 5

    public var localizationKey: String { "terrain.\(self)" }

    /// Can a building or path be placed here without terraforming?
    public var isBuildable: Bool {
        switch self {
        case .grass, .sand, .paved, .forest: return true
        case .water, .rock: return false
        }
    }

    /// Beauty contribution of the bare terrain, `-1...1`.
    public var sceneryValue: Double {
        switch self {
        case .grass: return 0.15
        case .sand: return 0.05
        case .water: return 0.55
        case .forest: return 0.50
        case .rock: return 0.0
        case .paved: return -0.05
        }
    }
}

/// What has been laid on top of the terrain.
public enum SurfaceType: UInt8, CaseIterable, Codable {
    case none = 0
    case footpath = 1
    case cyclePath = 2
    case plaza = 3
    case road = 4
    case bridge = 5

    public var localizationKey: String { "surface.\(self)" }

    /// Can guests and staff walk here?
    public var isWalkable: Bool {
        switch self {
        case .none, .road: return false
        case .footpath, .cyclePath, .plaza, .bridge: return true
        }
    }

    /// Relative traversal cost; plazas are pleasant, bridges slightly slower.
    public var movementCost: Int {
        switch self {
        case .footpath: return 10
        case .cyclePath: return 10
        case .plaza: return 9
        case .bridge: return 12
        case .road, .none: return 1_000
        }
    }
}

/// The terrain and surface grid.
///
/// Flat arrays rather than a grid of objects: this is read constantly by pathfinding and the
/// renderer, and contiguous storage keeps it cache friendly and trivially serialisable.
public struct TileMap {

    public let size: GridSize

    public private(set) var elevation: [Int8]
    public private(set) var terrainRaw: [UInt8]
    public private(set) var surfaceRaw: [UInt8]
    /// `0` means no building; otherwise the raw value of the occupying `BuildingID`.
    public private(set) var buildingRaw: [UInt32]
    /// Cached beauty per tile, `-100...100`, recomputed when scenery-bearing objects change.
    public private(set) var sceneryRaw: [Int8]

    /// Region changed since the last time derived state was rebuilt.
    public private(set) var dirtyRegion: GridRect?

    public init(size: GridSize) {
        self.size = size
        let count = size.tileCount
        self.elevation = [Int8](repeating: 0, count: count)
        self.terrainRaw = [UInt8](repeating: TerrainType.grass.rawValue, count: count)
        self.surfaceRaw = [UInt8](repeating: SurfaceType.none.rawValue, count: count)
        self.buildingRaw = [UInt32](repeating: 0, count: count)
        self.sceneryRaw = [Int8](repeating: 15, count: count)
        self.dirtyRegion = GridRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    public init(
        size: GridSize,
        elevation: [Int8],
        terrainRaw: [UInt8],
        surfaceRaw: [UInt8],
        buildingRaw: [UInt32],
        sceneryRaw: [Int8]
    ) {
        self.size = size
        self.elevation = elevation
        self.terrainRaw = terrainRaw
        self.surfaceRaw = surfaceRaw
        self.buildingRaw = buildingRaw
        self.sceneryRaw = sceneryRaw
        self.dirtyRegion = GridRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    // MARK: - Reads

    public func contains(_ point: GridPoint) -> Bool {
        size.contains(point)
    }

    public func terrain(at point: GridPoint) -> TerrainType {
        guard let index = size.index(of: point) else { return .water }
        return TerrainType(rawValue: terrainRaw[index]) ?? .grass
    }

    public func surface(at point: GridPoint) -> SurfaceType {
        guard let index = size.index(of: point) else { return .none }
        return SurfaceType(rawValue: surfaceRaw[index]) ?? .none
    }

    public func elevation(at point: GridPoint) -> Int {
        guard let index = size.index(of: point) else { return 0 }
        return Int(elevation[index])
    }

    public func building(at point: GridPoint) -> BuildingID? {
        guard let index = size.index(of: point) else { return nil }
        let raw = buildingRaw[index]
        return raw == 0 ? nil : BuildingID(raw: raw)
    }

    /// Beauty of a tile, `-1...1`.
    public func scenery(at point: GridPoint) -> Double {
        guard let index = size.index(of: point) else { return 0 }
        return Double(sceneryRaw[index]) / 100.0
    }

    public func isEmpty(at point: GridPoint) -> Bool {
        guard let index = size.index(of: point) else { return false }
        return buildingRaw[index] == 0 && surfaceRaw[index] == SurfaceType.none.rawValue
    }

    /// Walkable for pedestrians: a walkable surface with no building on top.
    public func isWalkable(at point: GridPoint) -> Bool {
        guard let index = size.index(of: point) else { return false }
        guard buildingRaw[index] == 0 else { return false }
        return SurfaceType(rawValue: surfaceRaw[index])?.isWalkable ?? false
    }

    public func movementCost(at point: GridPoint) -> Int {
        surface(at: point).movementCost
    }

    // MARK: - Writes

    public mutating func setTerrain(_ type: TerrainType, at point: GridPoint) {
        guard let index = size.index(of: point) else { return }
        terrainRaw[index] = type.rawValue
        markDirty(point)
    }

    public mutating func setSurface(_ type: SurfaceType, at point: GridPoint) {
        guard let index = size.index(of: point) else { return }
        surfaceRaw[index] = type.rawValue
        markDirty(point)
    }

    public mutating func setElevation(_ value: Int, at point: GridPoint) {
        guard let index = size.index(of: point) else { return }
        elevation[index] = Int8(clamp(value, -8, 12))
        markDirty(point)
    }

    public mutating func setBuilding(_ id: BuildingID?, at point: GridPoint) {
        guard let index = size.index(of: point) else { return }
        buildingRaw[index] = id?.raw ?? 0
        markDirty(point)
    }

    public mutating func setScenery(_ value: Double, at point: GridPoint) {
        guard let index = size.index(of: point) else { return }
        sceneryRaw[index] = Int8(clamp(Int((value * 100).rounded()), -100, 100))
    }

    public mutating func markDirty(_ point: GridPoint) {
        let rect = GridRect(x: point.x, y: point.y, width: 1, height: 1)
        dirtyRegion = dirtyRegion.map { $0.union(rect) } ?? rect
    }

    public mutating func markDirty(_ rect: GridRect) {
        guard !rect.isEmpty else { return }
        dirtyRegion = dirtyRegion.map { $0.union(rect) } ?? rect
    }

    public mutating func clearDirtyRegion() {
        dirtyRegion = nil
    }

    /// Average beauty of the tiles around a point — the measured basis for "what a lovely park".
    public func averageScenery(around point: GridPoint, radius: Int) -> Double {
        let rect = GridRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2 + 1,
            height: radius * 2 + 1
        ).clamped(to: size)
        guard !rect.isEmpty else { return 0 }
        var total = 0.0
        var count = 0
        for y in rect.minY...rect.maxY {
            for x in rect.minX...rect.maxX {
                total += scenery(at: GridPoint(x: x, y: y))
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }
}
