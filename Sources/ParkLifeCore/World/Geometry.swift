import Foundation

/// Integer tile coordinate. `+x` runs east, `+y` runs south, in grid space.
public struct GridPoint: Hashable, Codable, CustomStringConvertible {

    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public static let zero = GridPoint(x: 0, y: 0)

    public func offset(dx: Int, dy: Int) -> GridPoint {
        GridPoint(x: x + dx, y: y + dy)
    }

    public func neighbour(_ direction: GridDirection) -> GridPoint {
        offset(dx: direction.dx, dy: direction.dy)
    }

    /// Manhattan distance — the only distance that matches 4-way movement on the path network.
    public func manhattanDistance(to other: GridPoint) -> Int {
        abs(x - other.x) + abs(y - other.y)
    }

    public func chebyshevDistance(to other: GridPoint) -> Int {
        max(abs(x - other.x), abs(y - other.y))
    }

    public var orthogonalNeighbours: [GridPoint] {
        GridDirection.allCases.map { neighbour($0) }
    }

    public var description: String { "(\(x), \(y))" }
}

public struct GridSize: Hashable, Codable {

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var tileCount: Int { width * height }

    public func contains(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x < width && point.y < height
    }

    /// Row-major index, or `nil` when the point is outside.
    public func index(of point: GridPoint) -> Int? {
        guard contains(point) else { return nil }
        return point.y * width + point.x
    }

    public func point(at index: Int) -> GridPoint {
        GridPoint(x: index % width, y: index / width)
    }
}

public struct GridRect: Hashable, Codable {

    public var origin: GridPoint
    public var size: GridSize

    public init(origin: GridPoint, size: GridSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.init(origin: GridPoint(x: x, y: y), size: GridSize(width: width, height: height))
    }

    public var minX: Int { origin.x }
    public var minY: Int { origin.y }
    public var maxX: Int { origin.x + size.width - 1 }
    public var maxY: Int { origin.y + size.height - 1 }

    public func contains(_ point: GridPoint) -> Bool {
        guard !isEmpty else { return false }
        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersects(_ other: GridRect) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return !(other.minX > maxX || other.maxX < minX || other.minY > maxY || other.maxY < minY)
    }

    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    public var points: [GridPoint] {
        guard !isEmpty else { return [] }
        var result: [GridPoint] = []
        result.reserveCapacity(size.tileCount)
        for y in minY...maxY {
            for x in minX...maxX {
                result.append(GridPoint(x: x, y: y))
            }
        }
        return result
    }

    /// Grows the rect by `amount` tiles on every side — used for dirty regions.
    public func expanded(by amount: Int) -> GridRect {
        GridRect(
            x: minX - amount,
            y: minY - amount,
            width: size.width + amount * 2,
            height: size.height + amount * 2
        )
    }

    public func union(_ other: GridRect) -> GridRect {
        let lowX = Swift.min(minX, other.minX)
        let lowY = Swift.min(minY, other.minY)
        let highX = Swift.max(maxX, other.maxX)
        let highY = Swift.max(maxY, other.maxY)
        return GridRect(x: lowX, y: lowY, width: highX - lowX + 1, height: highY - lowY + 1)
    }

    public func clamped(to size: GridSize) -> GridRect {
        let lowX = Swift.max(0, minX)
        let lowY = Swift.max(0, minY)
        let highX = Swift.min(size.width - 1, maxX)
        let highY = Swift.min(size.height - 1, maxY)
        guard highX >= lowX, highY >= lowY else {
            return GridRect(x: 0, y: 0, width: 0, height: 0)
        }
        return GridRect(x: lowX, y: lowY, width: highX - lowX + 1, height: highY - lowY + 1)
    }
}

public enum GridDirection: Int, CaseIterable, Codable {
    case north = 0
    case east = 1
    case south = 2
    case west = 3

    public var dx: Int {
        switch self {
        case .north: return 0
        case .east: return 1
        case .south: return 0
        case .west: return -1
        }
    }

    public var dy: Int {
        switch self {
        case .north: return -1
        case .east: return 0
        case .south: return 1
        case .west: return 0
        }
    }

    public var opposite: GridDirection {
        switch self {
        case .north: return .south
        case .east: return .west
        case .south: return .north
        case .west: return .east
        }
    }

    public func rotated(by rotation: Rotation) -> GridDirection {
        GridDirection(rawValue: (rawValue + rotation.quarterTurns) % 4) ?? self
    }
}

/// Object placement rotation, in quarter turns.
public enum Rotation: Int, CaseIterable, Codable {
    case none = 0
    case quarter = 1
    case half = 2
    case threeQuarter = 3

    public var quarterTurns: Int { rawValue }

    public var next: Rotation {
        Rotation(rawValue: (rawValue + 1) % 4) ?? .none
    }

    /// Rotates an offset inside a footprint of the given size.
    public func apply(to offset: GridPoint, in size: GridSize) -> GridPoint {
        switch self {
        case .none:
            return offset
        case .quarter:
            return GridPoint(x: size.height - 1 - offset.y, y: offset.x)
        case .half:
            return GridPoint(x: size.width - 1 - offset.x, y: size.height - 1 - offset.y)
        case .threeQuarter:
            return GridPoint(x: offset.y, y: size.width - 1 - offset.x)
        }
    }

    /// Footprint dimensions after rotation.
    public func apply(to size: GridSize) -> GridSize {
        switch self {
        case .none, .half:
            return size
        case .quarter, .threeQuarter:
            return GridSize(width: size.height, height: size.width)
        }
    }
}

/// Continuous position in tile units — guests live here, so movement can be interpolated
/// smoothly by the renderer without the simulation knowing about frames.
public struct WorldPoint: Hashable, Codable {

    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ tile: GridPoint) {
        self.x = Double(tile.x) + 0.5
        self.y = Double(tile.y) + 0.5
    }

    public var tile: GridPoint {
        GridPoint(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)))
    }

    public func distance(to other: WorldPoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func lerp(_ from: WorldPoint, _ to: WorldPoint, _ t: Double) -> WorldPoint {
        WorldPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
    }
}
