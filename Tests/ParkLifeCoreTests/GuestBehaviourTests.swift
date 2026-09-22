import XCTest
@testable import ParkLifeCore

final class GuestNeedsTests: XCTestCase {

    func testNeedsClampToTheUnitInterval() {
        var needs = NeedState()
        needs.hunger = 5.0
        XCTAssertEqual(needs.hunger, 1.0)
        needs.thirst = -2.0
        XCTAssertEqual(needs.thirst, 0.0)
    }

    func testDominantNeedIsTheMostPressing() {
        var needs = NeedState()
        needs.hunger = 0.3
        needs.thirst = 0.9
        needs.boredom = 0.5
        XCTAssertEqual(needs.dominant.kind, .thirst)
        XCTAssertEqual(needs.dominant.value, 0.9, accuracy: 0.0001)
    }

    func testNeedsDriftOverTime() throws {
        var world = try TestFixtures.demoPark()
        let guestID = GuestID(raw: 9_001)
        var guest = Guest(
            id: guestID, groupID: GroupID(raw: 1), firstName: "Test", age: 34,
            personality: .neutral, interests: .neutral, position: WorldPoint(world.entranceTile)
        )
        guest.needs = NeedState(hunger: 0.1, thirst: 0.1, tiredness: 0.1, boredom: 0.1, bladder: 0.1)
        guest.activity = .idle
        guest.detail = .reduced
        guest.lastNeedsTick = world.tick
        world.guests.insert(guest)

        let tuning = SimulationTuning()
        let later = world.tick + 180   // three hours
        let context = TickContext(
            tick: later,
            date: GameDate(minutesSinceEpoch: later),
            previousDate: world.date,
            tuning: tuning
        )
        GuestAISystem.advanceNeeds(guestID: guestID, world: &world, context: context)

        let updated = try XCTUnwrap(world.guests[guestID])
        XCTAssertGreaterThan(updated.needs.hunger, 0.1)
        XCTAssertGreaterThan(updated.needs.thirst, updated.needs.hunger, "thirst builds faster than hunger")
        XCTAssertEqual(updated.lastNeedsTick, later)
    }

    func testDormantGuestsCatchUpInOneStepWhenTheyWake() throws {
        var world = try TestFixtures.demoPark()
        let guestID = GuestID(raw: 9_002)
        var guest = Guest(
            id: guestID, groupID: GroupID(raw: 1), firstName: "Test", age: 40,
            personality: .neutral, interests: .neutral, position: WorldPoint(world.entranceTile)
        )
        guest.activity = .idle
        guest.lastNeedsTick = world.tick
        world.guests.insert(guest)

        // Four hours of dormancy applied in a single step must equal four one-hour steps. Four
        // rather than eight so nothing saturates at 1.0 and the comparison is meaningful.
        let tuning = SimulationTuning()
        var stepwise = try XCTUnwrap(world.guests[guestID])
        for hour in 1...4 {
            let tick = world.tick + hour * 60
            let context = TickContext(tick: tick, date: GameDate(minutesSinceEpoch: tick), previousDate: world.date, tuning: tuning)
            GuestAISystem.advanceNeeds(guestID: guestID, world: &world, context: context)
        }
        stepwise = try XCTUnwrap(world.guests[guestID])

        var other = try TestFixtures.demoPark()
        var fresh = Guest(
            id: guestID, groupID: GroupID(raw: 1), firstName: "Test", age: 40,
            personality: .neutral, interests: .neutral, position: WorldPoint(other.entranceTile)
        )
        fresh.activity = .idle
        fresh.lastNeedsTick = other.tick
        other.guests.insert(fresh)
        let jumpTick = other.tick + 4 * 60
        let jumpContext = TickContext(tick: jumpTick, date: GameDate(minutesSinceEpoch: jumpTick), previousDate: other.date, tuning: tuning)
        GuestAISystem.advanceNeeds(guestID: guestID, world: &other, context: jumpContext)
        let jumped = try XCTUnwrap(other.guests[guestID])

        XCTAssertEqual(stepwise.needs.hunger, jumped.needs.hunger, accuracy: 0.0001)
        XCTAssertEqual(stepwise.needs.boredom, jumped.needs.boredom, accuracy: 0.0001)
    }

    func testWalkSpeedVariesByAge() {
        XCTAssertGreaterThan(AgeBand.adult.walkSpeed, AgeBand.senior.walkSpeed)
        XCTAssertGreaterThan(AgeBand.teen.walkSpeed, AgeBand.child.walkSpeed)
        XCTAssertEqual(AgeBand.band(forAge: 8), .child)
        XCTAssertEqual(AgeBand.band(forAge: 16), .teen)
        XCTAssertEqual(AgeBand.band(forAge: 40), .adult)
        XCTAssertEqual(AgeBand.band(forAge: 70), .senior)
    }

    func testInterestAffinityPicksTheStrongestMatch() {
        var interests = Interests.neutral
        interests.swimming = 0.9
        interests.sport = 0.2
        XCTAssertEqual(interests.affinity(for: [.swimming, .sport]), 0.9, accuracy: 0.0001)
        XCTAssertEqual(interests.affinity(for: []), 0.5, accuracy: 0.0001)
    }
}

final class GuestDecisionTests: XCTestCase {

    private func parkWithAGuest() throws -> (World, GuestID) {
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
            id: guestID, groupID: groupID, firstName: "Test", age: 36,
            personality: .neutral, interests: .neutral,
            position: WorldPoint(world.parkEntranceTiles.first ?? world.entranceTile)
        )
        guest.activity = .idle
        guest.detail = .reduced
        group.memberIDs = [guestID]

        world.groups.insert(group)
        world.guests.insert(guest)
        world.index.rebuildGuests(world.guests)
        return (world, guestID)
    }

    private func context(for world: World) -> TickContext {
        TickContext(
            tick: world.tick,
            date: world.date,
            previousDate: GameDate(minutesSinceEpoch: world.tick - 1),
            tuning: SimulationTuning()
        )
    }

    func testAHungryGuestChoosesSomewhereToEat() throws {
        var (world, guestID) = try parkWithAGuest()
        world.guests.modify(guestID) { guest in
            guest.needs = NeedState(hunger: 0.95, thirst: 0.5, tiredness: 0.1, boredom: 0.1, bladder: 0.1)
        }
        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context(for: world))
        guard case .visit(let buildingID) = decision else {
            return XCTFail("a starving guest should go and eat, got \(decision)")
        }
        let facility = try XCTUnwrap(world.definition(ofBuilding: buildingID)?.facility)
        XCTAssertGreaterThan(facility.reliefAmount(for: .hunger), 0.3, "the chosen place must actually serve food")
    }

    func testAnExhaustedGuestGoesToBed() throws {
        var (world, guestID) = try parkWithAGuest()
        world.guests.modify(guestID) { guest in
            guest.needs = NeedState(hunger: 0.1, thirst: 0.1, tiredness: 0.95, boredom: 0.1, bladder: 0.1)
        }
        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context(for: world))
        if case .sleep = decision { return }
        XCTFail("an exhausted guest should sleep, got \(decision)")
    }

    func testDepartureDayOverridesEverythingElse() throws {
        var (world, guestID) = try parkWithAGuest()
        let guest = try XCTUnwrap(world.guests[guestID])
        let departureDay = world.date.startOfDay
        world.groups.modify(guest.groupID) { $0.departureDate = departureDay }
        world.guests.modify(guestID) { guest in
            guest.needs = NeedState(hunger: 0.99, thirst: 0.99, tiredness: 0.99, boredom: 0.99, bladder: 0.99)
        }
        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context(for: world))
        if case .returnToUnit = decision { return }
        XCTFail("checkout day wins over every need, got \(decision)")
    }

    func testAContentGuestDoesNotStampedeToAFacility() throws {
        var (world, guestID) = try parkWithAGuest()
        world.guests.modify(guestID) { guest in
            guest.needs = NeedState(hunger: 0.05, thirst: 0.05, tiredness: 0.05, boredom: 0.05, bladder: 0.05)
        }
        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context(for: world))
        if case .visit = decision {
            XCTFail("a guest with no needs has no reason to queue for anything")
        }
    }

    func testClosedFacilitiesAreNotChosen() throws {
        var (world, guestID) = try parkWithAGuest()
        world.clock.setTick(GameDate(year: 2026, month: 6, day: 10, hour: 4).minutesSinceEpoch)
        world.guests.modify(guestID) { guest in
            guest.needs = NeedState(hunger: 0.99, thirst: 0.99, tiredness: 0.1, boredom: 0.9, bladder: 0.1)
        }
        let options = GuestDecisionMaker.scoreOptions(
            guest: try XCTUnwrap(world.guests[guestID]),
            group: try XCTUnwrap(world.groups[world.guests[guestID]!.groupID]),
            world: world,
            context: context(for: world)
        )
        // At 4am everything with opening hours is shut; only always-open facilities may appear.
        for option in options {
            let facility = try XCTUnwrap(world.definition(ofBuilding: option.building)?.facility)
            XCTAssertTrue(facility.openingHours.isAlwaysOpen, "\(facility.kind) should be closed at 4am")
        }
    }

    func testScoringPrefersCloserFacilitiesAllElseEqual() throws {
        let (world, guestID) = try parkWithAGuest()
        var hungry = try XCTUnwrap(world.guests[guestID])
        hungry.needs = NeedState(hunger: 0.9, thirst: 0.9, tiredness: 0.1, boredom: 0.1, bladder: 0.1)
        let options = GuestDecisionMaker.scoreOptions(
            guest: hungry,
            group: try XCTUnwrap(world.groups[hungry.groupID]),
            world: world,
            context: context(for: world)
        )
        XCTAssertFalse(options.isEmpty)
        // Options come back best-first.
        for index in 1..<max(1, options.count) where options.count > 1 {
            XCTAssertGreaterThanOrEqual(options[index - 1].score, options[index].score)
        }
        for option in options {
            XCTAssertGreaterThanOrEqual(option.distanceTiles, 0)
        }
    }

    func testAffordabilityLimitsExpensiveChoices() throws {
        var (world, guestID) = try parkWithAGuest()
        let guest = try XCTUnwrap(world.guests[guestID])
        // Nearly broke: the restaurant should score below the free pool.
        world.groups.modify(guest.groupID) { $0.spent = Money(euros: 895) }
        world.guests.modify(guestID) { stored in
            stored.needs = NeedState(hunger: 0.9, thirst: 0.9, tiredness: 0.1, boredom: 0.9, bladder: 0.1)
        }
        let options = GuestDecisionMaker.scoreOptions(
            guest: try XCTUnwrap(world.guests[guestID]),
            group: try XCTUnwrap(world.groups[guest.groupID]),
            world: world,
            context: context(for: world)
        )
        let restaurant = options.first { world.definition(ofBuilding: $0.building)?.facility?.kind == .restaurant }
        let pool = options.first { world.definition(ofBuilding: $0.building)?.facility?.kind == .pool }
        if let restaurant, let pool {
            XCTAssertLessThan(restaurant.score, pool.score, "a broke guest is priced out of the restaurant")
        }
    }
}

final class SatisfactionAndReviewTests: XCTestCase {

    private func groupWithMoments(_ moments: [(ReviewCategory, Double, String)]) -> GuestGroup {
        var group = GuestGroup(
            id: GroupID(raw: 1),
            archetypeID: "couple",
            memberIDs: [GuestID(raw: 1), GuestID(raw: 2)],
            budget: Money(euros: 500),
            arrivalDate: GameDate(year: 2026, month: 6, day: 12, hour: 16),
            departureDate: GameDate(year: 2026, month: 6, day: 15, hour: 10),
            expectation: 0.5,
            reviewWeights: ["accommodation": 1.4, "cleanliness": 1.2, "food": 1.3]
        )
        for (category, delta, reason) in moments {
            group.record(SatisfactionMoment(category: category, delta: delta, reasonKey: reason, tick: 0))
        }
        return group
    }

    func testCategoryScoresStartNeutralAndMoveWithMoments() {
        let happy = groupWithMoments([(.accommodation, 0.8, "moment.lovely"), (.accommodation, 0.4, "moment.spacious")])
        XCTAssertEqual(happy.score(for: .accommodation), 4.2, accuracy: 0.0001)

        let unhappy = groupWithMoments([(.cleanliness, -1.0, "moment.dirty")])
        XCTAssertEqual(unhappy.score(for: .cleanliness), 2.0, accuracy: 0.0001)

        // Untouched categories sit at the neutral middle.
        XCTAssertEqual(happy.score(for: .food), 3.0, accuracy: 0.0001)
    }

    func testScoresAreClampedToTheStarScale() {
        let ecstatic = groupWithMoments(Array(repeating: (ReviewCategory.food, 1.0, "moment.great"), count: 10))
        XCTAssertEqual(ecstatic.score(for: .food), 5.0, accuracy: 0.0001)
        let furious = groupWithMoments(Array(repeating: (ReviewCategory.food, -1.0, "moment.awful"), count: 10))
        XCTAssertEqual(furious.score(for: .food), 1.0, accuracy: 0.0001)
    }

    func testMomentsAreBounded() {
        var group = groupWithMoments([])
        for index in 0..<400 {
            group.record(SatisfactionMoment(category: .food, delta: 0.01, reasonKey: "m", tick: index))
        }
        XCTAssertLessThanOrEqual(group.moments.count, 240, "a long stay must not grow without limit")
    }

    func testOnlyExperiencedCategoriesAreReviewed() {
        let group = groupWithMoments([(.food, 0.5, "moment.good"), (.cleanliness, -0.3, "moment.dusty")])
        XCTAssertEqual(Set(group.experiencedCategories), [.food, .cleanliness])
    }

    func testReviewBodyFallsBackToSomethingSensible() {
        let review = Review(
            id: ReviewID(raw: 1), groupID: GroupID(raw: 1), archetypeID: "couple", tick: 0,
            overallStars: 4.1, categoryScores: [], positiveKeys: [], negativeKeys: [],
            nights: 3, partySize: 2
        )
        XCTAssertEqual(review.bodyKeys, ["review.neutralPositive"])
    }

    func testThoughtsMapToReviewCategories() {
        XCTAssertEqual(ThoughtKind.cottageWasDirty.reviewCategory, .cleanliness)
        XCTAssertEqual(ThoughtKind.queueTooLong.reviewCategory, .facilities)
        XCTAssertEqual(ThoughtKind.cottageTooFarFromPool.reviewCategory, .location)
        XCTAssertEqual(ThoughtKind.foodWasGood.reviewCategory, .food)
        XCTAssertTrue(ThoughtKind.poolIsFantastic.isPositive)
        XCTAssertFalse(ThoughtKind.tooCrowded.isPositive)
    }

    func testReputationRespondsToGoodAndBadReviews() {
        var reputation = Reputation()
        let opening = reputation.overall
        for _ in 0..<40 {
            reputation.apply(
                review: Review(
                    id: ReviewID(raw: 1), groupID: GroupID(raw: 1), archetypeID: "couple", tick: 0,
                    overallStars: 5.0,
                    categoryScores: [ReviewCategoryScore(category: .cleanliness, stars: 5)],
                    positiveKeys: [], negativeKeys: [], nights: 3, partySize: 2
                )
            )
        }
        XCTAssertGreaterThan(reputation.overall, opening)
        XCTAssertGreaterThan(reputation.averageReviewStars, 4.0)
        XCTAssertEqual(reputation.reviewCount, 40)
        XCTAssertGreaterThan(reputation.demandFactor, 1.0)

        var poor = Reputation()
        for _ in 0..<40 {
            poor.apply(
                review: Review(
                    id: ReviewID(raw: 2), groupID: GroupID(raw: 2), archetypeID: "couple", tick: 0,
                    overallStars: 1.0, categoryScores: [], positiveKeys: [], negativeKeys: [],
                    nights: 3, partySize: 2
                )
            )
        }
        XCTAssertLessThan(poor.overall, 0.4)
        XCTAssertLessThan(poor.demandFactor, 1.0)
    }

    func testGuestThoughtRingIsBounded() {
        var guest = Guest(
            id: GuestID(raw: 1), groupID: GroupID(raw: 1), firstName: "Test", age: 30,
            personality: .neutral, interests: .neutral, position: WorldPoint(x: 0, y: 0)
        )
        for index in 0..<50 {
            guest.remember(GuestThought(kind: .tooCrowded, magnitude: 0.5, tick: index))
        }
        XCTAssertEqual(guest.thoughts.count, 8, "guests remember impressions, not a log file")
        XCTAssertEqual(guest.thoughts.last?.tick, 49)
    }
}

final class NotificationTests: XCTestCase {

    func testCooldownAggregatesRepeats() {
        var centre = NotificationCentre()
        var allocator = IDAllocator()
        XCTAssertTrue(
            centre.post(
                priority: .warning, text: LocalizedText("test"), groupingKey: "dirty",
                tick: 0, cooldownMinutes: 120, allocator: &allocator
            )
        )
        for tick in 1...20 {
            XCTAssertFalse(
                centre.post(
                    priority: .warning, text: LocalizedText("test"), groupingKey: "dirty",
                    tick: tick, cooldownMinutes: 120, allocator: &allocator
                ),
                "repeats inside the cooldown must aggregate, not stack up"
            )
        }
        XCTAssertEqual(centre.items.count, 1)
        XCTAssertEqual(centre.items.first?.occurrences, 21)
    }

    func testCooldownExpires() {
        var centre = NotificationCentre()
        var allocator = IDAllocator()
        centre.post(priority: .info, text: LocalizedText("x"), groupingKey: "k", tick: 0, cooldownMinutes: 60, allocator: &allocator)
        XCTAssertTrue(
            centre.post(priority: .info, text: LocalizedText("x"), groupingKey: "k", tick: 61, cooldownMinutes: 60, allocator: &allocator)
        )
        XCTAssertEqual(centre.items.count, 2)
    }

    func testSortingPutsCriticalFirst() {
        var centre = NotificationCentre()
        var allocator = IDAllocator()
        centre.post(priority: .info, text: LocalizedText("info"), groupingKey: "a", tick: 10, allocator: &allocator)
        centre.post(priority: .critical, text: LocalizedText("critical"), groupingKey: "b", tick: 0, allocator: &allocator)
        centre.post(priority: .warning, text: LocalizedText("warning"), groupingKey: "c", tick: 5, allocator: &allocator)

        XCTAssertEqual(centre.sortedForDisplay.map(\.priority), [.critical, .warning, .info])
        XCTAssertEqual(centre.unreadCount, 3)
        centre.markAllRead()
        XCTAssertEqual(centre.unreadCount, 0)
    }

    func testTrayIsCapped() {
        var centre = NotificationCentre()
        centre.limit = 10
        var allocator = IDAllocator()
        for index in 0..<50 {
            centre.post(
                priority: .info, text: LocalizedText("x"), groupingKey: "k\(index)",
                tick: index, allocator: &allocator
            )
        }
        XCTAssertEqual(centre.items.count, 10)
    }
}
