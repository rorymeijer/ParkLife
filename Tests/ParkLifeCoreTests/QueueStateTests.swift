import XCTest
@testable import ParkLifeCore

/// The invariant that a guest marked as queueing is really in that queue.
///
/// It was broken by `MovementSystem` setting `.queueing(X)` immediately after asking
/// `QueueService` to join: when the join was refused — a full queue, or a facility that had
/// closed while the guest walked over — the refusal put the guest back to `.idle` and the next
/// line overwrote it. Nothing could recover them afterwards, because admission and impatience
/// both work off the queue the guest was never in, and the AI only reconsiders idle guests.
/// Every guest turned away was frozen for the rest of their holiday.
final class QueueStateTests: XCTestCase {

    private func parkWithAGuestAtAFacility(
        closed: Bool
    ) throws -> (World, GuestID, BuildingID) {
        var world = try TestFixtures.demoPark()
        world.clock.setTick(GameDate(year: 2026, month: 6, day: 10, hour: 13).minutesSinceEpoch)

        let facilityID = try XCTUnwrap(
            world.index.facilityIDs.first {
                guard let facility = world.definition(ofBuilding: $0)?.facility else { return false }
                return facility.kind != .reception && facility.kind != .entrance
            },
            "the demo park should contain a facility"
        )
        if closed {
            world.buildings.modify(facilityID) { $0.facility?.isOpen = false }
        }

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
        guest.lastNeedsTick = world.tick
        group.memberIDs = [guestID]

        world.groups.insert(group)
        world.guests.insert(guest)
        world.index.rebuildGuests(world.guests)
        world.activate(group: groupID)
        return (world, guestID, facilityID)
    }

    private func context(for world: World) -> TickContext {
        TickContext(
            tick: world.tick,
            date: world.date,
            previousDate: GameDate(minutesSinceEpoch: world.tick - 1),
            tuning: SimulationTuning()
        )
    }

    func testJoiningAnOpenQueueMarksTheGuestAsQueueingThere() throws {
        var (world, guestID, facilityID) = try parkWithAGuestAtAFacility(closed: false)
        var context = self.context(for: world)

        let joined = QueueService.joinQueue(
            guestID: guestID, buildingID: facilityID, world: &world, context: &context
        )

        XCTAssertTrue(joined, "an open, empty facility should accept a guest")
        XCTAssertEqual(world.guests[guestID]?.activity, .queueing(facilityID))
        XCTAssertEqual(world.buildings[facilityID]?.facility?.queue, [guestID])
    }

    func testAGuestTurnedAwayIsLeftIdleAndNotMarkedAsQueueing() throws {
        var (world, guestID, facilityID) = try parkWithAGuestAtAFacility(closed: true)
        var context = self.context(for: world)

        let joined = QueueService.joinQueue(
            guestID: guestID, buildingID: facilityID, world: &world, context: &context
        )

        XCTAssertFalse(joined, "a closed facility should refuse the guest")
        XCTAssertEqual(
            world.guests[guestID]?.activity, .idle,
            "a refused guest must be left idle — anything else strands them permanently"
        )
        XCTAssertEqual(world.buildings[facilityID]?.facility?.queue ?? [], [])
    }

    /// The invariant itself, across a real run: no guest is ever marked as queueing somewhere
    /// they are not actually queued.
    func testNoGuestIsEverMarkedQueueingSomewhereTheyAreNotQueued() throws {
        let world = try TestFixtures.demoPark()
        let engine = SimulationEngine(world: world)
        engine.run(ticks: 20 * GameDate.minutesPerDay)

        var stranded: [String] = []
        for guest in engine.world.guests.items {
            let buildingID: BuildingID?
            switch guest.activity {
            case .queueing(let id): buildingID = id
            case .queueingAtReception: buildingID = engine.world.index.receptionID
            default: continue
            }
            guard let id = buildingID else {
                stranded.append("guest \(guest.id) queueing at reception, but the park has none")
                continue
            }
            let queue = engine.world.buildings[id]?.facility?.queue ?? []
            if !queue.contains(guest.id) {
                stranded.append("guest \(guest.id) marked queueing at \(id) but is not in its queue")
            }
        }
        XCTAssertEqual(stranded, [], "stranded guests: \(stranded.count)")
    }
}
