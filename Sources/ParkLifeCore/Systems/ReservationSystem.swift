import Foundation

/// Drives the booking lifecycle: deposits, cancellations, arrival flags and no-shows.
///
/// ```
/// enquiry → booked → paid → arriving → checkedIn → checkedOut
///                 ↘ cancelled          ↘ noShow
/// ```
public enum ReservationSystem: SimulationSystem {

    public static let systemName = "Reservations"

    /// Share of the stay taken as a non-refundable deposit when the booking is confirmed.
    public static let depositFraction = 0.30
    /// How many days before arrival the deposit is taken.
    public static let depositLeadDays = 14

    public static func update(world: inout World, context: inout TickContext) {
        // Lifecycle transitions are a daily concern; running them every minute would be pure waste.
        guard context.date.minuteOfDay == 4 * 60 else { return }

        let today = context.date.dayIndex
        for id in world.reservations.sortedIDs {
            guard let reservation = world.reservations[id], reservation.status.isActive else { continue }

            switch reservation.status {
            case .enquiry, .booked:
                if reservation.arrival.dayIndex - today <= depositLeadDays {
                    takeDeposit(reservation: reservation, world: &world)
                } else if shouldCancel(reservation: reservation, world: &world, context: context) {
                    cancel(reservation: reservation, world: &world, context: &context)
                    continue
                }

            case .paid:
                if reservation.arrival.dayIndex == today {
                    world.reservations.modify(id) { $0.status = .arriving }
                    world.groups.modify(reservation.groupID) { $0.state = .arriving }
                } else if shouldCancel(reservation: reservation, world: &world, context: context) {
                    cancel(reservation: reservation, world: &world, context: &context)
                    continue
                }

            case .arriving:
                // Still flagged as arriving a day later means they never turned up.
                if reservation.arrival.dayIndex < today {
                    markNoShow(reservation: reservation, world: &world, context: &context)
                }

            default:
                break
            }
        }
    }

    private static func takeDeposit(reservation: Reservation, world: inout World) {
        let deposit = reservation.price.scaled(by: depositFraction)
        let now = world.tick
        world.reservations.modify(reservation.id) { stored in
            stored.status = .paid
            stored.paidAtTick = now
        }
        world.earn(deposit, category: .accommodation, reference: reservation.unitBuildingID?.raw)
    }

    private static func shouldCancel(
        reservation: Reservation,
        world: inout World,
        context: TickContext
    ) -> Bool {
        guard reservation.arrival.dayIndex - context.date.dayIndex > 2 else { return false }
        return world.random.demand.chance(context.tuning.cancellationProbabilityPerDay)
    }

    private static func cancel(reservation: Reservation, world: inout World, context: inout TickContext) {
        world.reservations.modify(reservation.id) { $0.status = .cancelled }
        world.groups.modify(reservation.groupID) { $0.state = .cancelled }
        context.emit(.reservationCancelled(reservation.id))
        ParkLog.shared.debug(.sim, "Reservation \(reservation.id) cancelled")
    }

    private static func markNoShow(reservation: Reservation, world: inout World, context: inout TickContext) {
        world.reservations.modify(reservation.id) { $0.status = .noShow }
        world.groups.modify(reservation.groupID) { $0.state = .noShow }
        // The deposit is kept; the balance is never collected.
        context.emit(.groupNoShow(reservation.groupID))
    }

    // MARK: - Reporting helpers used by the UI

    /// Units occupied on a given night, for the occupancy calendar.
    public static func occupiedUnits(on dayIndex: Int, in world: World) -> Int {
        var count = 0
        for reservation in world.reservations.items
        where reservation.status.holdsUnit && reservation.occupiesNight(dayIndex: dayIndex) {
            count += 1
        }
        return count
    }

    public static func occupancyRate(on dayIndex: Int, in world: World) -> Double {
        let units = world.index.accommodationIDs.count
        guard units > 0 else { return 0 }
        return Double(occupiedUnits(on: dayIndex, in: world)) / Double(units)
    }

    /// Reservations arriving on a day, in arrival-time order.
    public static func arrivals(on dayIndex: Int, in world: World) -> [Reservation] {
        world.reservations.items
            .filter { $0.arrival.dayIndex == dayIndex && $0.status.isActive }
            .sorted { $0.arrival.minutesSinceEpoch < $1.arrival.minutesSinceEpoch }
    }

    public static func departures(on dayIndex: Int, in world: World) -> [Reservation] {
        world.reservations.items
            .filter { $0.departure.dayIndex == dayIndex && $0.status != .cancelled }
            .sorted { $0.departure.minutesSinceEpoch < $1.departure.minutesSinceEpoch }
    }

    /// Booked accommodation revenue for the next `days` days — the forecast panel.
    public static func revenueForecast(days: Int, from dayIndex: Int, in world: World) -> [Money] {
        var result = [Money](repeating: .zero, count: max(0, days))
        guard days > 0 else { return result }
        for reservation in world.reservations.items where reservation.status.holdsUnit {
            let nights = max(1, reservation.nights)
            let perNight = reservation.price.split(into: nights)
            for night in 0..<nights {
                let offset = reservation.arrival.dayIndex + night - dayIndex
                if offset >= 0 && offset < days {
                    result[offset] += perNight[night]
                }
            }
        }
        return result
    }
}
