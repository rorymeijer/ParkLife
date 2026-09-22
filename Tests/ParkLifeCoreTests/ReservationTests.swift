import XCTest
@testable import ParkLifeCore

final class ReservationEngineTests: XCTestCase {

    private func parkWithUnits() throws -> World {
        try TestFixtures.demoPark()
    }

    private func archetype(_ id: String) throws -> GroupArchetypeDefinition {
        try TestFixtures.catalog.archetype(id)
    }

    func testAvailabilityRespectsCapacity() throws {
        let world = try parkWithUnits()
        let arrival = world.date.startOfDay.adding(days: 10)
        let departure = arrival.adding(days: 3)

        let forTwo = ReservationEngine.availableUnits(
            partySize: 2, preferredTiers: [], arrival: arrival, departure: departure, in: world
        )
        let forSix = ReservationEngine.availableUnits(
            partySize: 6, preferredTiers: [], arrival: arrival, departure: departure, in: world
        )
        XCTAssertFalse(forTwo.isEmpty)
        XCTAssertLessThanOrEqual(forSix.count, forTwo.count, "bigger parties fit in fewer units")
        for id in forSix {
            let capacity = world.definition(ofBuilding: id)?.accommodation?.capacity ?? 0
            XCTAssertGreaterThanOrEqual(capacity, 6)
        }
    }

    func testTierPreferenceIsHonoured() throws {
        let world = try parkWithUnits()
        let arrival = world.date.startOfDay.adding(days: 10)
        let units = ReservationEngine.availableUnits(
            partySize: 2, preferredTiers: [.comfort], arrival: arrival, departure: arrival.adding(days: 2), in: world
        )
        for id in units {
            XCTAssertEqual(world.definition(ofBuilding: id)?.accommodation?.tier, .comfort)
        }
    }

    func testBookingBlocksTheSameUnitForOverlappingDates() throws {
        var world = try parkWithUnits()
        let arrival = world.date.startOfDay.adding(days: 20).adding(minutes: 16 * 60)
        let departure = world.date.startOfDay.adding(days: 24).adding(minutes: 10 * 60)
        let unit = try XCTUnwrap(
            ReservationEngine.availableUnits(
                partySize: 2, preferredTiers: [], arrival: arrival, departure: departure, in: world
            ).first
        )

        let first = ReservationEngine.book(
            unit: unit, archetype: try archetype("couple"), adults: 2, children: 0,
            arrival: arrival, departure: departure,
            price: Money(euros: 400), discount: .zero, in: &world
        )
        XCTAssertNotNil(first)
        XCTAssertFalse(ReservationEngine.isAvailable(unit: unit, arrival: arrival, departure: departure, in: world))

        // Any overlap at all must be refused.
        let overlapping = ReservationEngine.book(
            unit: unit, archetype: try archetype("couple"), adults: 2, children: 0,
            arrival: arrival.adding(days: 1), departure: departure.adding(days: 1),
            price: Money(euros: 400), discount: .zero, in: &world
        )
        XCTAssertNil(overlapping, "the engine must never double-book a unit")
    }

    func testSameDayChangeoverIsAllowed() throws {
        var world = try parkWithUnits()
        let day = world.date.startOfDay.adding(days: 30)
        let firstArrival = day.adding(minutes: 16 * 60)
        let firstDeparture = day.adding(days: 3).adding(minutes: 10 * 60)
        let unit = try XCTUnwrap(
            ReservationEngine.availableUnits(
                partySize: 2, preferredTiers: [], arrival: firstArrival, departure: firstDeparture, in: world
            ).first
        )
        XCTAssertNotNil(
            ReservationEngine.book(
                unit: unit, archetype: try archetype("couple"), adults: 2, children: 0,
                arrival: firstArrival, departure: firstDeparture,
                price: Money(euros: 300), discount: .zero, in: &world
            )
        )
        // One party leaves in the morning, the next arrives that afternoon — that is not an overlap.
        let secondArrival = firstDeparture.startOfDay.adding(minutes: 16 * 60)
        XCTAssertTrue(
            ReservationEngine.isAvailable(
                unit: unit, arrival: secondArrival, departure: secondArrival.adding(days: 2), in: world
            )
        )
    }

    func testBookingRefusesAPartyThatDoesNotFit() throws {
        var world = try parkWithUnits()
        let arrival = world.date.startOfDay.adding(days: 12)
        let departure = arrival.adding(days: 2)
        let smallUnit = try XCTUnwrap(
            world.index.accommodationIDs.first {
                (world.definition(ofBuilding: $0)?.accommodation?.capacity ?? 0) == 4
            }
        )
        XCTAssertNil(
            ReservationEngine.book(
                unit: smallUnit, archetype: try archetype("multiGenerational"),
                adults: 5, children: 4, arrival: arrival, departure: departure,
                price: Money(euros: 900), discount: .zero, in: &world
            )
        )
    }

    func testStayPriceSumsEveryNight() throws {
        let world = try parkWithUnits()
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        let arrival = world.date.startOfDay.adding(days: 5)
        let oneNight = ReservationEngine.stayPrice(unit: unit, arrival: arrival, departure: arrival.adding(days: 1), in: world)
        let threeNights = ReservationEngine.stayPrice(unit: unit, arrival: arrival, departure: arrival.adding(days: 3), in: world)
        XCTAssertGreaterThan(oneNight.cents, 0)
        XCTAssertGreaterThan(threeNights.cents, oneNight.cents)
        XCTAssertLessThanOrEqual(threeNights.cents, oneNight.cents * 4)
    }

    func testSeasonalPricingRaisesSummerRates() throws {
        var world = try parkWithUnits()
        world.pricing.seasonalPricingEnabled = true
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        let instance = try XCTUnwrap(world.buildings[unit])
        let definition = try XCTUnwrap(world.definition(of: instance))

        let winter = world.pricing.nightlyPrice(definition: definition, instance: instance, date: GameDate(year: 2027, month: 1, day: 12))
        let summer = world.pricing.nightlyPrice(definition: definition, instance: instance, date: GameDate(year: 2027, month: 7, day: 12))
        XCTAssertGreaterThan(summer.cents, winter.cents)

        world.pricing.seasonalPricingEnabled = false
        let flatWinter = world.pricing.nightlyPrice(definition: definition, instance: instance, date: GameDate(year: 2027, month: 1, day: 12))
        let flatSummer = world.pricing.nightlyPrice(definition: definition, instance: instance, date: GameDate(year: 2027, month: 7, day: 12))
        XCTAssertEqual(flatWinter, flatSummer)
    }

    func testUnitPriceOverrideWins() throws {
        var world = try parkWithUnits()
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        world.buildings.modify(unit) { $0.accommodation?.nightlyPriceOverride = Money(euros: 999) }
        let instance = try XCTUnwrap(world.buildings[unit])
        let definition = try XCTUnwrap(world.definition(of: instance))
        XCTAssertEqual(
            world.pricing.nightlyPrice(definition: definition, instance: instance, date: world.date),
            Money(euros: 999)
        )
    }

    func testAcceptanceFallsAsPriceRises() throws {
        let archetype = try self.archetype("youngFamily")
        let cheap = ReservationEngine.acceptanceProbability(
            price: Money(euros: 300), quality: 0.7, archetype: archetype,
            partySize: 4, nights: 4, frugality: 0.5
        )
        let expensive = ReservationEngine.acceptanceProbability(
            price: Money(euros: 1_400), quality: 0.7, archetype: archetype,
            partySize: 4, nights: 4, frugality: 0.5
        )
        XCTAssertEqual(cheap, 1.0, accuracy: 0.0001)
        XCTAssertLessThan(expensive, 0.6)
        XCTAssertGreaterThan(expensive, 0.0)
    }

    func testQualityJustifiesAHigherPrice() throws {
        let archetype = try self.archetype("couple")
        let price = Money(euros: 900)
        let basic = ReservationEngine.acceptanceProbability(
            price: price, quality: 0.4, archetype: archetype, partySize: 2, nights: 4, frugality: 0.5
        )
        let luxury = ReservationEngine.acceptanceProbability(
            price: price, quality: 0.95, archetype: archetype, partySize: 2, nights: 4, frugality: 0.5
        )
        XCTAssertGreaterThan(luxury, basic, "a high price is acceptable when the quality supports it")
    }

    func testFrugalGuestsAreHarderToSell() throws {
        let archetype = try self.archetype("friendGroup")
        let price = Money(euros: 800)
        let relaxed = ReservationEngine.acceptanceProbability(
            price: price, quality: 0.6, archetype: archetype, partySize: 4, nights: 3, frugality: 0.1
        )
        let careful = ReservationEngine.acceptanceProbability(
            price: price, quality: 0.6, archetype: archetype, partySize: 4, nights: 3, frugality: 0.9
        )
        XCTAssertGreaterThanOrEqual(relaxed, careful)
    }

    func testQualityReflectsConditionAndCleanliness() throws {
        var world = try parkWithUnits()
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        let pristine = ReservationEngine.quality(of: unit, in: world)
        world.buildings.modify(unit) { building in
            building.condition = 0.3
            building.accommodation?.cleanliness = 0.2
        }
        XCTAssertLessThan(ReservationEngine.quality(of: unit, in: world), pristine)
    }

    func testStatusHelpers() {
        XCTAssertTrue(ReservationStatus.booked.holdsUnit)
        XCTAssertTrue(ReservationStatus.checkedIn.holdsUnit)
        XCTAssertFalse(ReservationStatus.cancelled.holdsUnit)
        XCTAssertFalse(ReservationStatus.checkedOut.holdsUnit)
        XCTAssertFalse(ReservationStatus.noShow.isActive)
    }
}

final class DemandSystemTests: XCTestCase {

    func testDemandGeneratesBookingsOverAWeek() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 7 * GameDate.minutesPerDay)
        XCTAssertGreaterThan(engine.world.reservations.count, 0, "a week should produce bookings")
        XCTAssertGreaterThan(engine.world.groups.count, 0)
    }

    func testSeasonalityMakesSummerBusierThanWinter() {
        let summer = DemandSystem.seasonFactor(for: GameDate(year: 2026, month: 7, day: 20))
        let winter = DemandSystem.seasonFactor(for: GameDate(year: 2026, month: 1, day: 20))
        XCTAssertGreaterThan(summer, winter * 2)
    }

    func testWeekendArrivalsArePreferred() {
        XCTAssertGreaterThan(
            DemandSystem.weekdayFactor(for: GameDate(year: 2026, month: 6, day: 12)),  // Friday
            DemandSystem.weekdayFactor(for: GameDate(year: 2026, month: 6, day: 10))   // Wednesday
        )
    }

    func testSchoolHolidaysOnlyPullFamilies() throws {
        let world = try TestFixtures.demoPark()
        let summerHoliday = GameDate(year: 2026, month: 7, day: 20)
        let family = try TestFixtures.catalog.archetype("youngFamily")
        let seniors = try TestFixtures.catalog.archetype("seniorCouple")

        let familyFactor = DemandSystem.calendarFactor(for: summerHoliday, archetype: family, world: world)
        let seniorFactor = DemandSystem.calendarFactor(for: summerHoliday, archetype: seniors, world: world)
        XCTAssertGreaterThan(familyFactor, seniorFactor, "only school-bound families are tied to the school calendar")
        XCTAssertGreaterThan(familyFactor, 1.5)
    }

    func testAnEmptyParkIsAHarderSellThanAFullOne() throws {
        let bare = try GameSetup.newGame(scenarioID: "sandbox-zandheuvel", catalog: TestFixtures.catalog)
        let developed = try TestFixtures.demoPark()
        XCTAssertLessThan(DemandSystem.facilityFactor(in: bare), DemandSystem.facilityFactor(in: developed))
    }

    func testNoBookingsWithoutAccommodation() throws {
        let world = try GameSetup.newGame(scenarioID: "sandbox-zandheuvel", catalog: TestFixtures.catalog)
        let engine = SimulationEngine(world: world)
        engine.run(ticks: 3 * GameDate.minutesPerDay)
        XCTAssertEqual(engine.world.reservations.count, 0, "nothing to book means nothing booked")
    }

    func testOccupancyReportingMatchesReservations() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 20 * GameDate.minutesPerDay)
        let day = engine.world.date.dayIndex
        let occupied = ReservationSystem.occupiedUnits(on: day, in: engine.world)
        XCTAssertLessThanOrEqual(occupied, engine.world.index.accommodationIDs.count)
        let rate = ReservationSystem.occupancyRate(on: day, in: engine.world)
        XCTAssertTrue((0...1).contains(rate))
    }

    func testRevenueForecastIsBounded() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 20 * GameDate.minutesPerDay)
        let forecast = ReservationSystem.revenueForecast(days: 14, from: engine.world.date.dayIndex, in: engine.world)
        XCTAssertEqual(forecast.count, 14)
        XCTAssertTrue(forecast.allSatisfy { $0.cents >= 0 })
    }

    func testNoUnitIsEverDoubleBooked() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 45 * GameDate.minutesPerDay)

        // Exhaustive check: for every unit, no two holding reservations may overlap.
        for unitID in engine.world.index.accommodationIDs {
            let holding = engine.world.index.reservations(forUnit: unitID)
                .compactMap { engine.world.reservations[$0] }
                .filter { $0.status.holdsUnit }
                .sorted { $0.arrival.dayIndex < $1.arrival.dayIndex }
            for index in 1..<max(1, holding.count) where holding.count > 1 {
                let previous = holding[index - 1]
                let current = holding[index]
                XCTAssertLessThanOrEqual(
                    previous.departure.dayIndex, current.arrival.dayIndex,
                    "unit \(unitID) is double-booked between reservations \(previous.id) and \(current.id)"
                )
            }
        }
    }
}
