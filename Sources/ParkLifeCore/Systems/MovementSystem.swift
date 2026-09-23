import Foundation

/// Moves guests and staff along their paths and decides what happens when they arrive.
///
/// Full-detail guests move every tick; reduced-detail (off-camera) guests move in larger steps
/// every fourth tick, which costs a quarter as much and is invisible because nobody is looking.
public enum MovementSystem: SimulationSystem {

    public static let systemName = "Movement"

    public static func update(world: inout World, context: inout TickContext) {
        world.navigation.decayCongestion()

        for guestID in world.guests.sortedIDs {
            guard let guest = world.guests[guestID] else { continue }
            guard guest.detail != .dormant, guest.path != nil else { continue }

            let stride: Int
            switch guest.detail {
            case .full: stride = 1
            case .reduced: stride = 4
            case .dormant: continue
            }
            guard context.tick % stride == 0 else { continue }

            advance(guestID: guestID, distance: guest.walkSpeed * Double(stride), world: &world, context: &context)
        }

        for staffID in world.staff.sortedIDs {
            guard let member = world.staff[staffID], member.path != nil else { continue }
            advanceStaff(staffID: staffID, world: &world, context: &context)
        }
    }

    private static func advance(
        guestID: GuestID,
        distance: Double,
        world: inout World,
        context: inout TickContext
    ) {
        var finished = false
        var visitedTile: GridPoint?

        world.guests.modify(guestID) { guest in
            guard var path = guest.path else { return }
            var remaining = distance
            while remaining > 0 && !path.isFinished {
                let step = min(remaining, 1.0 - path.progress)
                path.progress += step
                remaining -= step
                if path.progress >= 0.999 {
                    path.index += 1
                    path.progress = 0
                    visitedTile = path.index < path.tiles.count ? path.tiles[path.index] : path.tiles.last
                }
            }
            guest.position = path.currentPosition
            guest.path = path
            if path.isFinished {
                guest.path = nil
                finished = true
            }
        }

        if let tile = visitedTile {
            world.navigation.noteOccupancy(at: tile)
            let congestion = world.navigation.congestionLevel(at: tile)
            world.guests.modify(guestID) { guest in
                guest.congestionExposure = movingAverage(
                    current: guest.congestionExposure, sample: congestion, weight: 0.2
                )
            }
            if congestion > 0.8 {
                SatisfactionService.recordThought(
                    guestID: guestID,
                    kind: .tooCrowded,
                    magnitude: congestion,
                    delta: -0.04,
                    world: &world,
                    tick: context.tick
                )
            }
        }

        if finished {
            handleArrival(guestID: guestID, world: &world, context: &context)
        }
    }

    private static func handleArrival(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID] else { return }

        switch guest.activity {
        case .arriving, .walkingToReception:
            if let receptionID = world.index.receptionID {
                // `joinQueue` sets the activity itself, so a refused join leaves the guest idle
                // rather than stood at the desk in a queue they are not in.
                QueueService.joinQueue(guestID: guestID, buildingID: receptionID, world: &world, context: &context)
            } else {
                world.guests.modify(guestID) { $0.activity = .idle }
            }

        case .walkingToUnit:
            arriveAtUnit(guestID: guestID, world: &world, context: &context)

        case .walkingTo(let buildingID):
            QueueService.joinQueue(guestID: guestID, buildingID: buildingID, world: &world, context: &context)

        case .walkingToExit:
            world.guests.modify(guestID) { stored in
                stored.activity = .departed
                stored.detail = .dormant
            }
            world.guestsOnSite = max(0, world.guestsOnSite - 1)

        default:
            world.guests.modify(guestID) { stored in
                if !stored.activity.isDormant { stored.activity = .idle }
            }
        }
    }

    private static func arriveAtUnit(guestID: GuestID, world: inout World, context: inout TickContext) {
        guard let guest = world.guests[guestID], let group = world.groups[guest.groupID] else { return }

        let isDepartureDay = context.date.dayIndex >= group.departureDate.dayIndex
        if isDepartureDay, context.date.minuteOfDay >= context.tuning.wakeMinute {
            world.sleep(
                guest: guestID,
                untilTick: context.tick + context.tuning.packingMinutes,
                activity: .packing
            )
            return
        }

        if !guest.hasUnpacked {
            world.guests.modify(guestID) { $0.hasUnpacked = true }
            world.sleep(
                guest: guestID,
                untilTick: context.tick + context.tuning.unpackingMinutes,
                activity: .unpacking
            )
            return
        }

        // Back at the cottage for a rest.
        world.guests.modify(guestID) { stored in
            stored.activity = .idle
            stored.detail = .reduced
            stored.comfort = clamp01(stored.comfort + 0.05)
        }
    }

    private static func advanceStaff(staffID: StaffID, world: inout World, context: inout TickContext) {
        var finished = false
        world.staff.modify(staffID) { member in
            guard var path = member.path else { return }
            var remaining = 1.4
            while remaining > 0 && !path.isFinished {
                let step = min(remaining, 1.0 - path.progress)
                path.progress += step
                remaining -= step
                if path.progress >= 0.999 {
                    path.index += 1
                    path.progress = 0
                }
            }
            member.position = path.currentPosition
            member.path = path
            if path.isFinished {
                member.path = nil
                finished = true
            }
        }
        if finished {
            StaffSystem.beginWork(staffID: staffID, world: &world, context: &context)
        }
    }
}
