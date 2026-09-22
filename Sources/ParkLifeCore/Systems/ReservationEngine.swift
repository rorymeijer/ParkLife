import Foundation

/// Availability, pricing and booking creation.
///
/// This is the **only** code path that creates a reservation, and availability is an interval
/// check against that unit's existing bookings. That is what makes double-booking impossible
/// rather than merely unlikely.
public enum ReservationEngine {

    /// Effective quality of a unit right now, `0...1`.
    public static func quality(of id: BuildingID, in world: World) -> Double {
        guard let instance = world.buildings[id],
              let definition = world.definition(of: instance),
              let accommodation = definition.accommodation else { return 0 }
        let cleanliness = instance.accommodation?.cleanliness ?? 1.0
        let scenery = world.tiles.averageScenery(around: instance.origin, radius: 4)
        let base = accommodation.baseQuality
        return clamp01(
            base
                * (0.65 + 0.35 * instance.condition)
                * (0.78 + 0.22 * cleanliness)
                + scenery * 0.10
        )
    }

    /// Is the unit free for the whole requested stay?
    public static func isAvailable(
        unit: BuildingID,
        arrival: GameDate,
        departure: GameDate,
        in world: World
    ) -> Bool {
        guard let instance = world.buildings[unit], instance.accommodation != nil else { return false }
        guard let state = instance.accommodation, state.state != .maintenance else { return false }
        for reservationID in world.index.reservations(forUnit: unit) {
            guard let reservation = world.reservations[reservationID], reservation.status.holdsUnit else { continue }
            if reservation.overlaps(arrival: arrival, departure: departure) {
                return false
            }
        }
        return true
    }

    /// Units that can host a party of `partySize` over the requested dates, in stable id order.
    public static func availableUnits(
        partySize: Int,
        preferredTiers: [AccommodationTier],
        arrival: GameDate,
        departure: GameDate,
        in world: World
    ) -> [BuildingID] {
        var result: [BuildingID] = []
        for id in world.index.accommodationIDs {
            guard let instance = world.buildings[id],
                  let definition = world.definition(of: instance),
                  let accommodation = definition.accommodation else { continue }
            guard accommodation.capacity >= partySize else { continue }
            guard preferredTiers.isEmpty || preferredTiers.contains(accommodation.tier) else { continue }
            guard isAvailable(unit: id, arrival: arrival, departure: departure, in: world) else { continue }
            result.append(id)
        }
        return result
    }

    /// Total accommodation price for a stay, summing each night at that night's rate.
    public static func stayPrice(
        unit: BuildingID,
        arrival: GameDate,
        departure: GameDate,
        in world: World
    ) -> Money {
        guard let instance = world.buildings[unit],
              let definition = world.definition(of: instance),
              definition.accommodation != nil else { return .zero }
        var total = Money.zero
        let nights = max(1, arrival.nights(until: departure))
        for night in 0..<nights {
            let date = arrival.adding(days: night)
            total += world.pricing.nightlyPrice(definition: definition, instance: instance, date: date)
        }
        return total
    }

    /// How far above or below a group's willingness to pay a price sits, and therefore how likely
    /// they are to book. A high price is fine when quality justifies it (brief §16).
    public static func acceptanceProbability(
        price: Money,
        quality: Double,
        archetype: GroupArchetypeDefinition,
        partySize: Int,
        nights: Int,
        frugality: Double
    ) -> Double {
        let budget = archetype.budgetPerPersonPerNight * (partySize * nights)
        guard budget.cents > 0 else { return 0 }
        // Roughly 55% of the holiday budget goes on the roof over their heads.
        let tolerance = 0.75 + 0.60 * quality
        let acceptable = budget.scaled(by: 0.55 * tolerance * (1.25 - 0.5 * frugality))
        guard price.cents > acceptable.cents else { return 1.0 }
        let ratio = Double(acceptable.cents) / Double(price.cents)
        return clamp01(pow(ratio, 1.8))
    }

    /// Creates a confirmed booking and the group that will travel.
    ///
    /// Returns `nil` when the unit is no longer free — the caller never gets to bypass that check.
    @discardableResult
    public static func book(
        unit: BuildingID,
        archetype: GroupArchetypeDefinition,
        adults: Int,
        children: Int,
        arrival: GameDate,
        departure: GameDate,
        price: Money,
        discount: Money,
        in world: inout World
    ) -> ReservationID? {
        guard isAvailable(unit: unit, arrival: arrival, departure: departure, in: world) else { return nil }
        guard let instance = world.buildings[unit],
              let definition = world.definition(of: instance),
              let accommodation = definition.accommodation,
              accommodation.capacity >= adults + children else { return nil }

        let partySize = adults + children
        let nights = max(1, arrival.nights(until: departure))
        let groupID = world.ids.next(GroupID.self)
        let budget = archetype.budgetPerPersonPerNight * (partySize * nights)

        var group = GuestGroup(
            id: groupID,
            archetypeID: archetype.id,
            memberIDs: [],
            budget: budget,
            arrivalDate: arrival,
            departureDate: departure,
            expectation: expectation(for: accommodation.tier, price: price, budget: budget, world: world),
            reviewWeights: archetype.reviewWeights
        )
        group.unitBuildingID = unit

        let reservationID = world.ids.next(ReservationID.self)
        var reservation = Reservation(
            id: reservationID,
            groupID: groupID,
            unitBuildingID: unit,
            requestedDefinitionID: definition.id,
            arrival: arrival,
            departure: departure,
            adults: adults,
            children: children,
            packageID: "standard",
            price: Money(cents: max(0, price.cents - discount.cents)),
            discount: discount,
            extras: .zero,
            status: .booked,
            bookedAtTick: world.tick
        )
        reservation.status = .booked
        group.reservationID = reservationID

        world.groups.insert(group)
        world.reservations.insert(reservation)
        world.index.noteReservation(reservation)
        return reservationID
    }

    /// How demanding this group will be, `0...1`.
    ///
    /// Paying more, or booking a higher tier, raises the bar they measure the holiday against.
    private static func expectation(
        for tier: AccommodationTier,
        price: Money,
        budget: Money,
        world: World
    ) -> Double {
        let share = budget.cents > 0 ? Double(price.cents) / Double(budget.cents) : 0.5
        let base = 0.45 + 0.35 * clamp01(share / 0.6)
        return clamp01(base * tier.expectationMultiplier * world.difficulty.expectationMultiplier)
    }
}
