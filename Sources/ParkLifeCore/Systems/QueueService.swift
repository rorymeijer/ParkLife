import Foundation

/// Queue handling shared by every facility, including reception.
public enum QueueService {

    /// Puts a guest in a facility's queue and sets the activity to match, or turns them away.
    ///
    /// This owns *both* halves of the queueing state — membership of the queue and the guest's
    /// activity — because they have to agree. When the caller set `.queueing` itself, a guest who
    /// was turned away ended up marked as queueing at a facility they were not queueing at, and
    /// nothing could ever rescue them: admission only looks at the queue, impatience only scans
    /// the queue, and the AI only reconsiders idle guests. They stood at the door for the rest of
    /// the holiday.
    ///
    /// Returns `true` if the guest actually joined.
    @discardableResult
    public static func joinQueue(
        guestID: GuestID,
        buildingID: BuildingID,
        world: inout World,
        context: inout TickContext
    ) -> Bool {
        guard let instance = world.buildings[buildingID],
              let definition = world.definition(of: instance),
              let facility = definition.facility else {
            turnAway(guestID: guestID, world: &world, tick: context.tick)
            return false
        }

        let queueLength = instance.facility?.queue.count ?? 0
        guard queueLength < facility.queueCapacity, world.isOperational(buildingID) else {
            // Turned away: a measured disappointment, not a random grumble.
            SatisfactionService.recordThought(
                guestID: guestID,
                kind: .queueTooLong,
                magnitude: 0.8,
                delta: -0.12,
                world: &world,
                tick: context.tick,
                subject: buildingID.raw
            )
            context.emit(.guestThought(guestID, .queueTooLong))
            turnAway(guestID: guestID, world: &world, tick: context.tick)
            return false
        }

        let isReception = world.index.receptionID == buildingID
        world.buildings.modify(buildingID) { building in
            building.facility?.queue.append(guestID)
        }
        world.guests.modify(guestID) { guest in
            guest.activity = isReception ? .queueingAtReception : .queueing(buildingID)
            guest.queueJoinedTick = context.tick
            guest.detail = .dormant
            guest.path = nil
        }
        return true
    }

    /// Puts a guest back into circulation after a refused join.
    private static func turnAway(guestID: GuestID, world: inout World, tick: Tick) {
        world.guests.modify(guestID) { guest in
            guest.activity = .idle
            guest.detail = .reduced
            guest.path = nil
            guest.decisionCooldownUntilTick = tick + 20
        }
    }

    public static func leaveQueue(guestID: GuestID, buildingID: BuildingID, world: inout World) {
        world.buildings.modify(buildingID) { building in
            building.facility?.queue.removeAll(where: { $0 == guestID })
        }
    }

    /// Removes a guest from a facility entirely — both the queue and the guests being served.
    ///
    /// Needed because a party can be pulled out of reception mid-service when another member
    /// completes check-in; without this the abandoned guest would occupy a service slot forever.
    public static func leaveFacility(guestID: GuestID, buildingID: BuildingID, world: inout World) {
        world.buildings.modify(buildingID) { building in
            building.facility?.queue.removeAll(where: { $0 == guestID })
            building.facility?.occupants.removeAll(where: { $0 == guestID })
        }
    }

    /// Removes a guest from every facility in the park. Used when a guest leaves the world.
    public static func leaveAllFacilities(guestID: GuestID, world: inout World) {
        for buildingID in world.index.facilityIDs {
            leaveFacility(guestID: guestID, buildingID: buildingID, world: &world)
        }
    }

    /// How long a guest is prepared to wait, in minutes.
    public static func patienceMinutes(for guest: Guest) -> Int {
        Int(12.0 + 26.0 * guest.personality.patience)
    }
}
