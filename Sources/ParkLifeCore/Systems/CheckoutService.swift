import Foundation

/// Checkout, departure and handing the cottage back to housekeeping.
public enum CheckoutService {

    /// A guest has finished packing.
    public static func checkOut(guestID: GuestID, world: inout World, context: inout TickContext) {
        walkToExit(guestID: guestID, world: &world)
    }

    public static func walkToExit(guestID: GuestID, world: inout World) {
        guard let guest = world.guests[guestID] else { return }
        let exitTiles = world.parkEntranceTiles
        let goals = exitTiles.isEmpty ? [world.entranceTile] : exitTiles
        if let tiles = world.navigation.immediatePath(from: guest.tile, toAnyOf: goals) {
            world.guests.modify(guestID) { stored in
                stored.activity = .walkingToExit
                stored.detail = .reduced
                stored.path = MovementPath(tiles: tiles)
            }
        } else {
            // No route out: the guest is counted as departed rather than being stranded forever.
            world.guests.modify(guestID) { stored in
                stored.activity = .departed
                stored.detail = .dormant
                stored.path = nil
            }
            world.guestsOnSite = max(0, world.guestsOnSite - 1)
        }
    }

    /// Finalises a stay once every member of the party has left the park.
    public static func finaliseIfComplete(
        groupID: GroupID,
        world: inout World,
        context: inout TickContext
    ) {
        guard let group = world.groups[groupID], group.state == .checkedIn else { return }
        guard !group.memberIDs.isEmpty else { return }
        let allGone = group.memberIDs.allSatisfy { world.guests[$0]?.activity == .departed }
        guard allGone else { return }

        world.groups.modify(groupID) { $0.state = .checkedOut }
        if let reservationID = group.reservationID {
            world.reservations.modify(reservationID) { $0.status = .checkedOut }
        }

        if let unit = group.unitBuildingID {
            releaseUnit(unit, nights: group.arrivalDate.nights(until: group.departureDate), world: &world, context: &context)
        }
        world.bookkeeping.departuresToday += 1
        world.deactivate(group: groupID)
        context.emit(.groupCheckedOut(groupID))

        // Guests are removed from the world; their stay now lives on as a review and as statistics.
        for memberID in group.memberIDs {
            QueueService.leaveAllFacilities(guestID: memberID, world: &world)
            world.guests.remove(memberID)
        }
        world.index.rebuildGuests(world.guests)
    }

    /// The cottage becomes dirty and needs housekeeping before anyone else can check in.
    private static func releaseUnit(
        _ unit: BuildingID,
        nights: Int,
        world: inout World,
        context: inout TickContext
    ) {
        world.buildings.modify(unit) { building in
            building.accommodation?.state = .dirty
            building.accommodation?.currentReservationID = nil
            let loss = context.tuning.cleanlinessLossPerNight * Double(max(1, nights))
            let current = building.accommodation?.cleanliness ?? 1.0
            building.accommodation?.cleanliness = clamp01(current - loss)
        }
        context.emit(.unitNeedsCleaning(unit))
        StaffSystem.createCleaningTask(for: unit, world: &world, context: &context)
    }
}
