import Foundation

/// Unit lifecycle: waiting check-ins, completed stays, wear and tear.
public enum AccommodationSystem: SimulationSystem {

    public static let systemName = "Accommodation"

    public static func update(world: inout World, context: inout TickContext) {
        retryPendingCheckIns(world: &world, context: &context)
        finaliseCompletedStays(world: &world, context: &context)

        if context.isNewDay {
            applyDailyWear(world: &world, context: context)
            pruneFinishedStays(world: &world, context: context)
        }
    }

    /// A party whose cottage was not ready on arrival checks in the moment housekeeping finishes.
    private static func retryPendingCheckIns(world: inout World, context: inout TickContext) {
        for groupID in world.activeGroupIDs {
            guard let group = world.groups[groupID], group.state == .arriving else { continue }
            guard !group.memberIDs.isEmpty else { continue }
            guard let reservationID = group.reservationID,
                  let reservation = world.reservations[reservationID],
                  reservation.status == .arriving || reservation.status == .paid,
                  let unit = reservation.unitBuildingID,
                  let unitState = world.buildings[unit]?.accommodation,
                  unitState.state.acceptsCheckIn else { continue }

            // Only once a member has actually reached reception and been turned away.
            let waiting = group.memberIDs.contains { memberID in
                guard let guest = world.guests[memberID] else { return false }
                switch guest.activity {
                case .idle, .queueingAtReception: return true
                default: return false
                }
            }
            guard waiting else { continue }

            CheckInService.complete(
                groupID: groupID,
                reservationID: reservationID,
                unit: unit,
                world: &world,
                context: &context
            )
        }
    }

    private static func finaliseCompletedStays(world: inout World, context: inout TickContext) {
        // `activeGroupIDs` is mutated as stays finalise, so iterate a snapshot.
        for groupID in world.activeGroupIDs {
            guard let group = world.groups[groupID], group.state == .checkedIn else { continue }
            CheckoutService.finaliseIfComplete(groupID: groupID, world: &world, context: &context)
        }
    }

    /// Drops finished bookings and their parties once they are far enough in the past to be of no
    /// further interest.
    ///
    /// Without this, a park running for years would accumulate every reservation it ever took and
    /// the save would grow without limit. Everything worth keeping — revenue, occupancy, reviews —
    /// has already been folded into the ledger, the statistics and the review ring.
    static let historyRetentionDays = 30

    private static func pruneFinishedStays(world: inout World, context: TickContext) {
        let cutoff = context.date.dayIndex - historyRetentionDays
        var removedReservations: [ReservationID] = []
        var removedGroups: [GroupID] = []

        for reservation in world.reservations.items {
            guard !reservation.status.isActive else { continue }
            guard reservation.departure.dayIndex < cutoff else { continue }
            removedReservations.append(reservation.id)
            removedGroups.append(reservation.groupID)
        }
        guard !removedReservations.isEmpty else { return }

        for id in removedReservations {
            world.reservations.remove(id)
        }
        for id in removedGroups {
            guard let group = world.groups[id] else { continue }
            guard group.state != .arriving && group.state != .checkedIn else { continue }
            for memberID in group.memberIDs {
                world.guests.remove(memberID)
            }
            world.groups.remove(id)
        }
        world.index.rebuildReservations(world.reservations)
        world.index.rebuildGuests(world.guests)
        ParkLog.shared.debug(
            .sim,
            "Pruned \(removedReservations.count) finished bookings older than \(historyRetentionDays) days"
        )
    }

    /// Buildings wear out; occupied cottages get grubbier.
    private static func applyDailyWear(world: inout World, context: TickContext) {
        let decay = context.tuning.conditionLossPerDay * world.difficulty.operatingCostMultiplier
        for id in world.buildings.sortedIDs {
            world.buildings.modify(id) { building in
                building.condition = clamp01(building.condition - decay)
                if building.accommodation?.state == .occupied {
                    let current = building.accommodation?.cleanliness ?? 1.0
                    building.accommodation?.cleanliness = clamp01(current - context.tuning.cleanlinessLossPerNight * 0.4)
                }
                if building.facility != nil {
                    let current = building.facility?.cleanliness ?? 1.0
                    building.facility?.cleanliness = clamp01(current - 0.03)
                }
            }
        }
    }

    // MARK: - Reporting

    /// Units by state, for the accommodation panel.
    public static func unitCounts(in world: World) -> [UnitState: Int] {
        var counts: [UnitState: Int] = [:]
        for id in world.index.accommodationIDs {
            guard let state = world.buildings[id]?.accommodation?.state else { continue }
            counts[state, default: 0] += 1
        }
        return counts
    }
}
