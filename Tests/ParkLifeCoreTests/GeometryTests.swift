import XCTest
@testable import ParkLifeCore

final class GeometryTests: XCTestCase {

    func testGridSizeIndexing() {
        let size = GridSize(width: 10, height: 8)
        XCTAssertEqual(size.index(of: GridPoint(x: 3, y: 2)), 23)
        XCTAssertEqual(size.point(at: 23), GridPoint(x: 3, y: 2))
        XCTAssertNil(size.index(of: GridPoint(x: -1, y: 0)))
        XCTAssertNil(size.index(of: GridPoint(x: 10, y: 0)))
    }

    func testGridRectContainsAndIntersects() {
        let rect = GridRect(x: 2, y: 2, width: 3, height: 3)
        XCTAssertTrue(rect.contains(GridPoint(x: 4, y: 4)))
        XCTAssertFalse(rect.contains(GridPoint(x: 5, y: 4)))
        XCTAssertTrue(rect.intersects(GridRect(x: 4, y: 4, width: 2, height: 2)))
        XCTAssertFalse(rect.intersects(GridRect(x: 6, y: 6, width: 2, height: 2)))
        XCTAssertEqual(rect.points.count, 9)
    }

    func testEmptyRectBehavesSanely() {
        let empty = GridRect(x: 0, y: 0, width: 0, height: 0)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.points.isEmpty)
        XCTAssertFalse(empty.contains(.zero))
        XCTAssertFalse(empty.intersects(GridRect(x: 0, y: 0, width: 1, height: 1)))
    }

    func testRectClampingAndUnion() {
        let size = GridSize(width: 20, height: 20)
        let clamped = GridRect(x: -3, y: -3, width: 6, height: 6).clamped(to: size)
        XCTAssertEqual(clamped.minX, 0)
        XCTAssertEqual(clamped.maxX, 2)
        let union = GridRect(x: 0, y: 0, width: 2, height: 2).union(GridRect(x: 5, y: 5, width: 1, height: 1))
        XCTAssertEqual(union.minX, 0)
        XCTAssertEqual(union.maxY, 5)
    }

    func testRotationOfFootprintOffsets() {
        let size = GridSize(width: 3, height: 2)
        // A 3×2 footprint becomes 2×3 when rotated a quarter turn.
        XCTAssertEqual(Rotation.quarter.apply(to: size), GridSize(width: 2, height: 3))
        XCTAssertEqual(Rotation.half.apply(to: size), size)

        // Half a turn puts a bottom-row door on the top row, which is what the demo layout uses
        // to face buildings the other way.
        let door = GridPoint(x: 1, y: 1)
        XCTAssertEqual(Rotation.half.apply(to: door, in: size), GridPoint(x: 1, y: 0))
        XCTAssertEqual(Rotation.none.apply(to: door, in: size), door)
    }

    func testRotationIsCyclic() {
        let size = GridSize(width: 4, height: 4)
        let point = GridPoint(x: 1, y: 3)
        var rotated = point
        for _ in 0..<4 {
            rotated = Rotation.quarter.apply(to: rotated, in: size)
        }
        XCTAssertEqual(rotated, point)
    }

    func testDirections() {
        XCTAssertEqual(GridPoint(x: 5, y: 5).neighbour(.north), GridPoint(x: 5, y: 4))
        XCTAssertEqual(GridPoint(x: 5, y: 5).neighbour(.east), GridPoint(x: 6, y: 5))
        XCTAssertEqual(GridDirection.north.opposite, .south)
        XCTAssertEqual(GridPoint(x: 0, y: 0).manhattanDistance(to: GridPoint(x: 3, y: 4)), 7)
    }
}

final class IsometricProjectionTests: XCTestCase {

    private let size = GridSize(width: 64, height: 64)

    func testProjectionIsInvertible() {
        let projection = IsometricProjection(mapSize: size)
        for tile in [GridPoint(x: 0, y: 0), GridPoint(x: 17, y: 5), GridPoint(x: 63, y: 63)] {
            let world = WorldPoint(tile)
            let screen = projection.project(world)
            let recovered = projection.unproject(screen)
            XCTAssertEqual(recovered.x, world.x, accuracy: 0.0001)
            XCTAssertEqual(recovered.y, world.y, accuracy: 0.0001)
        }
    }

    func testProjectionIsInvertibleUnderEveryRotation() {
        for rotation in Rotation.allCases {
            let projection = IsometricProjection(mapSize: size, rotation: rotation)
            let world = WorldPoint(GridPoint(x: 11, y: 29))
            let recovered = projection.unproject(projection.project(world))
            XCTAssertEqual(recovered.x, world.x, accuracy: 0.0001, "rotation \(rotation)")
            XCTAssertEqual(recovered.y, world.y, accuracy: 0.0001, "rotation \(rotation)")
        }
    }

    func testOriginProjectsToScreenOrigin() {
        let projection = IsometricProjection(mapSize: size)
        let screen = projection.project(WorldPoint(x: 0, y: 0))
        XCTAssertEqual(screen.x, 0, accuracy: 0.0001)
        XCTAssertEqual(screen.y, 0, accuracy: 0.0001)
    }

    func testElevationRaisesTilesOnScreen() {
        let projection = IsometricProjection(mapSize: size)
        let flat = projection.project(GridPoint(x: 5, y: 5), elevation: 0)
        let raised = projection.project(GridPoint(x: 5, y: 5), elevation: 3)
        // Screen Y grows downwards, so a higher tile has a smaller Y.
        XCTAssertLessThan(raised.y, flat.y)
    }

    func testDepthOrdersBackToFront() {
        let projection = IsometricProjection(mapSize: size)
        let back = projection.depth(for: WorldPoint(GridPoint(x: 2, y: 2)))
        let front = projection.depth(for: WorldPoint(GridPoint(x: 8, y: 8)))
        XCTAssertLessThan(back, front)
    }

    func testTilePickingOnFlatGround() {
        let projection = IsometricProjection(mapSize: size)
        let tile = GridPoint(x: 12, y: 20)
        let screen = projection.project(tile)
        let picked = projection.tile(at: screen, elevationLookup: { _ in 0 })
        XCTAssertEqual(picked, tile)
    }
}
