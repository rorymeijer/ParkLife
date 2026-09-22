import Foundation

/// Aggregated time series, written as things happen.
///
/// Nothing here ever walks historical entities to answer a question — the charts read pre-rolled
/// buckets, which is what keeps a ten-year save as fast to inspect as a ten-day one (brief §37).
public enum StatisticsSystem: SimulationSystem {

    public static let systemName = "Statistics"

    public static func update(world: inout World, context: inout TickContext) {
        for event in context.events {
            switch event {
            case .guestSpent(_, let amount, _):
                world.statistics.accumulateDaily(.revenue, period: context.date.dayIndex, value: amount.euroValue)
            case .groupArrived:
                world.statistics.accumulateDaily(.arrivals, period: context.date.dayIndex, value: 1)
            case .groupCheckedOut:
                world.statistics.accumulateDaily(.departures, period: context.date.dayIndex, value: 1)
            default:
                break
            }
        }

        if context.isNewHour {
            recordHourly(world: &world, context: context)
        }
        if context.isNewDay {
            recordDaily(world: &world, context: context)
        }
        if context.isNewWeek {
            recordWeekly(world: &world, context: context)
        }
    }

    private static func recordHourly(world: inout World, context: TickContext) {
        let hourPeriod = context.date.dayIndex * 24 + context.date.hour
        world.statistics.recordHourly(.guestsOnSite, period: hourPeriod, value: Double(world.guestsOnSite))
        world.statistics.recordHourly(.occupancy, period: hourPeriod, value: world.occupancyRate * 100)
        world.statistics.recordHourly(.satisfaction, period: hourPeriod, value: world.averageGuestHappiness)
        world.statistics.recordHourly(.cashBalance, period: hourPeriod, value: world.cash.euroValue)
        world.bookkeeping.lastStatisticsHour = hourPeriod
    }

    private static func recordDaily(world: inout World, context: TickContext) {
        // Yesterday is now complete, so its totals are final.
        let yesterday = context.previousDate.dayIndex
        if let totals = world.ledger.totals(forDay: yesterday) {
            world.statistics.recordDaily(.revenue, period: yesterday, value: totals.revenue.euroValue)
            world.statistics.recordDaily(.expenses, period: yesterday, value: totals.expenses.euroValue)
            world.statistics.recordDaily(.profit, period: yesterday, value: totals.profit.euroValue)
        }
        world.statistics.recordDaily(.occupancy, period: yesterday, value: ReservationSystem.occupancyRate(on: yesterday, in: world) * 100)
        world.statistics.recordDaily(.satisfaction, period: yesterday, value: world.reputation.guestSatisfaction)
        world.statistics.recordDaily(.reviewScore, period: yesterday, value: world.reputation.averageReviewStars)
        world.statistics.recordDaily(.cashBalance, period: yesterday, value: world.cash.euroValue)
        world.statistics.recordDaily(.staffCount, period: yesterday, value: Double(world.staff.count))
        world.bookkeeping.lastStatisticsDay = yesterday
    }

    private static func recordWeekly(world: inout World, context: TickContext) {
        let week = context.previousDate.weekIndex
        world.statistics.recordWeekly(.profit, period: week, value: world.ledger.trailingProfit(days: 7).euroValue)
        world.statistics.recordWeekly(.revenue, period: week, value: world.ledger.trailingRevenue(days: 7).euroValue)
        world.statistics.recordWeekly(.occupancy, period: week, value: world.occupancyRate * 100)
        world.statistics.recordWeekly(.reviewScore, period: week, value: world.reputation.averageReviewStars)
    }

    /// Annual revenue, from the daily buckets rather than the entry log.
    public static func annualRevenue(in world: World) -> Money {
        world.ledger.trailingRevenue(days: 365)
    }
}
