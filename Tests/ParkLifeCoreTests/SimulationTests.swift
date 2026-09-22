import XCTest
@testable import ParkLifeCore

final class DeterminismTests: XCTestCase {

    func testSameSeedProducesTheSameWorld() throws {
        func run() throws -> UInt64 {
            let world = try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: 0xABCD_1234)
            let engine = SimulationEngine(world: world)
            engine.run(ticks: 20 * GameDate.minutesPerDay)
            return try engine.worldHash()
        }
        XCTAssertEqual(try run(), try run(), "the same seed must produce an identical world")
    }

    func testDifferentSeedsDiverge() throws {
        func run(_ seed: UInt64) throws -> UInt64 {
            let engine = SimulationEngine(world: try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: seed))
            engine.run(ticks: 20 * GameDate.minutesPerDay)
            return try engine.worldHash()
        }
        XCTAssertNotEqual(try run(1), try run(2))
    }

    func testTickGranularityDoesNotChangeOutcomes() throws {
        // Running 10 days in one go must match running them a day at a time: the simulation is a
        // pure function of ticks, not of how they are batched.
        let coarse = SimulationEngine(world: try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: 77))
        coarse.run(ticks: 10 * GameDate.minutesPerDay)

        let fine = SimulationEngine(world: try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: 77))
        for _ in 0..<10 {
            fine.run(ticks: GameDate.minutesPerDay)
        }
        XCTAssertEqual(try coarse.worldHash(), try fine.worldHash())
    }

    func testSpeedSettingDoesNotChangeOutcomes() throws {
        let slow = SimulationEngine(world: try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: 5))
        slow.submit(.setSpeed(.normal))
        slow.run(ticks: 5 * GameDate.minutesPerDay)

        let fast = SimulationEngine(world: try GameSetup.makeDemoPark(catalog: TestFixtures.catalog, seed: 5))
        fast.submit(.setSpeed(.maximum))
        fast.run(ticks: 5 * GameDate.minutesPerDay)

        // Speed only decides how many ticks run per second of real time.
        XCTAssertEqual(slow.world.clock.tick, fast.world.clock.tick)
        XCTAssertEqual(slow.world.cash, fast.world.cash)
        XCTAssertEqual(slow.world.statistics.totalGuestsHosted, fast.world.statistics.totalGuestsHosted)
    }
}

final class SystemOrderTests: XCTestCase {

    func testOrderIsDeclaredAndStable() {
        let order = SimulationEngine.systemOrder
        XCTAssertEqual(order.first, TimeSystem.systemName)
        XCTAssertEqual(order.last, NotificationSystem.systemName)
        XCTAssertEqual(Set(order).count, order.count, "no system may appear twice")
    }

    func testLoadBearingOrderings() throws {
        let order = SimulationEngine.systemOrder
        func index(_ name: String) throws -> Int {
            try XCTUnwrap(order.firstIndex(of: name), "\(name) is missing from the tick order")
        }
        // Needs must drift before decisions are taken on them.
        XCTAssertLessThan(try index(GuestAISystem.systemName), try index(MovementSystem.systemName))
        // Guests must arrive at a facility before it serves them.
        XCTAssertLessThan(try index(MovementSystem.systemName), try index(FacilitySystem.systemName))
        // Spending must be booked before the day is settled.
        XCTAssertLessThan(try index(FacilitySystem.systemName), try index(EconomySystem.systemName))
        // Reviews are written before reputation folds them in.
        XCTAssertLessThan(try index(ReviewSystem.systemName), try index(ReputationSystem.systemName))
        // Everything else happens before statistics and notifications observe it.
        XCTAssertLessThan(try index(ReputationSystem.systemName), try index(StatisticsSystem.systemName))
        XCTAssertLessThan(try index(StatisticsSystem.systemName), try index(NotificationSystem.systemName))
        // Bookings exist before anyone can arrive on them.
        XCTAssertLessThan(try index(DemandSystem.systemName), try index(ReservationSystem.systemName))
        XCTAssertLessThan(try index(ReservationSystem.systemName), try index(ArrivalSystem.systemName))
    }

    func testClockAdvancesOneMinutePerTick() throws {
        let engine = try TestFixtures.demoEngine()
        let before = engine.world.clock.tick
        engine.run(ticks: 90)
        XCTAssertEqual(engine.world.clock.tick, before + 90)
        XCTAssertEqual(engine.world.date.minutesSinceEpoch, before + 90)
    }
}

final class WeatherSystemTests: XCTestCase {

    func testWeatherIsGeneratedDailyAndStaysPlausible() throws {
        let engine = try TestFixtures.demoEngine()
        var seenConditions = Set<WeatherCondition>()
        for _ in 0..<60 {
            engine.run(ticks: GameDate.minutesPerDay)
            seenConditions.insert(engine.world.weather.condition)
            XCTAssertTrue((-30.0...45.0).contains(engine.world.weather.temperature), "temperature out of range")
            XCTAssertTrue((0.0...1.0).contains(engine.world.weather.precipitation))
            XCTAssertGreaterThanOrEqual(engine.world.weather.windKph, 0)
        }
        XCTAssertGreaterThan(seenConditions.count, 1, "the weather should actually change")
    }

    func testSummerIsWarmerThanWinter() throws {
        func meanTemperature(startingMonth month: Int) throws -> Double {
            var world = try TestFixtures.demoPark()
            world.clock.setTick(GameDate(year: 2026, month: month, day: 10, hour: 12).minutesSinceEpoch)
            let engine = SimulationEngine(world: world)
            var total = 0.0
            for _ in 0..<20 {
                engine.run(ticks: GameDate.minutesPerDay)
                total += engine.world.weather.dailyMeanTemperature
            }
            return total / 20.0
        }
        XCTAssertGreaterThan(try meanTemperature(startingMonth: 7), try meanTemperature(startingMonth: 1) + 5)
    }

    func testRainDrivesGuestsIndoors() {
        XCTAssertGreaterThan(WeatherCondition.rain.indoorAppealMultiplier, WeatherCondition.clear.indoorAppealMultiplier)
        XCTAssertLessThan(WeatherCondition.rain.outdoorAppealMultiplier, WeatherCondition.clear.outdoorAppealMultiplier)
    }

    func testComfortIndexPeaksInPleasantWeather() {
        var pleasant = Weather()
        pleasant.temperature = 21
        pleasant.precipitation = 0
        pleasant.windKph = 8

        var miserable = Weather()
        miserable.temperature = 4
        miserable.precipitation = 0.9
        miserable.windKph = 60

        XCTAssertGreaterThan(pleasant.comfortIndex, 0.8)
        XCTAssertLessThan(miserable.comfortIndex, 0.3)
    }
}

final class StaffSystemTests: XCTestCase {

    func testHiringAndDismissing() throws {
        var world = try TestFixtures.demoPark()
        let before = world.staff.count
        let id = try XCTUnwrap(StaffSystem.hire(roleID: "housekeeping", world: &world))
        XCTAssertEqual(world.staff.count, before + 1)
        XCTAssertEqual(world.staff[id]?.roleID, "housekeeping")
        XCTAssertFalse(world.staff[id]?.name.isEmpty ?? true)

        XCTAssertTrue(StaffSystem.dismiss(id, world: &world))
        XCTAssertEqual(world.staff.count, before)
        XCTAssertNil(StaffSystem.hire(roleID: "not-a-real-role", world: &world))
    }

    func testDismissingReleasesTheCurrentTask() throws {
        var world = try TestFixtures.demoPark()
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        var context = TickContext(tick: world.tick, date: world.date, previousDate: world.date, tuning: SimulationTuning())
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)
        let taskID = try XCTUnwrap(world.tasks.items.first?.id)
        let staffID = try XCTUnwrap(world.staff.items.first { $0.roleID == "housekeeping" }?.id)

        world.tasks.modify(taskID) { $0.assignedTo = staffID; $0.state = .assigned }
        world.staff.modify(staffID) { $0.currentTask = taskID }

        XCTAssertTrue(StaffSystem.dismiss(staffID, world: &world))
        XCTAssertEqual(world.tasks[taskID]?.state, .pending, "an unfinished task goes back in the queue")
        XCTAssertNil(world.tasks[taskID]?.assignedTo)
    }

    func testCleaningTasksAreNotDuplicated() throws {
        var world = try TestFixtures.demoPark()
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        var context = TickContext(tick: world.tick, date: world.date, previousDate: world.date, tuning: SimulationTuning())
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)
        XCTAssertEqual(world.tasks.count, 1)
    }

    func testHousekeepingReturnsADirtyCottageToReady() throws {
        var world = try TestFixtures.demoPark()
        // Put the cottage in the state a departing party leaves it in.
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        world.buildings.modify(unit) { building in
            building.accommodation?.state = .dirty
            building.accommodation?.cleanliness = 0.2
        }
        world.clock.setTick(GameDate(year: 2026, month: 4, day: 2, hour: 9).minutesSinceEpoch)
        var context = TickContext(tick: world.tick, date: world.date, previousDate: world.date, tuning: SimulationTuning())
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)

        let engine = SimulationEngine(world: world)
        engine.run(ticks: 6 * 60)

        XCTAssertEqual(engine.world.buildings[unit]?.accommodation?.state, .ready, "a housekeeper should have cleaned it")
        XCTAssertEqual(engine.world.buildings[unit]?.accommodation?.cleanliness, 1.0)
    }

    func testWithoutHousekeepersCottagesStayDirty() throws {
        var world = try TestFixtures.demoPark()
        for staffID in world.staff.sortedIDs where world.staff[staffID]?.roleID == "housekeeping" {
            StaffSystem.dismiss(staffID, world: &world)
        }
        let unit = try XCTUnwrap(world.index.accommodationIDs.first)
        world.buildings.modify(unit) { $0.accommodation?.state = .dirty }
        world.clock.setTick(GameDate(year: 2026, month: 4, day: 2, hour: 9).minutesSinceEpoch)
        var context = TickContext(tick: world.tick, date: world.date, previousDate: world.date, tuning: SimulationTuning())
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)

        let engine = SimulationEngine(world: world)
        engine.run(ticks: 8 * 60)
        XCTAssertEqual(
            engine.world.buildings[unit]?.accommodation?.state, .dirty,
            "a staff shortage must have consequences, not be silently papered over"
        )
        XCTAssertGreaterThan(StaffSystem.pendingCleaningCount(in: engine.world), 0)
    }

    func testShiftBoundaries() {
        var member = StaffMember(
            id: StaffID(raw: 1), name: "Test", roleID: "housekeeping",
            monthlySalary: Money(euros: 2_000), skill: 0.5,
            position: WorldPoint(x: 0, y: 0), hiredAtTick: 0
        )
        member.shiftStartMinute = 8 * 60
        member.shiftEndMinute = 17 * 60
        XCTAssertTrue(member.isOnShift(minuteOfDay: 12 * 60))
        XCTAssertFalse(member.isOnShift(minuteOfDay: 7 * 60))
        XCTAssertFalse(member.isOnShift(minuteOfDay: 18 * 60))

        member.shiftStartMinute = 22 * 60
        member.shiftEndMinute = 6 * 60
        XCTAssertTrue(member.isOnShift(minuteOfDay: 23 * 60))
        XCTAssertTrue(member.isOnShift(minuteOfDay: 2 * 60))
        XCTAssertFalse(member.isOnShift(minuteOfDay: 12 * 60))
    }
}

final class ObjectiveSystemTests: XCTestCase {

    func testScenarioObjectivesAreEvaluated() throws {
        var world = try GameSetup.newGame(scenarioID: "career-nl-1", catalog: TestFixtures.catalog)
        world.scenarioID = "career-nl-1"
        let statuses = ObjectiveSystem.statuses(in: world)
        XCTAssertEqual(statuses.count, 3)
        XCTAssertFalse(ObjectiveSystem.allComplete(in: world), "a brand new park has met nothing yet")
        for status in statuses {
            XCTAssertTrue((0.0...1.0).contains(status.progress))
        }
    }

    func testSustainedObjectivesNeedConsecutiveDays() throws {
        var world = try GameSetup.newGame(scenarioID: "career-nl-1", catalog: TestFixtures.catalog)
        // Force the occupancy objective to be met and let a few days pass.
        world.bookkeeping.objectiveSustainedDays["occupancy70"] = 10
        let status = try XCTUnwrap(ObjectiveSystem.statuses(in: world).first { $0.definition.id == "occupancy70" })
        XCTAssertEqual(status.sustainedDays, 10)
        XCTAssertFalse(status.isComplete, "not met right now, so the streak does not count")
    }

    func testMetricsReadRealWorldState() throws {
        var world = try TestFixtures.demoPark()
        world.cash = Money(euros: 12_345)
        XCTAssertEqual(ObjectiveSystem.measure(.cash, in: world), 12_345, accuracy: 0.01)
        world.statistics.totalGuestsHosted = 4_200
        XCTAssertEqual(ObjectiveSystem.measure(.totalGuestsHosted, in: world), 4_200)
        XCTAssertEqual(ObjectiveSystem.measure(.reputation, in: world), world.reputation.overall, accuracy: 0.0001)
    }

    func testWorldWithoutAScenarioHasNoObjectives() throws {
        var world = try TestFixtures.demoPark()
        world.scenarioID = nil
        XCTAssertTrue(ObjectiveSystem.statuses(in: world).isEmpty)
        XCTAssertFalse(ObjectiveSystem.allComplete(in: world))
    }
}

final class ResearchSystemTests: XCTestCase {

    func testAvailableProjectsRespectPrerequisites() throws {
        var world = try TestFixtures.demoPark()
        let initial = ResearchSystem.availableProjects(in: world).map(\.id)
        XCTAssertTrue(initial.contains("acc_waterfront"))
        XCTAssertFalse(initial.contains("acc_vip"), "VIP villas need waterfront lodges first")

        world.completedResearch = ["acc_waterfront"]
        XCTAssertTrue(ResearchSystem.availableProjects(in: world).map(\.id).contains("acc_vip"))
        XCTAssertFalse(ResearchSystem.availableProjects(in: world).map(\.id).contains("acc_waterfront"))
    }

    func testResearchCompletesAndUnlocksBuildings() throws {
        var world = try TestFixtures.demoPark()
        XCTAssertTrue(ResearchSystem.start("act_bikes", in: &world))
        let engine = SimulationEngine(world: world)
        // Bicycle hire takes three weeks.
        engine.run(ticks: 30 * GameDate.minutesPerDay)

        XCTAssertTrue(engine.world.completedResearch.contains("act_bikes"))
        XCTAssertNil(engine.world.activeResearchID)
        let available = TestFixtures.catalog.availableBuildings(completedResearch: Set(engine.world.completedResearch))
        XCTAssertTrue(available.contains { $0.id == "bike_rental" })
    }

    func testCannotResearchSomethingTwice() throws {
        var world = try TestFixtures.demoPark()
        world.completedResearch = ["act_bikes"]
        XCTAssertFalse(ResearchSystem.start("act_bikes", in: &world))
        XCTAssertFalse(ResearchSystem.start("not-a-project", in: &world))
    }
}
