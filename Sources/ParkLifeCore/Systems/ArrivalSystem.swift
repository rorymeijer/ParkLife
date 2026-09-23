import Foundation

/// Turns an arriving booking into actual people walking through the gate.
public enum ArrivalSystem: SimulationSystem {

    public static let systemName = "Arrivals"

    public static func update(world: inout World, context: inout TickContext) {
        let today = context.date.dayIndex
        for id in world.reservations.sortedIDs {
            guard let reservation = world.reservations[id] else { continue }
            guard reservation.status == .arriving || reservation.status == .paid else { continue }
            guard reservation.arrival.dayIndex == today else { continue }
            guard context.tick >= reservation.arrival.minutesSinceEpoch else { continue }
            guard let group = world.groups[reservation.groupID], group.memberIDs.isEmpty else { continue }
            guard let archetype = world.catalog.archetypes[group.archetypeID] else { continue }

            world.reservations.modify(id) { $0.status = .arriving }
            world.groups.modify(reservation.groupID) { $0.state = .arriving }

            GuestFactory.populate(
                group: reservation.groupID,
                reservation: reservation,
                archetype: archetype,
                in: &world
            )
            world.activate(group: reservation.groupID)
            sendToReception(groupID: reservation.groupID, world: &world, context: &context)
            world.bookkeeping.arrivalsToday += 1
            context.emit(.groupArrived(reservation.groupID))
        }
    }

    private static func sendToReception(groupID: GroupID, world: inout World, context: inout TickContext) {
        guard let group = world.groups[groupID] else { return }
        let spawn = world.parkEntranceTiles.first ?? world.entranceTile

        for guestID in group.memberIDs {
            world.guests.modify(guestID) { guest in
                guest.position = WorldPoint(spawn)
                guest.activity = .walkingToReception
                guest.detail = .reduced
                guest.path = nil
            }
            world.guestsOnSite += 1
        }

        guard let receptionID = world.index.receptionID else {
            // No reception at all: guests cannot check in. That is a real failure state, and the
            // player is told about it rather than guests silently teleporting into a cottage.
            world.notifications.post(
                priority: .critical,
                text: LocalizedText("notification.noReception"),
                groupingKey: "noReception",
                tick: world.tick,
                allocator: &world.ids
            )
            // Read the tick before taking exclusive access to the guest store: `world.tick` is
            // computed, so reading it touches the whole of `world`.
            let now = world.tick
            for guestID in group.memberIDs {
                world.guests.modify(guestID) { guest in
                    guest.activity = .idle
                    guest.remember(GuestThought(kind: .cantReachDestination, magnitude: 0.9, tick: now))
                }
                context.emit(.guestThought(guestID, .cantReachDestination))
            }
            return
        }

        // Reception is a shared destination, so it has a flow field: no search needed.
        if world.navigation.field(for: receptionID) == nil {
            world.registerSharedDestinations()
        }
        let now = world.tick
        for guestID in group.memberIDs {
            guard let guest = world.guests[guestID] else { continue }
            if let tiles = world.navigation.field(for: receptionID)?.path(from: guest.tile) {
                world.guests.modify(guestID) { $0.path = MovementPath(tiles: tiles) }
            } else {
                world.guests.modify(guestID) { guest in
                    guest.activity = .idle
                    guest.remember(GuestThought(kind: .cantReachDestination, magnitude: 0.8, tick: now))
                }
                world.notifications.post(
                    priority: .warning,
                    text: LocalizedText("notification.receptionUnreachable"),
                    groupingKey: "receptionUnreachable",
                    tick: world.tick,
                    allocator: &world.ids
                )
            }
        }
    }
}
