import Foundation

/// Turns simulation conditions into prioritised, de-duplicated alerts.
///
/// Every alert here has a cooldown and an aggregation key, because the raw events behind them
/// (a cottage needing cleaning, a guest failing to find a toilet) fire far too often to surface
/// one-for-one (brief §38).
public enum NotificationSystem: SimulationSystem {

    public static let systemName = "Notifications"

    public static func update(world: inout World, context: inout TickContext) {
        // Immediate, event-driven alerts.
        for event in context.events {
            switch event {
            case .groupNoShow(let groupID):
                world.notifications.post(
                    priority: .info,
                    text: LocalizedText("notification.noShow"),
                    groupingKey: "noShow",
                    tick: context.tick,
                    subject: groupID.raw,
                    cooldownMinutes: 720,
                    allocator: &world.ids
                )
            case .researchCompleted(let id):
                world.notifications.post(
                    priority: .info,
                    text: LocalizedText("notification.researchCompleted", [.text(id)]),
                    groupingKey: "research.\(id)",
                    tick: context.tick,
                    cooldownMinutes: 1,
                    allocator: &world.ids
                )
            default:
                break
            }
        }

        // Periodic condition checks — hourly is often enough for anything the player can act on.
        guard context.isNewHour else { return }
        checkHousekeepingBacklog(world: &world, context: context)
        checkCash(world: &world, context: context)
        checkUnstaffedFacilities(world: &world, context: context)
        checkBrokenBuildings(world: &world, context: context)

        if context.isNewDay {
            checkLostDemand(world: &world, context: context)
        }
    }

    private static func checkHousekeepingBacklog(world: inout World, context: TickContext) {
        let waiting = world.index.accommodationIDs.filter { world.buildings[$0]?.accommodation?.state == .dirty }.count
        guard waiting >= 3 else { return }
        let housekeepers = world.staff.items.filter { $0.roleID == "housekeeping" }.count
        world.notifications.post(
            priority: housekeepers == 0 ? .critical : .warning,
            text: LocalizedText("notification.cottagesAwaitingCleaning", [.integer(waiting)]),
            groupingKey: "cottagesAwaitingCleaning",
            tick: context.tick,
            cooldownMinutes: 240,
            allocator: &world.ids
        )
    }

    private static func checkCash(world: inout World, context: TickContext) {
        guard world.cash.cents < 0 else { return }
        world.notifications.post(
            priority: .critical,
            text: LocalizedText("notification.overdrawn", [.money(world.cash)]),
            groupingKey: "overdrawn",
            tick: context.tick,
            cooldownMinutes: 720,
            allocator: &world.ids
        )
    }

    private static func checkUnstaffedFacilities(world: inout World, context: TickContext) {
        var required = 0
        for id in world.index.facilityIDs {
            guard let facility = world.definition(ofBuilding: id)?.facility else { continue }
            required += facility.staffRequired
        }
        guard required > world.staff.count else { return }
        world.notifications.post(
            priority: .warning,
            text: LocalizedText("notification.understaffed", [.integer(required - world.staff.count)]),
            groupingKey: "understaffed",
            tick: context.tick,
            cooldownMinutes: 1_440,
            allocator: &world.ids
        )
    }

    private static func checkBrokenBuildings(world: inout World, context: TickContext) {
        let broken = world.buildings.items.filter { $0.condition < 0.25 }
        guard !broken.isEmpty else { return }
        world.notifications.post(
            priority: .critical,
            text: LocalizedText("notification.buildingsOutOfService", [.integer(broken.count)]),
            groupingKey: "buildingsOutOfService",
            tick: context.tick,
            cooldownMinutes: 480,
            allocator: &world.ids
        )
    }

    /// Demand that walked away is the single most actionable number in the game.
    private static func checkLostDemand(world: inout World, context: TickContext) {
        let lostCapacity = world.bookkeeping.lostEnquiriesToday
        let lostPrice = world.bookkeeping.lostEnquiriesPriceToday
        if lostCapacity >= 5 {
            world.notifications.post(
                priority: .info,
                text: LocalizedText("notification.lostEnquiriesCapacity", [.integer(lostCapacity)]),
                groupingKey: "lostEnquiriesCapacity",
                tick: context.tick,
                cooldownMinutes: 1_440,
                allocator: &world.ids
            )
        }
        if lostPrice >= 8 {
            world.notifications.post(
                priority: .info,
                text: LocalizedText("notification.lostEnquiriesPrice", [.integer(lostPrice)]),
                groupingKey: "lostEnquiriesPrice",
                tick: context.tick,
                cooldownMinutes: 1_440,
                allocator: &world.ids
            )
        }
    }
}
