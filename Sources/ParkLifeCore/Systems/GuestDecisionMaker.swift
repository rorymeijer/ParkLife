import Foundation

/// What a guest has decided to do next.
public enum GuestDecision {
    case visit(BuildingID)
    case returnToUnit
    case sleep
    case wander
    case leavePark
    case doNothing
}

/// Utility scoring for guest choices.
///
/// Every term is a measured quantity: real network distance, live queue length, actual price
/// against the group's remaining budget, current weather. There is no "pick a random facility"
/// branch anywhere in here.
public enum GuestDecisionMaker {

    public struct ScoredOption {
        public let building: BuildingID
        public let score: Double
        public let distanceTiles: Int
        public let price: Money
    }

    public static func decide(
        guestID: GuestID,
        world: World,
        context: TickContext
    ) -> GuestDecision {
        guard let guest = world.guests[guestID], let group = world.groups[guest.groupID] else {
            return .doNothing
        }

        // Departure day beats everything else: once the party is awake on the day they leave,
        // they head back to pack. Without this a tired guest could go to bed on checkout morning
        // and sleep straight through their own departure.
        if context.date.dayIndex >= group.departureDate.dayIndex,
           context.date.minuteOfDay >= context.tuning.wakeMinute {
            return .returnToUnit
        }

        let minuteOfDay = context.date.minuteOfDay
        let isLate = minuteOfDay >= context.tuning.bedtimeEarliestMinute || minuteOfDay < context.tuning.wakeMinute
        if isLate && guest.needs.tiredness > 0.45 {
            return .sleep
        }
        if guest.needs.tiredness > context.tuning.tirednessSeek {
            return .sleep
        }

        let options = scoreOptions(guest: guest, group: group, world: world, context: context)
        guard let best = options.first, best.score > 0.12 else {
            // Nothing worth doing: rest at the cottage if tired-ish, otherwise stroll.
            return guest.needs.tiredness > 0.5 ? .returnToUnit : .wander
        }
        return .visit(best.building)
    }

    /// All open, reachable facilities scored for this guest, best first.
    public static func scoreOptions(
        guest: Guest,
        group: GuestGroup,
        world: World,
        context: TickContext
    ) -> [ScoredOption] {
        var scored: [ScoredOption] = []
        let origin = guest.tile

        for id in world.index.facilityIDs {
            guard let instance = world.buildings[id],
                  let definition = world.definition(of: instance),
                  let facility = definition.facility,
                  let state = instance.facility else { continue }
            switch facility.kind {
            case .entrance, .reception: continue
            default: break
            }
            guard world.isOperational(id) else { continue }

            // Reachability first: an unreachable option costs one integer comparison to reject.
            guard let distanceTiles = world.navigation.tileDistance(from: origin, to: id) else { continue }
            guard distanceTiles <= context.tuning.maximumComfortableWalkTiles else { continue }

            let price = world.pricing.facilityPrice(definition: definition, instance: instance)
            let needMatch = needMatchScore(guest: guest, facility: facility, tuning: context.tuning)
            guard needMatch > 0.01 || facility.relief.isEmpty else { continue }

            let interest = guest.interests.affinity(for: facility.interests)
            let crowding = Double(state.occupants.count + state.queue.count)
                / Double(max(1, facility.capacity + facility.queueCapacity))
            let appeal = facility.appeal
                * instance.condition
                * (0.75 + 0.25 * state.cleanliness)
                * (1.0 - 0.55 * clamp01(crowding))
            let weatherFit = facility.isIndoor
                ? world.weather.condition.indoorAppealMultiplier
                : world.weather.condition.outdoorAppealMultiplier
            let proximity = 1.0 - 0.75 * clamp01(Double(distanceTiles) / Double(context.tuning.maximumComfortableWalkTiles))
            let affordability = affordabilityScore(price: price, group: group, guest: guest)
            let childFit = guest.ageBand == .child ? (0.35 + 0.65 * facility.childSuitability) : 1.0

            // A facility with a full queue is not worth walking to.
            guard state.queue.count < facility.queueCapacity else { continue }

            let score = (0.15 + needMatch) * (0.35 + 0.65 * interest) * appeal
                * weatherFit * proximity * affordability * childFit

            scored.append(ScoredOption(building: id, score: score, distanceTiles: distanceTiles, price: price))
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.building.raw < rhs.building.raw
        }
        return scored
    }

    /// How strongly this facility answers what the guest currently needs.
    ///
    /// Quadratic above the seek threshold, so an urgent need dominates instead of merely nudging.
    private static func needMatchScore(guest: Guest, facility: FacilityDefinition, tuning: SimulationTuning) -> Double {
        var total = 0.0
        for kind in NeedKind.allCases {
            let relief = facility.reliefAmount(for: kind)
            guard relief > 0 else { continue }
            let pressure = guest.needs[kind]
            let threshold = seekThreshold(for: kind, tuning: tuning)
            guard pressure > threshold * 0.55 else { continue }
            let excess = clamp01((pressure - threshold * 0.55) / max(0.05, 1.0 - threshold * 0.55))
            total += relief * excess * excess * 2.4
        }
        return total
    }

    private static func seekThreshold(for kind: NeedKind, tuning: SimulationTuning) -> Double {
        switch kind {
        case .hunger: return tuning.hungerSeek
        case .thirst: return tuning.thirstSeek
        case .tiredness: return tuning.tirednessSeek
        case .boredom: return tuning.boredomSeek
        case .bladder: return tuning.bladderSeek
        }
    }

    /// Free is always affordable; beyond that it is judged against what the party has left and how
    /// careful with money this particular person is.
    private static func affordabilityScore(price: Money, group: GuestGroup, guest: Guest) -> Double {
        guard price.cents > 0 else { return 1.0 }
        let remaining = group.remainingBudget
        guard remaining.cents > 0 else { return 0.05 }
        let share = Double(price.cents) / Double(remaining.cents)
        let tolerance = 0.28 * (1.35 - 0.7 * guest.personality.frugality)
        guard share > tolerance else { return 1.0 }
        return clamp(tolerance / share, 0.05, 1.0)
    }
}
