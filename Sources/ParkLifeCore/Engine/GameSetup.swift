import Foundation

/// Creates new games from scenario data, and builds the demo park used by tests, screenshots and
/// the debug menu.
public enum GameSetup {

    /// Starts a scenario.
    public static func newGame(
        scenarioID: String,
        catalog: ContentCatalog,
        seed: UInt64 = 0x5EED_1234_ABCD_0001,
        parkName: String? = nil,
        companyName: String = "Meijer Recreatie"
    ) throws -> World {
        let scenario = try catalog.scenario(scenarioID)
        let map = try catalog.map(scenario.mapID)

        var world = World(
            catalog: catalog,
            map: map,
            seed: seed,
            difficulty: scenario.difficulty,
            startDate: scenario.startDate.gameDate,
            startingCash: scenario.startingCash,
            parkName: parkName ?? map.nameKey,
            companyName: companyName
        )
        world.scenarioID = scenarioID

        // Prebuilt objects are placed without charging the player — they are part of the brief.
        for placement in scenario.prebuilt {
            placePrebuilt(placement, in: &world)
        }
        world.rebuildDerivedState()
        ParkLog.shared.info(.sim, "Started scenario \(scenarioID) on map \(map.id)")
        return world
    }

    private static func placePrebuilt(_ placement: ScenarioDefinition.PrebuiltPlacement, in world: inout World) {
        guard let definition = world.catalog.buildings[placement.definitionID] else { return }
        let rotation = Rotation(rawValue: placement.rotation) ?? .none
        let id = world.ids.next(BuildingID.self)
        let instance = BuildingInstance(
            id: id,
            definitionID: definition.id,
            origin: placement.origin,
            rotation: rotation,
            builtAtTick: world.tick,
            accommodation: definition.isAccommodation ? AccommodationState() : nil,
            facility: definition.isFacility ? FacilityState() : nil
        )
        for point in instance.footprintRect(definition: definition).points {
            world.tiles.setBuilding(id, at: point)
        }
        world.buildings.insert(instance)
    }

    /// Which side of a path row a building faces.
    public enum PathSide {
        case north
        case south
    }

    /// Places a building so that its door sits directly against a path row.
    ///
    /// The origin is derived from the definition's own entrance offset rather than hardcoded, so a
    /// new building type with a different footprint slots into the same layout code.
    @discardableResult
    public static func place(
        _ definitionID: String,
        doorX: Int,
        pathRowY: Int,
        side: PathSide,
        in world: inout World
    ) -> Bool {
        guard let definition = world.catalog.buildings[definitionID],
              let offset = definition.entranceOffsets.first else { return false }
        let rotation: Rotation = side == .north ? .none : .half
        let rotated = rotation.apply(to: offset, in: definition.footprint)
        let doorY = side == .north ? pathRowY - 1 : pathRowY + 1
        let origin = GridPoint(x: doorX - rotated.x, y: doorY - rotated.y)
        let placed = BuildService.apply(
            .placeBuilding(definitionID: definitionID, origin: origin, rotation: rotation),
            to: &world
        ) != nil
        if !placed {
            ParkLog.shared.warning(.build, "Demo layout could not place \(definitionID) at \(origin)")
        }
        return placed
    }

    /// A small working park: entrance, paths, reception, cottages, pool, restaurant, shops,
    /// playground, mini golf, toilets and starting staff.
    ///
    /// Everything is built through the normal `BuildService` path — this is not a special-case
    /// world — so if the build rules break, this breaks too and the tests say so. The layout is
    /// laid out around five path rows, with every building's door placed against one of them.
    public static func makeDemoPark(
        catalog: ContentCatalog,
        seed: UInt64 = 0x0DEA_0FAB_0000_0001,
        cash: Money = Money(euros: 3_000_000)
    ) throws -> World {
        var world = try newGame(
            scenarioID: "sandbox-zandheuvel",
            catalog: catalog,
            seed: seed,
            parkName: "De Zandheuvel"
        )
        world.cash = Money(euros: 20_000_000)

        let entrance = world.entranceTile
        let rows = [entrance.y - 10, entrance.y - 19, entrance.y - 28, entrance.y - 37, entrance.y - 46]
        let westEdge = entrance.x - 18
        let eastEdge = entrance.x + 18

        // Spine from the gate to the far end of the park.
        var spine: [GridPoint] = []
        for y in stride(from: entrance.y, through: rows[4], by: -1) {
            spine.append(GridPoint(x: entrance.x, y: y))
        }
        BuildService.apply(.placePath(definitionID: "footpath", tiles: spine), to: &world)

        // Five east–west rows every building hangs off.
        for rowY in rows {
            var row: [GridPoint] = []
            for x in westEdge...eastEdge {
                row.append(GridPoint(x: x, y: rowY))
            }
            BuildService.apply(.placePath(definitionID: "footpath", tiles: row), to: &world)
        }

        // A paved square just inside the gate.
        var plaza: [GridPoint] = []
        for y in (entrance.y - 6)...(entrance.y - 2) {
            for x in (entrance.x - 3)...(entrance.x + 3) {
                plaza.append(GridPoint(x: x, y: y))
            }
        }
        BuildService.apply(.placePath(definitionID: "paved_plaza", tiles: plaza), to: &world)

        // Services and leisure.
        place("reception", doorX: entrance.x - 7, pathRowY: rows[0], side: .north, in: &world)
        place("supermarket", doorX: entrance.x + 8, pathRowY: rows[0], side: .north, in: &world)
        place("toilet_block", doorX: entrance.x - 4, pathRowY: rows[1], side: .south, in: &world)
        place("souvenir_shop", doorX: entrance.x + 4, pathRowY: rows[1], side: .south, in: &world)
        place("restaurant_family", doorX: entrance.x - 11, pathRowY: rows[1], side: .north, in: &world)
        place("cafe_terrace", doorX: entrance.x + 5, pathRowY: rows[1], side: .north, in: &world)
        place("pool_indoor", doorX: entrance.x + 9, pathRowY: rows[2], side: .north, in: &world)
        place("snack_bar", doorX: entrance.x - 12, pathRowY: rows[2], side: .north, in: &world)
        place("playground", doorX: entrance.x - 9, pathRowY: rows[3], side: .south, in: &world)
        place("minigolf", doorX: entrance.x + 10, pathRowY: rows[4], side: .south, in: &world)

        // Cottages either side of the two northern rows.
        let cottageTypes = [
            "cottage_comfort_4", "cottage_comfort_6", "cottage_basic_4",
            "cottage_comfort_4", "cottage_comfort_6", "cottage_basic_4"
        ]
        let cottageDoors = [-16, -11, -6, 6, 11, 16]
        var index = 0
        for rowY in [rows[3], rows[4]] {
            for offset in cottageDoors {
                place(
                    cottageTypes[index % cottageTypes.count],
                    doorX: entrance.x + offset,
                    pathRowY: rowY,
                    side: .north,
                    in: &world
                )
                index += 1
            }
        }
        for offset in [-16, -11, -6] {
            place(
                cottageTypes[index % cottageTypes.count],
                doorX: entrance.x + offset,
                pathRowY: rows[4],
                side: .south,
                in: &world
            )
            index += 1
        }

        // Greenery: scenery is a measured input to guest happiness, not decoration for its own sake.
        for rowY in rows {
            for offset in [-2, 2] {
                BuildService.apply(
                    .placeBuilding(
                        definitionID: offset < 0 ? "tree_oak" : "tree_pine",
                        origin: GridPoint(x: entrance.x + offset, y: rowY - 1),
                        rotation: .none
                    ),
                    to: &world
                )
            }
            BuildService.apply(
                .placeBuilding(
                    definitionID: "bench",
                    origin: GridPoint(x: entrance.x + 1, y: rowY - 1),
                    rotation: .none
                ),
                to: &world
            )
        }

        // Staff: without housekeeping, cottages never become ready again.
        for _ in 0..<3 { StaffSystem.hire(roleID: "housekeeping", world: &world) }
        StaffSystem.hire(roleID: "reception", world: &world)
        StaffSystem.hire(roleID: "reception", world: &world)
        for _ in 0..<2 { StaffSystem.hire(roleID: "catering", world: &world) }
        for _ in 0..<2 { StaffSystem.hire(roleID: "lifeguard", world: &world) }
        StaffSystem.hire(roleID: "retail", world: &world)
        StaffSystem.hire(roleID: "maintenance", world: &world)

        // Housekeepers cover the day between them; everyone else works a long day shift.
        var housekeeperIndex = 0
        for staffID in world.staff.sortedIDs {
            world.staff.modify(staffID) { member in
                if member.roleID == "housekeeping" {
                    member.shiftStartMinute = 7 * 60 + housekeeperIndex * 3 * 60
                    member.shiftEndMinute = member.shiftStartMinute + 9 * 60
                    housekeeperIndex += 1
                } else {
                    member.shiftStartMinute = 8 * 60
                    member.shiftEndMinute = 22 * 60
                }
            }
        }

        world.rebuildDerivedState()
        world.cash = cash
        ParkLog.shared.info(
            .sim,
            "Demo park built: \(world.buildings.count) buildings, \(world.index.accommodationIDs.count) units"
        )
        return world
    }

}
