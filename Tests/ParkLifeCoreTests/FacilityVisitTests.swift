import XCTest
@testable import ParkLifeCore

/// A single paid facility visit, end to end.
///
/// `VerticalSliceTests.testGuestsSpendMoneyInFacilities` found that a 45-day run produced no food,
/// retail or activity revenue at all, but a 45-day run cannot say *where* the chain breaks. These
/// tests walk the same chain one link at a time — is a food place even a candidate, does the guest
/// reach it, does the money move — so a failure names the broken link.
final class FacilityVisitTests: XCTestCase {

    /// A hungry, thirsty adult standing at the park entrance, checked in, mid-afternoon.
    private func parkWithAHungryGuest() throws -> (World, GuestID) {
        var world = try TestFixtures.demoPark()
        world.clock.setTick(GameDate(year: 2026, month: 6, day: 10, hour: 13).minutesSinceEpoch)

        let groupID = world.ids.next(GroupID.self)
        var group = GuestGroup(
            id: groupID,
            archetypeID: "youngFamily",
            memberIDs: [],
            budget: Money(euros: 900),
            arrivalDate: world.date.adding(days: -1),
            departureDate: world.date.adding(days: 3),
            expectation: 0.5,
            reviewWeights: [:]
        )
        group.state = .checkedIn
        group.unitBuildingID = world.index.accommodationIDs.first

        let guestID = world.ids.next(GuestID.self)
        var guest = Guest(
            id: guestID,
            groupID: groupID,
            firstName: "Test",
            age: 36,
            personality: .neutral,
            interests: .neutral,
            position: WorldPoint(world.parkEntranceTiles.first ?? world.entranceTile)
        )
        guest.activity = .idle
        guest.detail = .reduced
        guest.hasUnpacked = true
        guest.needs = NeedState(hunger: 0.95, thirst: 0.9, tiredness: 0.1, boredom: 0.3, bladder: 0.1)
        guest.lastNeedsTick = world.tick
        group.memberIDs = [guestID]

        world.groups.insert(group)
        world.guests.insert(guest)
        world.index.rebuildGuests(world.guests)
        world.activate(group: groupID)
        return (world, guestID)
    }

    private func foodFacilityIDs(in world: World) -> [BuildingID] {
        world.index.facilityIDs.filter {
            (world.definition(ofBuilding: $0)?.facility?.reliefAmount(for: .hunger) ?? 0) > 0.3
        }
    }

    // MARK: Link 1 — is somewhere to eat even a candidate?

    func testAFoodFacilityIsOperationalAndReachable() throws {
        let (world, _) = try parkWithAHungryGuest()
        let food = foodFacilityIDs(in: world)
        XCTAssertFalse(food.isEmpty, "the demo park should contain somewhere to eat")

        let operational = food.filter { world.isOperational($0) }
        XCTAssertFalse(
            operational.isEmpty,
            "no food facility is operational at 13:00 — check opening hours, path access and condition"
        )

        let entrance = try XCTUnwrap(world.parkEntranceTiles.first)
        let reachable = operational.filter { world.navigation.tileDistance(from: entrance, to: $0) != nil }
        XCTAssertFalse(reachable.isEmpty, "no food facility has a flow field reaching the entrance")
    }

    // MARK: Link 2 — does the guest choose it?

    func testAHungryGuestDecidesToVisitSomewhereThatSellsFood() throws {
        let (world, guestID) = try parkWithAHungryGuest()
        let context = TickContext(
            tick: world.tick,
            date: world.date,
            previousDate: GameDate(minutesSinceEpoch: world.tick - 1),
            tuning: SimulationTuning()
        )
        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context)
        guard case .visit(let chosen) = decision else {
            return XCTFail("a starving guest chose \(decision) rather than going to eat")
        }
        let relief = world.definition(ofBuilding: chosen)?.facility?.reliefAmount(for: .hunger) ?? 0
        XCTAssertGreaterThan(relief, 0.2, "the chosen facility does not sell food")
    }

    // MARK: Link 3 — does the visit complete and the money move?

    func testTheVisitCompletesAndIsPaidFor() throws {
        let (world, guestID) = try parkWithAHungryGuest()
        let engine = SimulationEngine(world: world)
        // Long enough to walk across the park, queue and be served.
        engine.run(ticks: 8 * 60)

        let visits = engine.world.index.facilityIDs.reduce(0) { total, id in
            total + (engine.world.buildings[id]?.facility?.lifetimeVisits ?? 0)
        }
        XCTAssertGreaterThan(visits, 0, "the guest never actually reached any facility")

        let spent = engine.world.guests[guestID]?.moneySpent ?? .zero
        let revenue = [RevenueCategory.food, .retail, .activities].reduce(0) { total, category in
            total + engine.world.ledger.dailyTotals.reduce(0) {
                $0 + ($1.revenueByCategory[category.rawValue] ?? 0)
            }
        }
        XCTAssertGreaterThan(
            revenue, 0,
            "facilities were visited \(visits) time(s) but took no money — guest spent \(spent)"
        )
    }
}
