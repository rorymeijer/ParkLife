import Foundation

/// Emits calendar boundary events. The clock itself is advanced by the engine before systems run,
/// so every system sees the same "now".
public enum TimeSystem: SimulationSystem {

    public static let systemName = "Time"

    public static func update(world: inout World, context: inout TickContext) {
        if context.isNewHour {
            context.emit(.hourElapsed(context.date.hour))
        }
        if context.isNewDay {
            context.emit(.dayElapsed(context.date.dayIndex))
            world.bookkeeping.lostEnquiriesToday = 0
            world.bookkeeping.lostEnquiriesPriceToday = 0
            world.bookkeeping.arrivalsToday = 0
            world.bookkeeping.departuresToday = 0
            resetDailyFacilityCounters(&world)
        }
        if context.isNewWeek {
            context.emit(.weekElapsed(context.date.weekIndex))
        }
        if context.date.season != context.previousDate.season {
            context.emit(.seasonChanged(context.date.season))
        }
    }

    private static func resetDailyFacilityCounters(_ world: inout World) {
        for id in world.index.facilityIDs {
            world.buildings.modify(id) { building in
                building.facility?.visitsToday = 0
                building.facility?.revenueToday = .zero
            }
        }
    }
}
