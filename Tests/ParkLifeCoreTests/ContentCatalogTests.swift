import XCTest
@testable import ParkLifeCore

/// Shared fixtures. Loading the catalog once keeps the suite fast.
enum TestFixtures {

    static let catalog: ContentCatalog = {
        do {
            return try ContentCatalog.bundled()
        } catch {
            fatalError("Content catalog failed to load: \(error)")
        }
    }()

    static func demoPark() throws -> World {
        try GameSetup.makeDemoPark(catalog: catalog)
    }

    static func demoEngine() throws -> SimulationEngine {
        SimulationEngine(world: try demoPark())
    }
}

final class ContentCatalogTests: XCTestCase {

    func testCatalogLoads() {
        let catalog = TestFixtures.catalog
        XCTAssertFalse(catalog.buildings.isEmpty)
        XCTAssertFalse(catalog.paths.isEmpty)
        XCTAssertFalse(catalog.archetypes.isEmpty)
        XCTAssertFalse(catalog.maps.isEmpty)
        XCTAssertFalse(catalog.scenarios.isEmpty)
        XCTAssertFalse(catalog.staffRoles.isEmpty)
        XCTAssertFalse(catalog.names.adultNames.isEmpty)
    }

    func testIdsAreStableAndSorted() {
        let catalog = TestFixtures.catalog
        XCTAssertEqual(catalog.buildingIDs, catalog.buildingIDs.sorted())
        XCTAssertEqual(catalog.buildingIDs.count, catalog.buildings.count)
    }

    func testEveryBuildingIsWellFormed() throws {
        let catalog = TestFixtures.catalog
        for id in catalog.buildingIDs {
            let definition = try catalog.building(id)
            XCTAssertGreaterThan(definition.footprintWidth, 0, "\(id) width")
            XCTAssertGreaterThan(definition.footprintHeight, 0, "\(id) height")
            XCTAssertGreaterThanOrEqual(definition.constructionCost.cents, 0, "\(id) cost")
            XCTAssertFalse(definition.art.isEmpty, "\(id) art")
            XCTAssertFalse(definition.nameKey.isEmpty, "\(id) nameKey")
            XCTAssertTrue((0...1).contains(definition.demolitionRefundFraction), "\(id) refund")

            // Entrance offsets must sit inside the footprint, or the building can never be reached.
            for offset in definition.entranceOffsets {
                XCTAssertTrue(
                    offset.x >= 0 && offset.x < definition.footprintWidth
                        && offset.y >= 0 && offset.y < definition.footprintHeight,
                    "\(id) entrance offset \(offset) is outside its footprint"
                )
            }
            if definition.requiresPathAdjacency && definition.category != .decoration {
                XCTAssertFalse(definition.entranceOffsets.isEmpty, "\(id) needs an entrance")
            }
        }
    }

    func testAccommodationDefinitionsAreSane() throws {
        for definition in TestFixtures.catalog.accommodationDefinitions {
            let accommodation = try XCTUnwrap(definition.accommodation)
            XCTAssertGreaterThan(accommodation.capacity, 0, "\(definition.id)")
            XCTAssertGreaterThan(accommodation.baseNightlyPrice.cents, 0, "\(definition.id)")
            XCTAssertGreaterThan(accommodation.cleaningMinutes, 0, "\(definition.id)")
            XCTAssertTrue((0...1).contains(accommodation.baseQuality), "\(definition.id)")
            XCTAssertGreaterThanOrEqual(accommodation.bedrooms, 1, "\(definition.id)")
        }
    }

    func testFacilityDefinitionsAreSane() throws {
        for id in TestFixtures.catalog.buildingIDs {
            guard let facility = TestFixtures.catalog.buildings[id]?.facility else { continue }
            XCTAssertGreaterThan(facility.capacity, 0, "\(id) capacity")
            XCTAssertGreaterThanOrEqual(facility.queueCapacity, 0, "\(id) queue")
            XCTAssertLessThanOrEqual(facility.minimumServiceMinutes, facility.maximumServiceMinutes, "\(id)")
            XCTAssertTrue((0...1).contains(facility.appeal), "\(id) appeal")
            XCTAssertTrue((0...1).contains(facility.childSuitability), "\(id) child suitability")
            XCTAssertTrue((0...1).contains(facility.variableCostFraction), "\(id) variable cost")
            for relief in facility.relief {
                XCTAssertTrue((0...1).contains(relief.amount), "\(id) relief \(relief.need)")
            }
        }
    }

    func testResearchPrerequisitesExist() {
        let catalog = TestFixtures.catalog
        for (id, definition) in catalog.research {
            for prerequisite in definition.prerequisites {
                XCTAssertNotNil(catalog.research[prerequisite], "\(id) requires unknown \(prerequisite)")
            }
            for unlocked in definition.unlocksBuildings {
                XCTAssertNotNil(catalog.buildings[unlocked], "\(id) unlocks unknown \(unlocked)")
            }
        }
    }

    func testBuildingsGatedByResearchReferenceRealProjects() {
        let catalog = TestFixtures.catalog
        for id in catalog.buildingIDs {
            guard let required = catalog.buildings[id]?.researchID else { continue }
            XCTAssertNotNil(catalog.research[required], "\(id) requires unknown research \(required)")
        }
    }

    func testScenariosReferenceRealContent() throws {
        let catalog = TestFixtures.catalog
        for (id, scenario) in catalog.scenarios {
            XCTAssertNotNil(catalog.maps[scenario.mapID], "\(id) uses unknown map")
            for placement in scenario.prebuilt {
                XCTAssertNotNil(catalog.buildings[placement.definitionID], "\(id) prebuilds unknown building")
            }
            for objective in scenario.objectives {
                XCTAssertGreaterThan(objective.target, 0, "\(id)/\(objective.id)")
            }
        }
    }

    func testArchetypeMarketSharesAreUsable() {
        let catalog = TestFixtures.catalog
        var total = 0.0
        for id in catalog.archetypeIDs {
            let archetype = catalog.archetypes[id]!
            XCTAssertGreaterThan(archetype.marketShare, 0, "\(id)")
            XCTAssertLessThanOrEqual(archetype.minimumAdults, archetype.maximumAdults, "\(id)")
            XCTAssertLessThanOrEqual(archetype.minimumNights, archetype.maximumNights, "\(id)")
            XCTAssertGreaterThan(archetype.budgetPerPersonPerNight.cents, 0, "\(id)")
            XCTAssertEqual(archetype.adultAgeRange.count, 2, "\(id)")
            XCTAssertEqual(archetype.childAgeRange.count, 2, "\(id)")
            total += archetype.marketShare
        }
        XCTAssertEqual(total, 1.0, accuracy: 0.05)
    }

    func testAvailabilityFiltersOnResearch() {
        let catalog = TestFixtures.catalog
        let starting = catalog.availableBuildings(completedResearch: [])
        XCTAssertFalse(starting.contains { $0.id == "villa_vip_8" })
        XCTAssertTrue(starting.contains { $0.id == "cottage_comfort_4" })

        let withVIP = catalog.availableBuildings(completedResearch: ["acc_vip"])
        XCTAssertTrue(withVIP.contains { $0.id == "villa_vip_8" })
    }

    func testOpeningHours() {
        let daytime = OpeningHours(opensAtMinute: 9 * 60, closesAtMinute: 21 * 60)
        XCTAssertTrue(daytime.isOpen(atMinuteOfDay: 12 * 60))
        XCTAssertFalse(daytime.isOpen(atMinuteOfDay: 8 * 60))
        XCTAssertFalse(daytime.isOpen(atMinuteOfDay: 22 * 60))
        XCTAssertTrue(OpeningHours.alwaysOpen.isOpen(atMinuteOfDay: 3 * 60))

        let overnight = OpeningHours(opensAtMinute: 22 * 60, closesAtMinute: 2 * 60)
        XCTAssertTrue(overnight.isOpen(atMinuteOfDay: 23 * 60))
        XCTAssertTrue(overnight.isOpen(atMinuteOfDay: 60))
        XCTAssertFalse(overnight.isOpen(atMinuteOfDay: 12 * 60))
    }
}
