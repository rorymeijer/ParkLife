import XCTest
@testable import ParkLifeCore

final class GameDateTests: XCTestCase {

    func testEpochIsThursdayFirstOfJanuary() {
        let epoch = GameDate(minutesSinceEpoch: 0)
        XCTAssertEqual(epoch.year, 2026)
        XCTAssertEqual(epoch.month, 1)
        XCTAssertEqual(epoch.dayOfMonth, 1)
        XCTAssertEqual(epoch.weekday, .thursday)
        XCTAssertEqual(epoch.dayOfYear, 1)
        XCTAssertEqual(epoch.gameYear, 1)
    }

    func testConstructionFromComponents() {
        let date = GameDate(year: 2026, month: 3, day: 2, hour: 14, minute: 30)
        XCTAssertEqual(date.dayIndex, 60)
        XCTAssertEqual(date.hour, 14)
        XCTAssertEqual(date.minute, 30)
        XCTAssertEqual(date.weekday, .monday)
        XCTAssertEqual(date.season, .spring)
    }

    func testLeapYearHandling() {
        let date = GameDate(year: 2028, month: 2, day: 29)
        XCTAssertEqual(date.dayIndex, 789)
        XCTAssertEqual(date.month, 2)
        XCTAssertEqual(date.dayOfMonth, 29)
        XCTAssertEqual(date.weekday, .tuesday)
    }

    func testSeasons() {
        XCTAssertEqual(GameDate(year: 2026, month: 4, day: 10).season, .spring)
        XCTAssertEqual(GameDate(year: 2026, month: 7, day: 10).season, .summer)
        XCTAssertEqual(GameDate(year: 2026, month: 10, day: 10).season, .autumn)
        XCTAssertEqual(GameDate(year: 2026, month: 12, day: 25).season, .winter)
        XCTAssertEqual(GameDate(year: 2026, month: 12, day: 25).weekday, .friday)
    }

    func testWeekendDetection() {
        XCTAssertTrue(GameDate(year: 2026, month: 1, day: 3).isWeekend)   // Saturday
        XCTAssertTrue(GameDate(year: 2026, month: 1, day: 4).isWeekend)   // Sunday
        XCTAssertFalse(GameDate(year: 2026, month: 1, day: 5).isWeekend)  // Monday
    }

    func testNightsBetweenDates() {
        let arrival = GameDate(year: 2026, month: 6, day: 12, hour: 16)
        let departure = GameDate(year: 2026, month: 6, day: 15, hour: 10)
        // Friday afternoon to Monday morning is three nights, as a hotel counts them.
        XCTAssertEqual(arrival.nights(until: departure), 3)
        XCTAssertEqual(departure.nights(until: arrival), 0)
    }

    func testMinuteOfDayAndStartOfDay() {
        let date = GameDate(year: 2026, month: 5, day: 4, hour: 23, minute: 59)
        XCTAssertEqual(date.minuteOfDay, 23 * 60 + 59)
        XCTAssertEqual(date.startOfDay.minuteOfDay, 0)
        XCTAssertEqual(date.startOfDay.dayIndex, date.dayIndex)
        XCTAssertEqual(date.adding(minutes: 1).dayIndex, date.dayIndex + 1)
    }

    func testMonotonicityAcrossAYear() {
        var previous = GameDate(minutesSinceEpoch: 0)
        for day in 1...800 {
            let date = GameDate(minutesSinceEpoch: day * GameDate.minutesPerDay)
            XCTAssertGreaterThan(date, previous)
            XCTAssertEqual(date.dayIndex, previous.dayIndex + 1)
            previous = date
        }
    }
}

final class SimulationClockTests: XCTestCase {

    func testPausedClockDoesNotAdvance() {
        var clock = SimulationClock(startDate: GameDate(year: 2026, month: 3, day: 1), speed: .paused)
        XCTAssertEqual(clock.pendingTicks(forRealSeconds: 10, maximumTicks: 64), 0)
    }

    func testFixedStepAccumulatesFractions() {
        var clock = SimulationClock(speed: .normal)   // 2 ticks per real second
        XCTAssertEqual(clock.pendingTicks(forRealSeconds: 0.25, maximumTicks: 64), 0)
        XCTAssertEqual(clock.pendingTicks(forRealSeconds: 0.25, maximumTicks: 64), 1)
        XCTAssertEqual(clock.pendingTicks(forRealSeconds: 1.0, maximumTicks: 64), 2)
    }

    func testTickCapIsRespected() {
        var clock = SimulationClock(speed: .maximum)  // 64 ticks per real second
        XCTAssertEqual(clock.pendingTicks(forRealSeconds: 10, maximumTicks: 64), 64)
    }

    func testSpeedsAreOrdered() {
        XCTAssertEqual(GameSpeed.paused.ticksPerSecond, 0)
        XCTAssertLessThan(GameSpeed.normal.ticksPerSecond, GameSpeed.fast.ticksPerSecond)
        XCTAssertLessThan(GameSpeed.fast.ticksPerSecond, GameSpeed.veryFast.ticksPerSecond)
        XCTAssertLessThan(GameSpeed.veryFast.ticksPerSecond, GameSpeed.maximum.ticksPerSecond)
    }

    func testCodableKeepsTickAndSpeed() throws {
        var clock = SimulationClock(startDate: GameDate(year: 2026, month: 8, day: 1, hour: 9), speed: .fast)
        clock.advanceOneTick()
        let restored = try JSONDecoder().decode(SimulationClock.self, from: try JSONEncoder().encode(clock))
        XCTAssertEqual(restored.tick, clock.tick)
        XCTAssertEqual(restored.speed, .fast)
    }
}

final class ScheduleQueueTests: XCTestCase {

    func testDrainsInTickOrder() {
        var queue = ScheduleQueue()
        queue.schedule(.guestWake, entity: 1, at: 50)
        queue.schedule(.guestWake, entity: 2, at: 10)
        queue.schedule(.guestWake, entity: 3, at: 30)

        let due = queue.drain(upTo: 40)
        XCTAssertEqual(due.map(\.entity), [2, 3])
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.drain(upTo: 100).map(\.entity), [1])
    }

    func testSameTickEventsFireInInsertionOrder() {
        var queue = ScheduleQueue()
        for entity in UInt32(1)...UInt32(5) {
            queue.schedule(.facilityServiceComplete, entity: entity, at: 20)
        }
        XCTAssertEqual(queue.drain(upTo: 20).map(\.entity), [1, 2, 3, 4, 5])
    }

    func testCodableRoundTripPreservesOrder() throws {
        var queue = ScheduleQueue()
        queue.schedule(.guestWake, entity: 7, at: 99)
        queue.schedule(.unitTurnaroundComplete, entity: 8, at: 12)
        let restored = try JSONDecoder().decode(ScheduleQueue.self, from: try JSONEncoder().encode(queue))
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.pendingEvents.first?.entity, 8)
    }

    func testDormantEntitiesCostNothingUntilDue() {
        var queue = ScheduleQueue()
        for entity in UInt32(0)..<UInt32(3_000) {
            queue.schedule(.guestWake, entity: entity, at: 1_000)
        }
        // Nothing is due yet: a park full of sleeping guests does no work.
        XCTAssertTrue(queue.drain(upTo: 999).isEmpty)
        XCTAssertEqual(queue.drain(upTo: 1_000).count, 3_000)
    }
}
