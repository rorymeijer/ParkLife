import Foundation

/// Position in rendered points.
public struct ScreenPoint: Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Grid ↔ screen conversion for the 2.5D isometric view.
///
/// This lives in the core, not the renderer, because build previews, tile picking and the debug
/// overlays all need the same maths — but note that the *simulation itself* never calls it. Camera
/// rotation rotates coordinates here, so simulation grid coordinates are never touched by camera
/// state.
public struct IsometricProjection {

    public static let defaultTileWidth: Double = 64
    public static let defaultTileHeight: Double = 32
    public static let defaultElevationStep: Double = 16

    public let tileWidth: Double
    public let tileHeight: Double
    public let elevationStep: Double
    public let mapSize: GridSize
    public let rotation: Rotation

    public init(
        mapSize: GridSize,
        rotation: Rotation = .none,
        tileWidth: Double = IsometricProjection.defaultTileWidth,
        tileHeight: Double = IsometricProjection.defaultTileHeight,
        elevationStep: Double = IsometricProjection.defaultElevationStep
    ) {
        self.mapSize = mapSize
        self.rotation = rotation
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.elevationStep = elevationStep
    }

    public func withRotation(_ newRotation: Rotation) -> IsometricProjection {
        IsometricProjection(
            mapSize: mapSize,
            rotation: newRotation,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            elevationStep: elevationStep
        )
    }

    /// Applies camera rotation to a continuous world position.
    public func rotate(_ point: WorldPoint) -> WorldPoint {
        let width = Double(mapSize.width)
        let height = Double(mapSize.height)
        switch rotation {
        case .none:
            return point
        case .quarter:
            return WorldPoint(x: height - point.y, y: point.x)
        case .half:
            return WorldPoint(x: width - point.x, y: height - point.y)
        case .threeQuarter:
            return WorldPoint(x: point.y, y: width - point.x)
        }
    }

    /// Inverse of `rotate`.
    public func unrotate(_ point: WorldPoint) -> WorldPoint {
        let width = Double(mapSize.width)
        let height = Double(mapSize.height)
        switch rotation {
        case .none:
            return point
        case .quarter:
            return WorldPoint(x: point.y, y: height - point.x)
        case .half:
            return WorldPoint(x: width - point.x, y: height - point.y)
        case .threeQuarter:
            return WorldPoint(x: width - point.y, y: point.x)
        }
    }

    /// Grid/world position → screen point, at zoom 1.
    public func project(_ point: WorldPoint, elevation: Int = 0) -> ScreenPoint {
        let rotated = rotate(point)
        return ScreenPoint(
            x: (rotated.x - rotated.y) * (tileWidth / 2),
            y: (rotated.x + rotated.y) * (tileHeight / 2) - Double(elevation) * elevationStep
        )
    }

    public func project(_ tile: GridPoint, elevation: Int = 0) -> ScreenPoint {
        project(WorldPoint(tile), elevation: elevation)
    }

    /// Screen point → world position on the ground plane (elevation 0).
    public func unproject(_ point: ScreenPoint) -> WorldPoint {
        let halfWidth = tileWidth / 2
        let halfHeight = tileHeight / 2
        let rotatedX = (point.x / halfWidth + point.y / halfHeight) / 2
        let rotatedY = (point.y / halfHeight - point.x / halfWidth) / 2
        return unrotate(WorldPoint(x: rotatedX, y: rotatedY))
    }

    /// Screen point → tile, compensating for the elevation of the tile under the cursor.
    ///
    /// Analytic rather than per-pixel hit testing: O(1) plus a short walk down the elevation
    /// candidates, which keeps picking cheap even on large maps.
    public func tile(at point: ScreenPoint, elevationLookup: (GridPoint) -> Int) -> GridPoint? {
        // Try progressively lower elevations; the first tile whose projected height matches wins.
        var candidate: GridPoint?
        for testElevation in stride(from: 12, through: 0, by: -1) {
            let adjusted = ScreenPoint(x: point.x, y: point.y + Double(testElevation) * elevationStep)
            let world = unproject(adjusted)
            let tile = world.tile
            guard mapSize.contains(tile) else { continue }
            if elevationLookup(tile) == testElevation {
                return tile
            }
            if candidate == nil, testElevation == 0 {
                candidate = tile
            }
        }
        let flat = unproject(point).tile
        return mapSize.contains(flat) ? flat : candidate
    }

    /// Painter's-algorithm depth. Higher draws in front.
    public func depth(for point: WorldPoint, layer: Int = 0) -> Double {
        let rotated = rotate(point)
        return (rotated.x + rotated.y) * 1_000 + Double(layer)
    }
}
