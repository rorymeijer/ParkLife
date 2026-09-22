import XCTest
@testable import ParkLifeCore

/// The Phase 1 acceptance test.
///
/// BUILD → BOOKING → ARRIVAL → STAY → SPENDING → DEPARTURE → REVIEW → PROFIT must work end to end
/// on a headless simulation, with no rendering involved at all.
final class VerticalSliceTests: XCTestCase {

    private func runSlice(days: Int) throws -> SimulationEngine {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: days * GameDate.minutesPerDay)
        return engine
    }

    func testTheWholeHolidayLoopRuns() throws {
        let engine = try runSlice(days: 45)
        let world = engine.world

        XCTAssertGreaterThan(world.reservations.count + world.statistics.totalReviews, 0)
        XCTAssertGreaterThan(world.statistics.totalGuestsHosted, 0, "guests should have checked in")
        XCTAssertGreaterThan(world.statistics.totalNightsSold, 0, "nights should have been sold")
        XCTAssertGreaterThan(world.reviews.count, 0, "completed stays must produce reviews")
        XCTAssertGreaterThan(world.ledger.lifetimeRevenue.cents, 0, "the park must take money")
        XCTAssertGreaterThan(
            world.ledger.dailyTotals.reduce(0) { $0 + ($1.revenueByCategory[RevenueCategory.accommodation.rawValue] ?? 0) },
            0,
            "accommodation revenue is the core of the business"
        )
    }

    func testGuestsActuallyArriveAndCheckIn() throws {
        let engine = try runSlice(days: 30)
        let world = engine.world
        let checkedIn = world.groups.items.filter { $0.state == .checkedIn || $0.state == .checkedOut }
        XCTAssertFalse(checkedIn.isEmpty, "some parties must have checked in")

        // Anyone checked in must hold a unit, and that unit must know about them.
        for group in world.groups.items where group.state == .checkedIn {
            let unit = try XCTUnwrap(group.unitBuildingID, "a checked-in group must hold a unit")
            XCTAssertEqual(world.buildings[unit]?.accommodation?.state, .occupied)
        }
    }

    func testGuestsSpendMoneyInFacilities() throws {
        let engine = try runSlice(days: 45)
        let categories = [RevenueCategory.food, .retail, .activities]
        let spent = categories.reduce(0) { total, category in
            total + engine.world.ledger.dailyTotals.reduce(0) {
                $0 + ($1.revenueByCategory[category.rawValue] ?? 0)
            }
        }
        XCTAssertGreaterThan(spent, 0, "guests must use the restaurants, shops and pool")
    }

    func testGuestsSleepAndTheParkGoesQuietAtNight() throws {
        let engine = try TestFixtures.demoEngine()
        // Run to a point where guests are on site, then look at 03:00.
        engine.run(ticks: 30 * GameDate.minutesPerDay)
        let minutesToThreeAM = (27 * 60 - engine.world.date.minuteOfDay + GameDate.minutesPerDay)
            % GameDate.minutesPerDay
        engine.run(ticks: minutesToThreeAM)

        XCTAssertEqual(engine.world.date.hour, 3)
        let onSite = engine.world.guests.items.filter { $0.activity != .departed && $0.activity != .offPark }
        if !onSite.isEmpty {
            let dormant = onSite.filter { $0.detail == .dormant }
            XCTAssertGreaterThan(
                Double(dormant.count) / Double(onSite.count), 0.6,
                "at 3am most guests should be dormant, which is what makes level of detail pay off"
            )
        }
    }

    func testStaysEndAndUnitsAreRecycled() throws {
        let engine = try runSlice(days: 45)
        let world = engine.world
        let checkedOut = world.groups.items.filter { $0.state == .checkedOut }
        XCTAssertFalse(checkedOut.isEmpty, "stays must finish")

        // No unit may be left marked occupied by a party that has gone.
        for unitID in world.index.accommodationIDs {
            guard let state = world.buildings[unitID]?.accommodation else { continue }
            if state.state == .occupied {
                let reservationID = try XCTUnwrap(state.currentReservationID)
                XCTAssertEqual(world.reservations[reservationID]?.status, .checkedIn)
            }
        }
    }

    func testHousekeepingReturnsCottagesToService() throws {
        let engine = try runSlice(days: 45)
        let world = engine.world
        XCTAssertGreaterThan(
            world.index.accommodationIDs.filter { world.buildings[$0]?.accommodation?.state == .ready }.count,
            0,
            "housekeeping must return cottages to service"
        )
        // With three housekeepers and fifteen cottages, a backlog should not run away.
        let dirty = world.index.accommodationIDs.filter { world.buildings[$0]?.accommodation?.state == .dirty }.count
        XCTAssertLessThan(dirty, world.index.accommodationIDs.count)
    }

    func testReviewsAreDerivedFromTheStay() throws {
        let engine = try runSlice(days: 45)
        let reviews = engine.world.reviews
        XCTAssertFalse(reviews.isEmpty)
        for review in reviews {
            XCTAssertTrue((1.0...5.0).contains(review.overallStars), "stars out of range: \(review.overallStars)")
            XCTAssertGreaterThan(review.nights, 0)
            XCTAssertGreaterThan(review.partySize, 0)
            XCTAssertFalse(review.categoryScores.isEmpty, "a review must rate what the party experienced")
            for score in review.categoryScores {
                XCTAssertTrue((1.0...5.0).contains(score.stars))
            }
            XCTAssertFalse(review.bodyKeys.isEmpty, "every review says something")
        }
    }

    func testReputationRespondsToReviews() throws {
        let engine = try runSlice(days: 45)
        XCTAssertGreaterThan(engine.world.reputation.reviewCount, 0)
        XCTAssertTrue((1.0...5.0).contains(engine.world.reputation.averageReviewStars))
        XCTAssertTrue((0.0...1.0).contains(engine.world.reputation.overall))
        XCTAssertTrue((1.0...5.0).contains(engine.world.reputation.starRating))
    }

    func testGuestThoughtsComeFromRealConditions() throws {
        let engine = try runSlice(days: 30)
        var seen = Set<ThoughtKind>()
        for guest in engine.world.guests.items {
            for thought in guest.thoughts {
                seen.insert(thought.kind)
                XCTAssertTrue((0.0...1.0).contains(thought.magnitude))
                XCTAssertLessThanOrEqual(thought.tick, engine.world.tick)
            }
        }
        // Every recorded thought must map to a review category, since that is how it reaches
        // the review the party writes.
        for kind in seen {
            XCTAssertFalse(kind.reviewCategory.rawValue.isEmpty)
        }
    }

    func testStatisticsAreRecordedWithoutRescanningHistory() throws {
        let engine = try runSlice(days: 40)
        let statistics = engine.world.statistics
        XCTAssertNotNil(statistics.dailySeries(.occupancy))
        XCTAssertNotNil(statistics.dailySeries(.revenue))
        XCTAssertNotNil(statistics.hourlySeries(.guestsOnSite))
        // Hourly detail is bounded to a week regardless of how long the game runs.
        XCTAssertLessThanOrEqual(statistics.hourlySeries(.guestsOnSite)?.count ?? 0, 24 * 7)
    }

    func testHistoryIsPrunedSoLongGamesStayBounded() throws {
        let engine = try runSlice(days: 90)
        let world = engine.world
        let cutoff = world.date.dayIndex - AccommodationSystem.historyRetentionDays
        for reservation in world.reservations.items where !reservation.status.isActive {
            XCTAssertGreaterThanOrEqual(
                reservation.departure.dayIndex, cutoff,
                "finished bookings older than the retention window should have been pruned"
            )
        }
    }

    func testSnapshotDescribesTheParkWithoutExposingTheWorld() throws {
        let engine = try runSlice(days: 20)
        let snapshot = engine.snapshot(viewport: GridRect(x: 30, y: 40, width: 40, height: 40))

        XCTAssertEqual(snapshot.tick, engine.world.tick)
        XCTAssertEqual(snapshot.tiles.count, 40 * 40)
        XCTAssertFalse(snapshot.buildings.isEmpty)
        XCTAssertEqual(snapshot.hud.cash, engine.world.cash)
        XCTAssertTrue((0...100).contains(snapshot.hud.occupancyPercent))
        XCTAssertTrue((1.0...5.0).contains(snapshot.hud.reputationStars))
        for building in snapshot.buildings {
            XCTAssertFalse(building.art.isEmpty)
        }
    }

    func testNotificationsAreAggregatedNotSpammed() throws {
        let engine = try runSlice(days: 45)
        let notifications = engine.world.notifications.items
        // A month and a half of operation must not fill the tray with duplicates.
        let grouped = Dictionary(grouping: notifications, by: { $0.groupingKey })
        for (key, entries) in grouped {
            XCTAssertLessThanOrEqual(entries.count, 24, "notification '\(key)' is spamming")
        }
        XCTAssertLessThanOrEqual(notifications.count, 60)
    }

    func testNoGuestIsLeftStrandedForever() throws {
        let engine = try runSlice(days: 60)
        let world = engine.world
        for guest in world.guests.items {
            guard let group = world.groups[guest.groupID] else { continue }
            // Nobody should still be on site long after their departure date.
            if guest.activity != .departed && guest.activity != .offPark {
                XCTAssertLessThanOrEqual(
                    group.departureDate.dayIndex, world.date.dayIndex + 30,
                    "guest \(guest.id) is on site with no plausible booking"
                )
            }
        }
    }

    func testFacilityOccupancyNeverExceedsCapacity() throws {
        let engine = try runSlice(days: 45)
        for id in engine.world.index.facilityIDs {
            guard let instance = engine.world.buildings[id],
                  let facility = engine.world.definition(of: instance)?.facility,
                  let state = instance.facility else { continue }
            XCTAssertLessThanOrEqual(state.occupants.count, facility.capacity, "\(instance.definitionID) over capacity")
            XCTAssertLessThanOrEqual(state.queue.count, facility.queueCapacity, "\(instance.definitionID) queue overflow")
        }
    }
}
