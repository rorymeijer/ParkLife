import Foundation

/// Creates the individual people in a booked party.
///
/// Personality and interests are sampled from the group archetype with jitter, so two families
/// behave differently without either being random noise.
public enum GuestFactory {

    public static func populate(
        group groupID: GroupID,
        reservation: Reservation,
        archetype: GroupArchetypeDefinition,
        in world: inout World
    ) {
        guard var group = world.groups[groupID] else { return }
        guard group.memberIDs.isEmpty else { return }

        let spawn = WorldPoint(world.entranceTile)
        var members: [GuestID] = []

        for _ in 0..<reservation.adults {
            let age = world.random.guestSpawn.nextInt(
                in: archetype.adultAgeRange[0]...archetype.adultAgeRange[1]
            )
            let name = world.random.guestSpawn.pick(world.catalog.names.adultNames) ?? "Guest"
            members.append(makeGuest(name: name, age: age, groupID: groupID, archetype: archetype, spawn: spawn, world: &world))
        }
        for _ in 0..<reservation.children {
            let age = world.random.guestSpawn.nextInt(
                in: archetype.childAgeRange[0]...archetype.childAgeRange[1]
            )
            let name = world.random.guestSpawn.pick(world.catalog.names.childNames) ?? "Guest"
            members.append(makeGuest(name: name, age: age, groupID: groupID, archetype: archetype, spawn: spawn, world: &world))
        }

        group.memberIDs = members
        world.groups.insert(group)
        for id in members {
            if let guest = world.guests[id] {
                world.index.noteGuest(guest)
            }
        }
    }

    private static func makeGuest(
        name: String,
        age: Int,
        groupID: GroupID,
        archetype: GroupArchetypeDefinition,
        spawn: WorldPoint,
        world: inout World
    ) -> GuestID {
        let id = world.ids.next(GuestID.self)
        let personality = Personality(
            sociability: jitter(0.5, world: &world),
            adventurousness: jitter(0.5, world: &world),
            patience: jitter(0.5, world: &world),
            frugality: jitter(0.5, world: &world),
            tidiness: jitter(0.5, world: &world),
            activityLevel: jitter(age < 16 ? 0.72 : (age > 64 ? 0.38 : 0.55), world: &world)
        )
        var interests = Interests.neutral
        for kind in InterestKind.allCases {
            let bias = archetype.interestBias[kind.rawValue] ?? 0.5
            interests[kind] = jitter(bias, world: &world)
        }
        // Children are drawn to water and play regardless of the family average.
        if age < 13 {
            interests.swimming = clamp01(interests.swimming + 0.15)
            interests.entertainment = clamp01(interests.entertainment + 0.15)
        }

        var guest = Guest(
            id: id,
            groupID: groupID,
            firstName: name,
            age: age,
            personality: personality,
            interests: interests,
            position: spawn
        )
        // Arriving after a journey: peckish, a bit tired, ready for something to do.
        guest.needs.hunger = world.random.guestSpawn.nextDouble(in: 0.25...0.55)
        guest.needs.thirst = world.random.guestSpawn.nextDouble(in: 0.30...0.60)
        guest.needs.tiredness = world.random.guestSpawn.nextDouble(in: 0.20...0.45)
        guest.needs.boredom = world.random.guestSpawn.nextDouble(in: 0.15...0.40)
        world.guests.insert(guest)
        return id
    }

    private static func jitter(_ base: Double, world: inout World) -> Double {
        clamp01(world.random.guestSpawn.gaussian(mean: base, standardDeviation: 0.13))
    }
}
