import XCTest
@testable import ParkLifeCore

final class BuildServiceTests: XCTestCase {

    private func emptyWorld() throws -> World {
        try GameSetup.newGame(scenarioID: "sandbox-zandheuvel", catalog: TestFixtures.catalog)
    }

    func testPlacingAPathCostsPerTileAndMakesItWalkable() throws {
        var world = try emptyWorld()
        let before = world.cash
        let tiles = (0..<10).map { GridPoint(x: 40 + $0, y: 60) }

        let record = try XCTUnwrap(BuildService.apply(.placePath(definitionID: "footpath", tiles: tiles), to: &world))
        let perTile = try world.catalog.path("footpath").costPerTile
        XCTAssertEqual(world.cash.cents, before.cents - perTile.cents * 10)
        XCTAssertEqual(record.cashDelta.cents, -perTile.cents * 10)
        for tile in tiles {
            XCTAssertTrue(world.tiles.isWalkable(at: tile))
            XCTAssertTrue(world.navigation.network.isWalkable(tile))
        }
    }

    func testPlacingTheSamePathTwiceChargesOnce() throws {
        var world = try emptyWorld()
        let tiles = (0..<5).map { GridPoint(x: 40 + $0, y: 60) }
        BuildService.apply(.placePath(definitionID: "footpath", tiles: tiles), to: &world)
        let afterFirst = world.cash
        // No tile changes, so there is nothing to charge for.
        XCTAssertNil(BuildService.apply(.placePath(definitionID: "footpath", tiles: tiles), to: &world))
        XCTAssertEqual(world.cash, afterFirst)
    }

    func testPlacingABuildingOccupiesItsFootprint() throws {
        var world = try emptyWorld()
        let origin = GridPoint(x: 40, y: 60)
        let record = try XCTUnwrap(
            BuildService.apply(.placeBuilding(definitionID: "cottage_comfort_4", origin: origin, rotation: .none), to: &world)
        )
        guard case .placedBuilding(let id) = record.kind else {
            return XCTFail("expected a placed building record")
        }
        let definition = try world.catalog.building("cottage_comfort_4")
        for point in GridRect(origin: origin, size: definition.footprint).points {
            XCTAssertEqual(world.tiles.building(at: point), id)
        }
        XCTAssertEqual(world.index.accommodationIDs, [id])
        XCTAssertEqual(world.buildings[id]?.accommodation?.state, .ready)
    }

    func testOverlappingPlacementIsRejected() throws {
        var world = try emptyWorld()
        BuildService.apply(.placeBuilding(definitionID: "cottage_comfort_4", origin: GridPoint(x: 40, y: 60), rotation: .none), to: &world)
        let validation = BuildService.validate(
            .placeBuilding(definitionID: "cottage_basic_4", origin: GridPoint(x: 41, y: 61), rotation: .none),
            in: world
        )
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.failure, .tileOccupied)
        XCTAssertFalse(validation.offendingTiles.isEmpty)
    }

    func testOutOfBoundsPlacementIsRejected() throws {
        let world = try emptyWorld()
        let validation = BuildService.validate(
            .placeBuilding(definitionID: "cottage_comfort_4", origin: GridPoint(x: 95, y: 95), rotation: .none),
            in: world
        )
        XCTAssertFalse(validation.isValid)
        XCTAssertEqual(validation.failure, .outOfBounds)
    }

    func testWaterIsNotBuildableButBridgesCross() throws {
        var world = try emptyWorld()
        // The Zandheuvel lake sits around (8,10)–(34,28).
        let lakeTile = try XCTUnwrap(
            GridRect(x: 8, y: 10, width: 26, height: 18).points.first { world.tiles.terrain(at: $0) == .water }
        )
        let cottage = BuildService.validate(
            .placeBuilding(definitionID: "cottage_basic_4", origin: lakeTile, rotation: .none),
            in: world
        )
        XCTAssertFalse(cottage.isValid)

        world.completedResearch = ["infra_cycling", "infra_bridges"]
        let bridge = BuildService.validate(.placePath(definitionID: "timber_bridge", tiles: [lakeTile]), in: world)
        XCTAssertTrue(bridge.isValid, "bridges are the one surface that may cross water")

        let footpath = BuildService.validate(.placePath(definitionID: "footpath", tiles: [lakeTile]), in: world)
        XCTAssertFalse(footpath.isValid)
    }

    func testUnresearchedBuildingIsRejected() throws {
        let world = try emptyWorld()
        let validation = BuildService.validate(
            .placeBuilding(definitionID: "villa_vip_8", origin: GridPoint(x: 40, y: 60), rotation: .none),
            in: world
        )
        XCTAssertEqual(validation.failure, .notResearched)
    }

    func testInsufficientFundsIsRejected() throws {
        var world = try emptyWorld()
        world.cash = Money(euros: 100)
        let validation = BuildService.validate(
            .placeBuilding(definitionID: "pool_indoor", origin: GridPoint(x: 40, y: 60), rotation: .none),
            in: world
        )
        XCTAssertEqual(validation.failure, .notEnoughMoney)
    }

    func testDisconnectedBuildingIsAllowedButWarns() throws {
        let world = try emptyWorld()
        let validation = BuildService.validate(
            .placeBuilding(definitionID: "cottage_comfort_4", origin: GridPoint(x: 40, y: 60), rotation: .none),
            in: world
        )
        XCTAssertTrue(validation.isValid, "placing before connecting a path must not be blocked")
        XCTAssertTrue(validation.warnsNoPathAccess)
    }

    func testDemolitionRefundsAndFreesTiles() throws {
        var world = try emptyWorld()
        let origin = GridPoint(x: 40, y: 60)
        BuildService.apply(.placeBuilding(definitionID: "cottage_comfort_4", origin: origin, rotation: .none), to: &world)
        let id = try XCTUnwrap(world.index.accommodationIDs.first)
        let definition = try world.catalog.building("cottage_comfort_4")
        let cashBefore = world.cash

        BuildService.apply(.demolishBuilding(id), to: &world)
        XCTAssertNil(world.buildings[id])
        XCTAssertNil(world.tiles.building(at: origin))
        let expectedRefund = definition.constructionCost.scaled(by: definition.demolitionRefundFraction)
        XCTAssertEqual(world.cash.cents, cashBefore.cents + expectedRefund.cents)
    }

    func testEntranceCannotBeDemolished() throws {
        let world = try emptyWorld()
        let entranceID = try XCTUnwrap(world.index.entranceID)
        XCTAssertEqual(BuildService.validate(.demolishBuilding(entranceID), in: world).failure, .entranceCannotBeDemolished)
    }

    func testOccupiedUnitCannotBeDemolished() throws {
        var world = try emptyWorld()
        BuildService.apply(.placeBuilding(definitionID: "cottage_comfort_4", origin: GridPoint(x: 40, y: 60), rotation: .none), to: &world)
        let id = try XCTUnwrap(world.index.accommodationIDs.first)
        world.buildings.modify(id) { $0.accommodation?.state = .occupied }
        XCTAssertEqual(BuildService.validate(.demolishBuilding(id), in: world).failure, .unitIsOccupied)
    }

    func testUndoRestoresWorldAndCashExactly() throws {
        var world = try emptyWorld()
        let cashBefore = world.cash
        let buildingsBefore = world.buildings.count

        let record = try XCTUnwrap(
            BuildService.apply(
                .placeBuilding(definitionID: "restaurant_family", origin: GridPoint(x: 40, y: 60), rotation: .none),
                to: &world
            )
        )
        XCTAssertNotEqual(world.cash, cashBefore)

        XCTAssertTrue(BuildService.undo(record, in: &world))
        XCTAssertEqual(world.cash, cashBefore, "undo must restore cash exactly, never approximately")
        XCTAssertEqual(world.buildings.count, buildingsBefore)
        XCTAssertNil(world.tiles.building(at: GridPoint(x: 40, y: 60)))
    }

    func testUndoOfPathRestoresPreviousSurfaces() throws {
        var world = try emptyWorld()
        let tiles = (0..<4).map { GridPoint(x: 40 + $0, y: 60) }
        BuildService.apply(.placePath(definitionID: "footpath", tiles: tiles), to: &world)
        let upgrade = try XCTUnwrap(BuildService.apply(.placePath(definitionID: "paved_plaza", tiles: tiles), to: &world))
        XCTAssertEqual(world.tiles.surface(at: tiles[0]), .plaza)

        BuildService.undo(upgrade, in: &world)
        XCTAssertEqual(world.tiles.surface(at: tiles[0]), .footpath, "undo restores what was there before")
    }

    func testUndoRedoThroughTheEngine() throws {
        let engine = SimulationEngine(world: try emptyWorld())
        let cashBefore = engine.world.cash

        XCTAssertNoThrow(try engine.submit(.build(.placeBuilding(definitionID: "cafe_terrace", origin: GridPoint(x: 40, y: 60), rotation: .none))).get())
        XCTAssertEqual(engine.world.buildings.count, 2)  // entrance + cafe
        XCTAssertTrue(engine.history.canUndo)

        XCTAssertNoThrow(try engine.submit(.undoBuild).get())
        XCTAssertEqual(engine.world.buildings.count, 1)
        XCTAssertEqual(engine.world.cash, cashBefore)
        XCTAssertTrue(engine.history.canRedo)

        XCTAssertNoThrow(try engine.submit(.redoBuild).get())
        XCTAssertEqual(engine.world.buildings.count, 2)
        XCTAssertNotEqual(engine.world.cash, cashBefore)
    }

    func testUndoWithEmptyStackIsRejected() throws {
        let engine = SimulationEngine(world: try emptyWorld())
        if case .success = engine.submit(.undoBuild) {
            XCTFail("undo with nothing to undo should be rejected")
        }
    }

    func testDemoParkBuildsSuccessfully() throws {
        let world = try TestFixtures.demoPark()
        XCTAssertGreaterThanOrEqual(world.index.accommodationIDs.count, 12, "demo park should have cottages")
        XCTAssertNotNil(world.index.receptionID)
        XCTAssertNotNil(world.index.entranceID)
        XCTAssertFalse(world.index.facilities(ofKind: .pool).isEmpty)
        XCTAssertFalse(world.index.facilities(ofKind: .restaurant).isEmpty)
        XCTAssertFalse(world.index.facilities(ofKind: .supermarket).isEmpty)
        XCTAssertGreaterThan(world.staff.count, 5)
    }

    func testSceneryIsRecomputedAfterBuilding() throws {
        var world = try emptyWorld()
        let point = GridPoint(x: 41, y: 61)
        let before = world.tiles.scenery(at: point)
        BuildService.apply(.placeBuilding(definitionID: "tree_oak", origin: GridPoint(x: 40, y: 60), rotation: .none), to: &world)
        XCTAssertGreaterThan(world.tiles.scenery(at: point), before, "trees make their surroundings nicer")
    }
}
