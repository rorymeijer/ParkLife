import XCTest
@testable import ParkLifeCore

final class PathNetworkTests: XCTestCase {

    /// A 20×20 map with a plus-shaped path and one isolated island of path.
    private func makeTileMap() -> TileMap {
        var tiles = TileMap(size: GridSize(width: 20, height: 20))
        for x in 2..<18 {
            tiles.setSurface(.footpath, at: GridPoint(x: x, y: 10))
        }
        for y in 2..<18 {
            tiles.setSurface(.footpath, at: GridPoint(x: 10, y: y))
        }
        // Disconnected island in the corner.
        tiles.setSurface(.footpath, at: GridPoint(x: 1, y: 1))
        tiles.setSurface(.footpath, at: GridPoint(x: 1, y: 2))
        return tiles
    }

    func testWalkabilityFollowsSurface() {
        var network = PathNetwork(size: GridSize(width: 20, height: 20))
        network.update(tiles: makeTileMap(), region: nil)
        XCTAssertTrue(network.isWalkable(GridPoint(x: 10, y: 10)))
        XCTAssertFalse(network.isWalkable(GridPoint(x: 0, y: 0)))
        XCTAssertFalse(network.isWalkable(GridPoint(x: 100, y: 100)))
        XCTAssertEqual(network.walkableCount, 16 + 16 - 1 + 2)
    }

    func testConnectivityComponents() {
        var network = PathNetwork(size: GridSize(width: 20, height: 20))
        network.update(tiles: makeTileMap(), region: nil)
        XCTAssertEqual(network.componentCount, 2)
        XCTAssertTrue(network.areConnected(GridPoint(x: 3, y: 10), GridPoint(x: 10, y: 16)))
        // The island is a different component, so this is answered without any search.
        XCTAssertFalse(network.areConnected(GridPoint(x: 3, y: 10), GridPoint(x: 1, y: 1)))
    }

    func testRemovingATileCanSplitAComponent() {
        var tiles = TileMap(size: GridSize(width: 10, height: 3))
        for x in 0..<10 {
            tiles.setSurface(.footpath, at: GridPoint(x: x, y: 1))
        }
        var network = PathNetwork(size: tiles.size)
        network.update(tiles: tiles, region: nil)
        XCTAssertEqual(network.componentCount, 1)

        tiles.setSurface(.none, at: GridPoint(x: 5, y: 1))
        network.update(tiles: tiles, region: GridRect(x: 5, y: 1, width: 1, height: 1))
        XCTAssertEqual(network.componentCount, 2)
        XCTAssertFalse(network.areConnected(GridPoint(x: 0, y: 1), GridPoint(x: 9, y: 1)))
    }

    func testBuildingsBlockWalkability() {
        var tiles = makeTileMap()
        XCTAssertTrue(tiles.isWalkable(at: GridPoint(x: 10, y: 5)))
        tiles.setBuilding(BuildingID(raw: 1), at: GridPoint(x: 10, y: 5))
        XCTAssertFalse(tiles.isWalkable(at: GridPoint(x: 10, y: 5)))
    }
}

final class AStarTests: XCTestCase {

    private func corridor() -> PathNetwork {
        var tiles = TileMap(size: GridSize(width: 30, height: 30))
        for x in 1..<29 {
            tiles.setSurface(.footpath, at: GridPoint(x: x, y: 15))
        }
        for y in 1..<29 {
            tiles.setSurface(.footpath, at: GridPoint(x: 15, y: y))
        }
        var network = PathNetwork(size: tiles.size)
        network.update(tiles: tiles, region: nil)
        return network
    }

    func testFindsAStraightPath() throws {
        let network = corridor()
        let result = try XCTUnwrap(
            AStarPathfinder.findPath(
                from: GridPoint(x: 2, y: 15),
                toAnyOf: [GridPoint(x: 12, y: 15)],
                network: network
            )
        )
        XCTAssertEqual(result.tiles.first, GridPoint(x: 2, y: 15))
        XCTAssertEqual(result.tiles.last, GridPoint(x: 12, y: 15))
        XCTAssertEqual(result.tiles.count, 11)
    }

    func testPathAroundACorner() throws {
        let network = corridor()
        let result = try XCTUnwrap(
            AStarPathfinder.findPath(
                from: GridPoint(x: 3, y: 15),
                toAnyOf: [GridPoint(x: 15, y: 4)],
                network: network
            )
        )
        XCTAssertEqual(result.tiles.last, GridPoint(x: 15, y: 4))
        // Down the corridor then up the other one: 12 + 11 steps.
        XCTAssertEqual(result.tiles.count, 24)
        // Every tile on the route must actually be walkable.
        for tile in result.tiles {
            XCTAssertTrue(network.isWalkable(tile))
        }
    }

    func testUnreachableDestinationReturnsNil() {
        let network = corridor()
        XCTAssertNil(
            AStarPathfinder.findPath(
                from: GridPoint(x: 2, y: 15),
                toAnyOf: [GridPoint(x: 0, y: 0)],
                network: network
            )
        )
    }

    func testMultipleGoalsPicksTheNearest() throws {
        let network = corridor()
        let result = try XCTUnwrap(
            AStarPathfinder.findPath(
                from: GridPoint(x: 15, y: 15),
                toAnyOf: [GridPoint(x: 15, y: 25), GridPoint(x: 17, y: 15)],
                network: network
            )
        )
        XCTAssertEqual(result.tiles.last, GridPoint(x: 17, y: 15))
    }

    func testStartingOnTheGoalIsATrivialPath() throws {
        let network = corridor()
        let result = try XCTUnwrap(
            AStarPathfinder.findPath(
                from: GridPoint(x: 15, y: 15),
                toAnyOf: [GridPoint(x: 15, y: 15)],
                network: network
            )
        )
        XCTAssertEqual(result.tiles, [GridPoint(x: 15, y: 15)])
    }

    func testNodeBudgetIsRespected() {
        let network = corridor()
        // A budget of one node cannot complete a long search, and must give up rather than
        // blowing the tick.
        XCTAssertNil(
            AStarPathfinder.findPath(
                from: GridPoint(x: 2, y: 15),
                toAnyOf: [GridPoint(x: 15, y: 28)],
                network: network,
                nodeBudget: 2
            )
        )
    }

    func testResultIsDeterministic() {
        let network = corridor()
        let first = AStarPathfinder.findPath(
            from: GridPoint(x: 2, y: 15), toAnyOf: [GridPoint(x: 15, y: 3)], network: network
        )
        let second = AStarPathfinder.findPath(
            from: GridPoint(x: 2, y: 15), toAnyOf: [GridPoint(x: 15, y: 3)], network: network
        )
        XCTAssertEqual(first?.tiles, second?.tiles)
    }
}

final class FlowFieldTests: XCTestCase {

    private func openGrid() -> PathNetwork {
        var tiles = TileMap(size: GridSize(width: 24, height: 24))
        for y in 2..<22 {
            for x in 2..<22 {
                tiles.setSurface(.footpath, at: GridPoint(x: x, y: y))
            }
        }
        var network = PathNetwork(size: tiles.size)
        network.update(tiles: tiles, region: nil)
        return network
    }

    func testFieldReachesEveryConnectedTile() {
        let network = openGrid()
        var field = FlowField(size: network.size)
        field.build(goals: [GridPoint(x: 21, y: 21)], network: network)

        XCTAssertTrue(field.isReachable(from: GridPoint(x: 2, y: 2)))
        XCTAssertFalse(field.isReachable(from: GridPoint(x: 0, y: 0)))
        XCTAssertEqual(field.cost(from: GridPoint(x: 21, y: 21)), 0)
    }

    func testCostDecreasesTowardTheGoal() throws {
        let network = openGrid()
        var field = FlowField(size: network.size)
        field.build(goals: [GridPoint(x: 21, y: 21)], network: network)

        var cursor = GridPoint(x: 3, y: 4)
        var previous = try XCTUnwrap(field.cost(from: cursor))
        var steps = 0
        while let direction = field.nextStep(from: cursor) {
            cursor = cursor.neighbour(direction)
            let cost = try XCTUnwrap(field.cost(from: cursor))
            XCTAssertLessThan(cost, previous)
            previous = cost
            steps += 1
            XCTAssertLessThan(steps, 200, "field must terminate")
        }
        XCTAssertEqual(cursor, GridPoint(x: 21, y: 21))
    }

    func testPathMatchesAStarLength() throws {
        let network = openGrid()
        var field = FlowField(size: network.size)
        let goal = GridPoint(x: 20, y: 5)
        field.build(goals: [goal], network: network)

        let start = GridPoint(x: 4, y: 18)
        let fieldPath = try XCTUnwrap(field.path(from: start))
        let search = try XCTUnwrap(
            AStarPathfinder.findPath(from: start, toAnyOf: [goal], network: network)
        )
        // Both are shortest paths on a uniform grid, so they must cost the same.
        XCTAssertEqual(fieldPath.count, search.tiles.count)
        XCTAssertEqual(fieldPath.last, goal)
    }

    func testMultipleGoalsFormOneField() throws {
        let network = openGrid()
        var field = FlowField(size: network.size)
        field.build(goals: [GridPoint(x: 2, y: 2), GridPoint(x: 21, y: 21)], network: network)
        // A tile near one goal routes to that goal, not to the far one.
        let path = try XCTUnwrap(field.path(from: GridPoint(x: 3, y: 3)))
        XCTAssertEqual(path.last, GridPoint(x: 2, y: 2))
    }
}

final class NavigationStateTests: XCTestCase {

    func testDemoParkIsFullyConnected() throws {
        let world = try TestFixtures.demoPark()
        let entrance = try XCTUnwrap(world.parkEntranceTiles.first)
        XCTAssertTrue(world.navigation.network.isWalkable(entrance))

        // Every facility and every cottage must be reachable from the gate, or the park does not
        // work as a park.
        for id in world.index.facilityIDs + world.index.accommodationIDs {
            let access = world.accessTiles(for: id)
            guard !access.isEmpty else {
                XCTFail("building \(id) has no access tiles")
                continue
            }
            XCTAssertTrue(
                access.contains { world.navigation.network.areConnected(entrance, $0) },
                "building \(id) (\(world.definition(ofBuilding: id)?.id ?? "?")) is not reachable from the entrance"
            )
        }
    }

    func testSharedDestinationsHaveFlowFields() throws {
        let world = try TestFixtures.demoPark()
        let reception = try XCTUnwrap(world.index.receptionID)
        XCTAssertNotNil(world.navigation.field(for: reception))
        let entrance = try XCTUnwrap(world.parkEntranceTiles.first)
        XCTAssertNotNil(world.navigation.tileDistance(from: entrance, to: reception))
    }

    func testCongestionRisesAndDecays() {
        var navigation = NavigationState(size: GridSize(width: 8, height: 8))
        let point = GridPoint(x: 3, y: 3)
        XCTAssertEqual(navigation.congestionLevel(at: point), 0)
        for _ in 0..<5 {
            navigation.noteOccupancy(at: point)
        }
        let busy = navigation.congestionLevel(at: point)
        XCTAssertGreaterThan(busy, 0)
        for _ in 0..<30 {
            navigation.decayCongestion()
        }
        XCTAssertEqual(navigation.congestionLevel(at: point), 0)
    }

    func testRequestQueueRespectsItsBudget() throws {
        var world = try TestFixtures.demoPark()
        let entrance = try XCTUnwrap(world.parkEntranceTiles.first)
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        let goals = world.accessTiles(for: unit)
        for raw in UInt32(1)...UInt32(20) {
            world.navigation.enqueue(PathRequest(guestID: GuestID(raw: raw), start: entrance, goals: goals))
        }
        XCTAssertEqual(world.navigation.pendingRequestCount, 20)
        let results = world.navigation.serviceRequests()
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.tiles != nil })
    }
}
