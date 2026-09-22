import Foundation

/// Needs, wake-ups and the guest state machine.
///
/// Only guests who are actually awake and idle do work here. Sleeping guests, guests inside a
/// facility and guests unpacking are dormant: their needs are advanced in one step when they wake
/// (`lastNeedsTick`), which makes level of detail exact rather than approximate.
public enum GuestAISystem: SimulationSystem {

    public static let systemName = "GuestAI"

    public static func update(world: inout World, context: inout TickContext) {
        wakeScheduledGuests(world: &world, context: &context)

        for guestID in world.guests.sortedIDs {
            guard let guest = world.guests[guestID] else { continue }
            guard guest.detail != .dormant else { continue }
            guard guest.activity != .offPark, guest.activity != .departed else { continue }

            advanceNeeds(guestID: guestID, world: &world, context: context)
            updateHappiness(guestID: guestID, world: &world, context: context)

            if case .idle = world.guests[guestID]?.activity {
                considerDecision(guestID: guestID, world: &world, context: &context)
            }
        }
    }

    // MARK: - Wake-ups

    private static func wakeScheduledGuests(world: inout World, context: inout TickContext) {
        for event in context.dueEvents(ofKind: .guestWake) {
            let guestID = GuestID(raw: event.entity)
            guard let guest = world.guests[guestID] else { continue }
            advanceNeeds(guestID: guestID, world: &world, context: context)

            switch guest.activity {
            case .unpacking:
                setIdle(guestID, world: &world)
            case .sleeping:
                world.guests.modify(guestID) { stored in
                    stored.needs.tiredness = max(0, stored.needs.tiredness - 0.9)
                    stored.comfort = clamp01(stored.comfort + 0.1)
                }
                setIdle(guestID, world: &world)
            case .packing:
                CheckoutService.checkOut(guestID: guestID, world: &world, context: &context)
            case .checkingIn:
                setIdle(guestID, world: &world)
            default:
                setIdle(guestID, world: &world)
            }
        }
    }

    private static func setIdle(_ guestID: GuestID, world: inout World) {
        world.guests.modify(guestID) { guest in
            guest.activity = .idle
            guest.detail = .reduced
            guest.path = nil
        }
    }

    // MARK: - Needs

    /// Advances needs by however much time has passed since they were last touched.
    public static func advanceNeeds(guestID: GuestID, world: inout World, context: TickContext) {
        world.guests.modify(guestID) { guest in
            let elapsed = context.tick - guest.lastNeedsTick
            guard elapsed > 0 else { return }
            guest.lastNeedsTick = context.tick
            let hours = Double(elapsed) / 60.0
            let activityScale = 0.75 + 0.5 * guest.personality.activityLevel
            let tuning = context.tuning

            if case .sleeping = guest.activity {
                guest.needs.tiredness -= tuning.tirednessRecoveryPerHour * hours
                guest.needs.hunger += tuning.hungerPerHour * hours * 0.35
                guest.needs.thirst += tuning.thirstPerHour * hours * 0.35
                guest.needs.bladder += tuning.bladderPerHour * hours * 0.4
            } else {
                guest.needs.hunger += tuning.hungerPerHour * hours * activityScale
                guest.needs.thirst += tuning.thirstPerHour * hours * activityScale
                guest.needs.tiredness += tuning.tirednessPerHour * hours * activityScale
                guest.needs.boredom += tuning.boredomPerHour * hours
                guest.needs.bladder += tuning.bladderPerHour * hours
            }
        }
    }

    /// Happiness follows comfort, needs and the surroundings the guest can actually see.
    private static func updateHappiness(guestID: GuestID, world: inout World, context: TickContext) {
        guard context.tick % 10 == 0 else { return }
        let scenery = world.guests[guestID].map { world.tiles.averageScenery(around: $0.tile, radius: 3) } ?? 0
        let weatherComfort = world.weather.comfortIndex
        world.guests.modify(guestID) { guest in
            let needPenalty = guest.needs.averagePressure
            let target = clamp01(
                0.55
                    + 0.28 * (1.0 - needPenalty * 1.4)
                    + 0.14 * scenery
                    + 0.10 * (weatherComfort - 0.5)
                    + 0.08 * (guest.comfort - 0.5)
                    - 0.25 * guest.congestionExposure
            )
            guest.happiness = movingAverage(current: guest.happiness, sample: target, weight: 0.08)
        }
    }

    // MARK: - Decisions

    private static func considerDecision(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID] else { return }
        guard context.tick >= guest.decisionCooldownUntilTick else { return }
        guard context.tick - guest.lastDecisionTick >= context.tuning.decisionIntervalMinutes else { return }
        world.guests.modify(guestID) { $0.lastDecisionTick = context.tick }

        let decision = GuestDecisionMaker.decide(guestID: guestID, world: world, context: context)
        switch decision {
        case .visit(let buildingID):
            startVisit(guestID: guestID, buildingID: buildingID, world: &world, context: &context)

        case .returnToUnit:
            startWalkToUnit(guestID: guestID, world: &world, context: &context)

        case .sleep:
            startSleep(guestID: guestID, world: &world, context: &context)

        case .wander:
            wander(guestID: guestID, world: &world, context: context)

        case .leavePark:
            CheckoutService.walkToExit(guestID: guestID, world: &world)

        case .doNothing:
            world.guests.modify(guestID) {
                $0.decisionCooldownUntilTick = context.tick + context.tuning.failedDecisionCooldownMinutes
            }
        }
    }

    private static func startVisit(
        guestID: GuestID,
        buildingID: BuildingID,
        world: inout World,
        context: inout TickContext
    ) {
        guard let guest = world.guests[guestID] else { return }
        guard let field = world.navigation.field(for: buildingID),
              let tiles = field.path(from: guest.tile) else {
            noteUnreachable(guestID: guestID, world: &world, context: &context)
            return
        }
        world.guests.modify(guestID) { stored in
            stored.activity = .walkingTo(buildingID)
            stored.detail = .reduced
            stored.path = MovementPath(tiles: tiles)
        }
    }

    private static func startWalkToUnit(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID],
              let group = world.groups[guest.groupID],
              let unit = group.unitBuildingID else {
            noteUnreachable(guestID: guestID, world: &world, context: &context)
            return
        }
        let goals = world.accessTiles(for: unit)
        guard !goals.isEmpty else {
            noteUnreachable(guestID: guestID, world: &world, context: &context)
            return
        }
        // A cottage is a private destination, so it goes through the budgeted A* queue rather
        // than getting a flow field of its own.
        if let tiles = world.navigation.immediatePath(from: guest.tile, toAnyOf: goals) {
            world.guests.modify(guestID) { stored in
                stored.activity = .walkingToUnit
                stored.detail = .reduced
                stored.path = MovementPath(tiles: tiles)
            }
        } else {
            noteUnreachable(guestID: guestID, world: &world, context: &context)
        }
    }

    private static func startSleep(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID],
              let group = world.groups[guest.groupID],
              let unit = group.unitBuildingID else {
            world.guests.modify(guestID) {
                $0.decisionCooldownUntilTick = context.tick + context.tuning.failedDecisionCooldownMinutes
            }
            return
        }
        // Must actually be at the cottage to go to bed.
        let atUnit = world.buildings[unit].flatMap { instance -> Bool? in
            guard let definition = world.definition(of: instance) else { return nil }
            return instance.footprintRect(definition: definition).expanded(by: 1).contains(guest.tile)
        } ?? false

        guard atUnit else {
            startWalkToUnit(guestID: guestID, world: &world, context: &context)
            return
        }

        let wakeMinute = context.tuning.wakeMinute
        let today = context.date.startOfDay
        var wake = today.adding(minutes: wakeMinute)
        if wake.minutesSinceEpoch <= context.tick {
            wake = today.adding(days: 1).adding(minutes: wakeMinute)
        }
        let minimum = context.tick + context.tuning.sleepMinutesMinimum
        world.sleep(guest: guestID, untilTick: max(wake.minutesSinceEpoch, minimum), activity: .sleeping)
    }

    /// A short stroll: still movement, still uses real paths, but no destination.
    private static func wander(guestID: GuestID, world: inout World, context: TickContext) {
        guard let guest = world.guests[guestID] else { return }
        let neighbours = world.navigation.network.walkableNeighbours(of: guest.tile)
        guard !neighbours.isEmpty else {
            world.guests.modify(guestID) {
                $0.decisionCooldownUntilTick = context.tick + context.tuning.failedDecisionCooldownMinutes
            }
            return
        }
        let index = Int(world.random.guestBehaviour.next() % UInt64(neighbours.count))
        world.guests.modify(guestID) { stored in
            stored.path = MovementPath(tiles: [stored.tile, neighbours[index]])
            stored.detail = .reduced
        }
    }

    private static func noteUnreachable(guestID: GuestID, world: inout World, context: inout TickContext) {
        world.guests.modify(guestID) { guest in
            guest.decisionCooldownUntilTick = context.tick + context.tuning.failedDecisionCooldownMinutes
            guest.remember(GuestThought(kind: .cantReachDestination, magnitude: 0.7, tick: context.tick))
        }
        if let guest = world.guests[guestID] {
            SatisfactionService.record(
                groupID: guest.groupID,
                category: .location,
                delta: -0.10,
                reasonKey: ThoughtKind.cantReachDestination.localizationKey,
                world: &world,
                tick: context.tick
            )
        }
        context.emit(.guestThought(guestID, .cantReachDestination))
    }
}
