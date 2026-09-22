import Foundation

/// Queues, service, payment and the satisfaction that comes out of a facility visit.
public enum FacilitySystem: SimulationSystem {

    public static let systemName = "Facilities"

    public static func update(world: inout World, context: inout TickContext) {
        completeServices(world: &world, context: &context)

        for buildingID in world.index.facilityIDs {
            guard let instance = world.buildings[buildingID],
                  let definition = world.definition(of: instance),
                  let facility = definition.facility else { continue }

            handleImpatience(buildingID: buildingID, facility: facility, world: &world, context: &context)

            guard world.isOperational(buildingID) else { continue }
            admitFromQueue(
                buildingID: buildingID,
                definition: definition,
                facility: facility,
                world: &world,
                context: &context
            )
        }
    }

    // MARK: - Admission

    private static func admitFromQueue(
        buildingID: BuildingID,
        definition: BuildingDefinition,
        facility: FacilityDefinition,
        world: inout World,
        context: inout TickContext
    ) {
        while true {
            guard let state = world.buildings[buildingID]?.facility else { return }
            guard state.occupants.count < facility.capacity, let next = state.queue.first else { return }
            guard let guest = world.guests[next] else {
                world.buildings.modify(buildingID) { $0.facility?.queue.removeFirst() }
                continue
            }

            let waited = context.tick - guest.queueJoinedTick
            world.buildings.modify(buildingID) { building in
                building.facility?.queue.removeFirst()
                building.facility?.occupants.append(next)
                building.facility?.visitsToday += 1
                building.facility?.lifetimeVisits += 1
                let previous = building.facility?.averageWaitMinutes ?? 0
                building.facility?.averageWaitMinutes = movingAverage(
                    current: previous, sample: Double(waited), weight: 0.15
                )
            }

            let duration = serviceDuration(facility: facility, world: &world)
            world.guests.modify(next) { stored in
                stored.activity = .using(buildingID)
                stored.detail = .dormant
            }
            world.schedule.schedule(.facilityServiceComplete, entity: next.raw, at: context.tick + duration)
            context.emit(.facilityVisited(buildingID))
        }
    }

    private static func serviceDuration(facility: FacilityDefinition, world: inout World) -> Int {
        guard facility.maximumServiceMinutes > facility.minimumServiceMinutes else {
            return max(1, facility.minimumServiceMinutes)
        }
        return world.random.guestBehaviour.nextInt(
            in: facility.minimumServiceMinutes...facility.maximumServiceMinutes
        )
    }

    // MARK: - Impatience

    /// Guests who have queued past their patience give up — and remember it.
    private static func handleImpatience(
        buildingID: BuildingID,
        facility: FacilityDefinition,
        world: inout World,
        context: inout TickContext
    ) {
        guard let queue = world.buildings[buildingID]?.facility?.queue, !queue.isEmpty else { return }
        var leavers: [GuestID] = []
        for guestID in queue {
            guard let guest = world.guests[guestID] else {
                leavers.append(guestID)
                continue
            }
            let waited = context.tick - guest.queueJoinedTick
            if waited > QueueService.patienceMinutes(for: guest) {
                leavers.append(guestID)
            }
        }
        guard !leavers.isEmpty else { return }
        for guestID in leavers {
            QueueService.leaveQueue(guestID: guestID, buildingID: buildingID, world: &world)
            guard world.guests[guestID] != nil else { continue }
            world.guests.modify(guestID) { guest in
                guest.activity = .idle
                guest.detail = .reduced
                guest.decisionCooldownUntilTick = context.tick + 25
            }
            let isReception = world.index.receptionID == buildingID
            SatisfactionService.recordThought(
                guestID: guestID,
                kind: isReception ? .longWaitAtReception : .queueTooLong,
                magnitude: 0.85,
                delta: isReception ? -0.22 : -0.14,
                world: &world,
                tick: context.tick,
                subject: buildingID.raw
            )
            context.emit(.guestThought(guestID, isReception ? .longWaitAtReception : .queueTooLong))
        }
    }

    // MARK: - Completion

    private static func completeServices(world: inout World, context: inout TickContext) {
        for event in context.dueEvents(ofKind: .facilityServiceComplete) {
            let guestID = GuestID(raw: event.entity)
            guard let guest = world.guests[guestID] else { continue }
            guard case .using(let buildingID) = guest.activity else { continue }

            world.buildings.modify(buildingID) { building in
                building.facility?.occupants.removeAll(where: { $0 == guestID })
            }

            guard let instance = world.buildings[buildingID],
                  let definition = world.definition(of: instance),
                  let facility = definition.facility else {
                world.guests.modify(guestID) { $0.activity = .idle; $0.detail = .reduced }
                continue
            }

            if facility.kind == .reception {
                CheckInService.checkIn(guestID: guestID, world: &world, context: &context)
                continue
            }

            applyVisitOutcome(
                guestID: guestID,
                buildingID: buildingID,
                definition: definition,
                facility: facility,
                world: &world,
                context: &context
            )
        }
    }

    private static func applyVisitOutcome(
        guestID: GuestID,
        buildingID: BuildingID,
        definition: BuildingDefinition,
        facility: FacilityDefinition,
        world: inout World,
        context: inout TickContext
    ) {
        guard let guest = world.guests[guestID], let instance = world.buildings[buildingID] else { return }
        let price = world.pricing.facilityPrice(definition: definition, instance: instance)
        let quality = clamp01(
            facility.appeal * instance.condition * (0.75 + 0.25 * (instance.facility?.cleanliness ?? 1.0))
        )

        // Payment comes out of the group's holiday budget, in whole cents.
        var paid = Money.zero
        if price.cents > 0, let group = world.groups[guest.groupID], group.canAfford(price) {
            paid = price
            world.groups.modify(guest.groupID) { $0.spent += price }
            world.guests.modify(guestID) { $0.moneySpent += price }
            world.earn(price, category: facility.kind.revenueCategory, reference: buildingID.raw)
            let variableCost = price.scaled(by: facility.variableCostFraction)
            if variableCost.cents > 0 {
                world.spend(variableCost, category: expenseCategory(for: facility.kind), reference: buildingID.raw)
            }
            world.buildings.modify(buildingID) { building in
                building.facility?.revenueToday += price
                building.facility?.lifetimeRevenue += price
            }
            context.emit(.guestSpent(guestID, price, facility.kind.revenueCategory))
        }

        // Needs relief.
        world.guests.modify(guestID) { stored in
            for relief in facility.relief {
                stored.needs[relief.need] = stored.needs[relief.need] - relief.amount * (0.7 + 0.3 * quality)
            }
            stored.comfort = clamp01(stored.comfort + 0.05 * quality)
            stored.activity = .idle
            stored.detail = .reduced
            stored.decisionCooldownUntilTick = context.tick + 5
        }
        world.buildings.modify(buildingID) { building in
            // Use wears a place down a little.
            let current = building.facility?.cleanliness ?? 1.0
            building.facility?.cleanliness = clamp01(current - 0.004)
        }

        recordVisitSatisfaction(
            guestID: guestID,
            buildingID: buildingID,
            facility: facility,
            quality: quality,
            paid: paid,
            world: &world,
            context: &context
        )
    }

    private static func recordVisitSatisfaction(
        guestID: GuestID,
        buildingID: BuildingID,
        facility: FacilityDefinition,
        quality: Double,
        paid: Money,
        world: inout World,
        context: inout TickContext
    ) {
        guard let guest = world.guests[guestID], let group = world.groups[guest.groupID] else { return }
        let category: ReviewCategory
        switch facility.kind {
        case .restaurant, .snackBar, .cafe: category = .food
        case .supermarket, .shop: category = .facilities
        case .pool, .playground, .activity: category = .activities
        default: category = .facilities
        }

        // Quality measured against what this group expected to get.
        let delta = clamp((quality - group.expectation) * 0.9, -0.5, 0.5)
        SatisfactionService.record(
            groupID: guest.groupID,
            category: category,
            delta: delta,
            reasonKey: "moment.facilityVisit",
            world: &world,
            tick: context.tick
        )

        if facility.kind == .pool, quality > 0.72 {
            SatisfactionService.recordThought(
                guestID: guestID, kind: .poolIsFantastic, magnitude: quality,
                delta: 0.22, world: &world, tick: context.tick, subject: buildingID.raw
            )
            context.emit(.guestThought(guestID, .poolIsFantastic))
        }
        if category == .food {
            let kind: ThoughtKind = quality >= group.expectation ? .foodWasGood : .foodWasDisappointing
            SatisfactionService.recordThought(
                guestID: guestID, kind: kind, magnitude: abs(quality - group.expectation) + 0.3,
                delta: kind == .foodWasGood ? 0.14 : -0.16,
                world: &world, tick: context.tick, subject: buildingID.raw
            )
        }

        // Value judgement: price against what they felt they got.
        if paid.cents > 0 {
            let perceivedWorth = Double(paid.cents) * (0.6 + 0.8 * quality)
            let ratio = perceivedWorth / Double(paid.cents)
            if ratio < 0.95 - 0.25 * guest.personality.frugality {
                SatisfactionService.recordThought(
                    guestID: guestID, kind: .expensive, magnitude: 0.6,
                    delta: -0.13, world: &world, tick: context.tick, subject: buildingID.raw
                )
            } else if ratio > 1.15 {
                SatisfactionService.recordThought(
                    guestID: guestID, kind: .goodValue, magnitude: 0.6,
                    delta: 0.10, world: &world, tick: context.tick, subject: buildingID.raw
                )
            }
        }
    }

    private static func expenseCategory(for kind: FacilityKind) -> ExpenseCategory {
        switch kind {
        case .restaurant, .snackBar, .cafe: return .ingredients
        case .supermarket, .shop: return .inventory
        default: return .maintenance
        }
    }
}
