import Foundation

/// Staff, their task queue and the work they actually do.
///
/// Housekeeping is the loop that matters first: a party checks out, the cottage becomes dirty, a
/// task is created, a housekeeper walks there and cleans it, and only then can the next party
/// check in. With nobody to do it, dirty cottages pile up and arrivals are left waiting — which is
/// exactly the consequence a staff shortage should have.
public enum StaffSystem: SimulationSystem {

    public static let systemName = "Staff"

    public static func update(world: inout World, context: inout TickContext) {
        completeFinishedTasks(world: &world, context: &context)
        assignPendingTasks(world: &world, context: &context)
    }

    // MARK: - Task creation

    public static func createCleaningTask(for unit: BuildingID, world: inout World, context: inout TickContext) {
        let alreadyQueued = world.tasks.items.contains { task in
            task.target == unit && task.kind == .cleanUnit && task.state != .completed && task.state != .cancelled
        }
        guard !alreadyQueued else { return }

        let minutes = world.definition(ofBuilding: unit)?.accommodation?.cleaningMinutes ?? 45
        let id = world.ids.next(TaskID.self)
        let task = StaffTask(
            id: id,
            kind: .cleanUnit,
            target: unit,
            createdTick: context.tick,
            priority: 10,
            durationMinutes: minutes
        )
        world.tasks.insert(task)
    }

    // MARK: - Assignment

    private static func assignPendingTasks(world: inout World, context: inout TickContext) {
        let pending = world.tasks.items
            .filter { $0.state == .pending }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdTick < rhs.createdTick
            }
        guard !pending.isEmpty else { return }

        for task in pending {
            guard let staffID = findWorker(for: task, world: world, context: context) else { continue }
            guard let member = world.staff[staffID] else { continue }

            let goals = world.accessTiles(for: task.target)
            let startTile = goals.isEmpty ? member.position.tile : member.position.tile
            guard !goals.isEmpty,
                  let tiles = world.navigation.immediatePath(from: startTile, toAnyOf: goals) else {
                continue
            }

            world.tasks.modify(task.id) { stored in
                stored.state = .assigned
                stored.assignedTo = staffID
            }
            world.staff.modify(staffID) { stored in
                stored.currentTask = task.id
                stored.activity = .walkingTo(task.target)
                stored.path = MovementPath(tiles: tiles)
            }
        }
    }

    /// Nearest idle worker whose role handles this kind of task and who is on shift.
    private static func findWorker(for task: StaffTask, world: World, context: TickContext) -> StaffID? {
        var best: StaffID?
        var bestDistance = Int.max
        for staffID in world.staff.sortedIDs {
            guard let member = world.staff[staffID] else { continue }
            guard member.currentTask == nil, member.activity == .idle else { continue }
            guard member.isOnShift(minuteOfDay: context.date.minuteOfDay) else { continue }
            guard let role = world.catalog.staffRoles[member.roleID],
                  role.handlesTasks.contains(task.kind.rawValue) else { continue }
            if let zone = member.assignedZone, !zone.contains(world.buildings[task.target]?.origin ?? .zero) {
                continue
            }
            let distance = member.position.tile.manhattanDistance(to: world.buildings[task.target]?.origin ?? .zero)
            if distance < bestDistance {
                bestDistance = distance
                best = staffID
            }
        }
        return best
    }

    // MARK: - Work

    /// Called by `MovementSystem` when a staff member reaches their target.
    public static func beginWork(staffID: StaffID, world: inout World, context: inout TickContext) {
        guard let member = world.staff[staffID], let taskID = member.currentTask,
              let task = world.tasks[taskID] else { return }

        // Skill shortens the job; an inexperienced cleaner takes noticeably longer.
        let speed = 0.7 + 0.6 * member.skill
        let minutes = max(3, Int(Double(task.durationMinutes) / speed))
        world.tasks.modify(taskID) { stored in
            stored.state = .inProgress
            stored.completesAtTick = context.tick + minutes
        }
        world.staff.modify(staffID) { stored in
            stored.activity = .working(task.target)
            stored.path = nil
        }
        world.schedule.schedule(.staffTaskComplete, entity: taskID.raw, at: context.tick + minutes)
    }

    private static func completeFinishedTasks(world: inout World, context: inout TickContext) {
        for event in context.dueEvents(ofKind: .staffTaskComplete) {
            let taskID = TaskID(raw: event.entity)
            guard let task = world.tasks[taskID], task.state == .inProgress else { continue }

            switch task.kind {
            case .cleanUnit:
                world.buildings.modify(task.target) { building in
                    building.accommodation?.cleanliness = 1.0
                    building.accommodation?.lastCleanedTick = context.tick
                    if building.accommodation?.state == .dirty || building.accommodation?.state == .cleaning {
                        building.accommodation?.state = .ready
                    }
                }
                context.emit(.unitCleaned(task.target))

            case .cleanFacility:
                world.buildings.modify(task.target) { building in
                    building.facility?.cleanliness = 1.0
                }

            case .repairBuilding:
                world.buildings.modify(task.target) { building in
                    building.condition = clamp01(building.condition + 0.4)
                }

            default:
                break
            }

            world.tasks.modify(taskID) { $0.state = .completed }
            if let staffID = task.assignedTo {
                world.staff.modify(staffID) { stored in
                    stored.currentTask = nil
                    stored.activity = .idle
                    stored.experience += 0.002
                    stored.skill = clamp01(stored.skill + 0.0008)
                }
            }
            context.emit(.staffTaskCompleted(taskID))
            world.tasks.remove(taskID)
        }
    }

    // MARK: - Hiring

    @discardableResult
    public static func hire(roleID: String, world: inout World) -> StaffID? {
        guard let role = world.catalog.staffRoles[roleID] else { return nil }
        let id = world.ids.next(StaffID.self)
        let name = world.random.staff.pick(world.catalog.names.staffNames) ?? "Employee"
        let surname = world.random.staff.pick(world.catalog.names.surnames) ?? ""
        let member = StaffMember(
            id: id,
            name: surname.isEmpty ? name : "\(name) \(surname)",
            roleID: roleID,
            monthlySalary: role.monthlySalary,
            skill: world.random.staff.nextDouble(in: 0.35...0.75),
            position: WorldPoint(world.entranceTile),
            hiredAtTick: world.tick
        )
        world.staff.insert(member)
        ParkLog.shared.info(.staff, "Hired \(member.name) as \(roleID)")
        return id
    }

    @discardableResult
    public static func dismiss(_ id: StaffID, world: inout World) -> Bool {
        guard let member = world.staff[id] else { return false }
        if let taskID = member.currentTask {
            world.tasks.modify(taskID) { stored in
                stored.state = .pending
                stored.assignedTo = nil
                stored.completesAtTick = nil
            }
        }
        world.staff.remove(id)
        return true
    }

    /// Cottages waiting for housekeeping — the number the player watches.
    public static func pendingCleaningCount(in world: World) -> Int {
        world.tasks.items.filter { $0.kind == .cleanUnit && $0.state != .completed }.count
    }
}
