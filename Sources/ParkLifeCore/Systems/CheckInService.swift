import Foundation

/// Check-in: the moment a booking becomes a stay.
public enum CheckInService {

    /// A guest has been served at reception.
    public static func checkIn(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID], let group = world.groups[guest.groupID] else { return }

        if group.state == .checkedIn {
            // A later member of a group that is already checked in: send them straight to the unit.
            sendToUnit(guestID: guestID, world: &world)
            return
        }

        guard let reservationID = group.reservationID,
              let reservation = world.reservations[reservationID],
              let unit = reservation.unitBuildingID,
              let unitInstance = world.buildings[unit],
              let unitState = unitInstance.accommodation else {
            world.guests.modify(guestID) { $0.activity = .idle; $0.detail = .reduced }
            return
        }

        guard unitState.state.acceptsCheckIn else {
            // The cottage is not ready. The party waits, and that wait is felt.
            world.guests.modify(guestID) { stored in
                stored.activity = .idle
                stored.detail = .reduced
                stored.decisionCooldownUntilTick = context.tick + 20
            }
            SatisfactionService.record(
                groupID: guest.groupID,
                category: .staff,
                delta: -0.06,
                reasonKey: "moment.waitingForCottage",
                world: &world,
                tick: context.tick
            )
            world.notifications.post(
                priority: .warning,
                text: LocalizedText("notification.arrivalWaitingForClean"),
                groupingKey: "arrivalWaitingForClean",
                tick: context.tick,
                subject: unit.raw,
                allocator: &world.ids
            )
            return
        }

        complete(groupID: guest.groupID, reservationID: reservationID, unit: unit, world: &world, context: &context)
    }

    /// Completes check-in for the whole party.
    public static func complete(
        groupID: GroupID,
        reservationID: ReservationID,
        unit: BuildingID,
        world: inout World,
        context: inout TickContext
    ) {
        guard let reservation = world.reservations[reservationID] else { return }

        // Balance of the stay is collected now; the deposit was taken earlier.
        let deposit = reservation.price.scaled(by: ReservationSystem.depositFraction)
        let balance = Money(cents: max(0, reservation.price.cents - deposit.cents))
        world.earn(balance, category: .accommodation, reference: unit.raw)

        world.reservations.modify(reservationID) { $0.status = .checkedIn }
        world.groups.modify(groupID) { group in
            group.state = .checkedIn
            group.unitBuildingID = unit
        }
        world.buildings.modify(unit) { building in
            building.accommodation?.state = .occupied
            building.accommodation?.currentReservationID = reservationID
            building.accommodation?.totalNightsSold += reservation.nights
            building.accommodation?.lifetimeRevenue += reservation.price
        }
        world.statistics.totalNightsSold += reservation.nights
        world.statistics.totalGuestsHosted += reservation.partySize

        recordArrivalImpressions(groupID: groupID, unit: unit, world: &world, context: &context)

        guard let group = world.groups[groupID] else { return }
        for memberID in group.memberIDs {
            if let receptionID = world.index.receptionID {
                // Both the queue and the desk: a member still being served is pulled out too,
                // otherwise their service slot is never released.
                QueueService.leaveFacility(guestID: memberID, buildingID: receptionID, world: &world)
            }
            sendToUnit(guestID: memberID, world: &world)
        }
        context.emit(.groupCheckedIn(groupID))
        ParkLog.shared.debug(.guest, "Group \(groupID) checked into unit \(unit)")
    }

    /// First impressions: how clean the cottage is, and how far it is from what they came for.
    private static func recordArrivalImpressions(
        groupID: GroupID,
        unit: BuildingID,
        world: inout World,
        context: inout TickContext
    ) {
        guard let group = world.groups[groupID],
              let instance = world.buildings[unit],
              let definition = world.definition(of: instance),
              let accommodation = definition.accommodation else { return }

        let cleanliness = instance.accommodation?.cleanliness ?? 1.0
        if cleanliness < 0.5 {
            SatisfactionService.record(
                groupID: groupID,
                category: .cleanliness,
                delta: -0.85,
                reasonKey: ThoughtKind.cottageWasDirty.localizationKey,
                world: &world,
                tick: context.tick
            )
            for memberID in group.memberIDs {
                world.guests.modify(memberID) { guest in
                    guest.remember(GuestThought(kind: .cottageWasDirty, magnitude: 1 - cleanliness, tick: context.tick))
                }
            }
        } else if cleanliness > 0.9 {
            SatisfactionService.record(
                groupID: groupID,
                category: .cleanliness,
                delta: 0.30,
                reasonKey: "moment.spotlessCottage",
                world: &world,
                tick: context.tick
            )
        }

        // Quality against expectation.
        let quality = ReservationEngine.quality(of: unit, in: world)
        let delta = clamp((quality - group.expectation) * 1.3, -0.9, 0.9)
        SatisfactionService.record(
            groupID: groupID,
            category: .accommodation,
            delta: delta,
            reasonKey: accommodation.tier.localizationKey,
            world: &world,
            tick: context.tick
        )
        if delta > 0.35, let first = group.memberIDs.first {
            world.guests.modify(first) { guest in
                guest.remember(GuestThought(kind: .cottageIsLovely, magnitude: delta, tick: context.tick))
            }
        }

        // "Our cottage is too far from the pool" — measured on the real path network.
        let entranceTile = instance.origin
        for kind in [FacilityKind.pool, FacilityKind.restaurant] {
            let facilities = world.index.facilities(ofKind: kind)
            guard !facilities.isEmpty else { continue }
            var nearest: Int?
            for facilityID in facilities {
                if let distance = world.navigation.tileDistance(from: entranceTile, to: facilityID) {
                    nearest = nearest.map { Swift.min($0, distance) } ?? distance
                }
            }
            guard let distance = nearest, distance > 55 else { continue }
            let thought: ThoughtKind = kind == .pool ? .cottageTooFarFromPool : .cottageTooFarFromRestaurant
            let magnitude = clamp01(Double(distance - 55) / 45.0)
            SatisfactionService.record(
                groupID: groupID,
                category: .location,
                delta: -0.25 * magnitude - 0.1,
                reasonKey: thought.localizationKey,
                world: &world,
                tick: context.tick
            )
            if let first = group.memberIDs.first {
                world.guests.modify(first) { guest in
                    guest.remember(GuestThought(kind: thought, magnitude: magnitude, tick: context.tick, subject: unit.raw))
                }
            }
        }

        // Nothing for the children to do is a complaint families actually make.
        let hasChildren = group.memberIDs.contains { world.guests[$0]?.ageBand == .child }
        if hasChildren {
            let childFriendly = world.index.facilityIDs.filter { id in
                guard let facility = world.definition(ofBuilding: id)?.facility else { return false }
                return facility.childSuitability > 0.6 && world.isOperational(id)
            }
            if childFriendly.count < 2 {
                SatisfactionService.record(
                    groupID: groupID,
                    category: .activities,
                    delta: -0.45,
                    reasonKey: ThoughtKind.notEnoughForChildren.localizationKey,
                    world: &world,
                    tick: context.tick
                )
            }
        }
    }

    private static func sendToUnit(guestID: GuestID, world: inout World) {
        guard let guest = world.guests[guestID],
              let group = world.groups[guest.groupID],
              let unit = group.unitBuildingID else { return }
        let goals = world.accessTiles(for: unit)
        if !goals.isEmpty, let tiles = world.navigation.immediatePath(from: guest.tile, toAnyOf: goals) {
            world.guests.modify(guestID) { stored in
                stored.activity = .walkingToUnit
                stored.detail = .reduced
                stored.path = MovementPath(tiles: tiles)
            }
        } else {
            let now = world.tick
            world.guests.modify(guestID) { stored in
                stored.activity = .idle
                stored.detail = .reduced
                stored.remember(GuestThought(kind: .cantReachDestination, magnitude: 0.9, tick: now))
            }
        }
    }
}
