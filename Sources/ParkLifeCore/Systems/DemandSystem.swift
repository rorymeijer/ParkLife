import Foundation

/// Generates enquiries once a day and turns the ones that convert into bookings.
///
/// Demand is a product of real factors (season, weekday, school holidays, reputation, facility
/// mix, price versus perceived value) rather than a single fudge multiplier — see
/// docs/SIMULATION.md §5.
public enum DemandSystem: SimulationSystem {

    public static let systemName = "Demand"

    /// Enquiries arrive in the small hours, so the player sees the day's bookings on waking.
    public static let generationMinuteOfDay = 3 * 60 + 30

    public static func update(world: inout World, context: inout TickContext) {
        guard context.date.minuteOfDay == generationMinuteOfDay else { return }
        guard world.bookkeeping.lastDemandDay != context.date.dayIndex else { return }
        world.bookkeeping.lastDemandDay = context.date.dayIndex

        let unitCount = world.index.accommodationIDs.count
        guard unitCount > 0 else { return }

        let localDemand = world.catalog.maps[world.mapID]?.localDemand ?? 1.0
        let expected = context.tuning.enquiriesPerUnitPerDay
            * Double(unitCount)
            * localDemand
            * world.reputation.demandFactor
            * facilityFactor(in: world)

        let enquiries = world.random.demand.poisson(mean: max(0, expected))
        guard enquiries > 0 else { return }

        var created = 0
        for _ in 0..<enquiries {
            if processEnquiry(world: &world, context: &context) {
                created += 1
            }
        }
        if created > 0 {
            ParkLog.shared.debug(.sim, "Day \(context.date.dayIndex): \(created)/\(enquiries) enquiries converted")
        }
    }

    /// Variety and quality of what the park offers. An empty park is a hard sell.
    public static func facilityFactor(in world: World) -> Double {
        var kinds: Set<String> = []
        var qualitySum = 0.0
        var count = 0
        for id in world.index.facilityIDs {
            guard let instance = world.buildings[id],
                  let definition = world.definition(of: instance),
                  let facility = definition.facility else { continue }
            switch facility.kind {
            case .entrance, .reception: continue
            default: break
            }
            kinds.insert(facility.kind.rawValue)
            qualitySum += facility.appeal * instance.condition
            count += 1
        }
        guard count > 0 else { return 0.45 }
        let variety = clamp01(Double(kinds.count) / 6.0)
        let quality = clamp01(qualitySum / Double(count))
        return clamp(0.45 + 0.75 * variety + 0.35 * quality, 0.45, 1.55)
    }

    /// One enquiry: pick who is asking, when, and whether they book.
    private static func processEnquiry(world: inout World, context: inout TickContext) -> Bool {
        guard let archetype = pickArchetype(world: &world, date: context.date) else { return false }

        let adults = world.random.demand.nextInt(in: archetype.minimumAdults...archetype.maximumAdults)
        let children = archetype.maximumChildren > 0
            ? world.random.demand.nextInt(in: archetype.minimumChildren...archetype.maximumChildren)
            : 0
        let partySize = adults + children
        guard partySize > 0 else { return false }

        let nights = world.random.demand.nextInt(in: archetype.minimumNights...archetype.maximumNights)
        let leadDays = sampleLeadTime(world: &world, horizon: context.tuning.bookingHorizonDays)
        var arrivalDay = context.date.startOfDay.adding(days: leadDays)
        arrivalDay = shiftToPreferredArrivalDay(arrivalDay, world: &world)
        // Parties turn up through the afternoon and evening, and leave by mid-morning.
        let checkInMinute = context.tuning.checkInFromMinute + world.random.demand.nextInt(in: 0...300)
        let arrival = arrivalDay.adding(minutes: checkInMinute)
        let departure = arrivalDay.adding(days: nights).adding(minutes: context.tuning.checkOutByMinute)

        // Seasonal and calendar pull decides whether this party bothers enquiring at all.
        let pull = seasonFactor(for: arrival)
            * weekdayFactor(for: arrival)
            * calendarFactor(for: arrival, archetype: archetype, world: world)
        if !world.random.demand.chance(clamp01(pull / 2.4)) {
            return false
        }

        let candidates = ReservationEngine.availableUnits(
            partySize: partySize,
            preferredTiers: archetype.preferredTiers,
            arrival: arrival,
            departure: departure,
            in: world
        )
        guard !candidates.isEmpty else {
            world.bookkeeping.lostEnquiriesToday += 1
            return false
        }

        // Prefer the best value: quality per euro, with a mild preference for a right-sized unit.
        var bestUnit: BuildingID?
        var bestScore = -1.0
        var bestPrice = Money.zero
        var bestQuality = 0.0
        for unit in candidates {
            guard let instance = world.buildings[unit],
                  let definition = world.definition(of: instance),
                  let accommodation = definition.accommodation else { continue }
            let price = ReservationEngine.stayPrice(unit: unit, arrival: arrival, departure: departure, in: world)
            guard price.cents > 0 else { continue }
            let quality = ReservationEngine.quality(of: unit, in: world)
            let sizeFit = 1.0 - clamp01(Double(accommodation.capacity - partySize) / 6.0) * 0.35
            let score = quality * sizeFit / (Double(price.cents) / Double(max(1, partySize * nights)) / 6_000.0)
            if score > bestScore {
                bestScore = score
                bestUnit = unit
                bestPrice = price
                bestQuality = quality
            }
        }
        guard let unit = bestUnit else {
            world.bookkeeping.lostEnquiriesToday += 1
            return false
        }

        let frugality = world.random.demand.nextDouble(in: 0.25...0.75)
        let acceptance = ReservationEngine.acceptanceProbability(
            price: bestPrice,
            quality: bestQuality,
            archetype: archetype,
            partySize: partySize,
            nights: nights,
            frugality: frugality
        )
        guard world.random.demand.chance(acceptance) else {
            world.bookkeeping.lostEnquiriesPriceToday += 1
            return false
        }

        var discount = Money.zero
        if leadDays <= 7, world.pricing.lastMinuteDiscount > 0 {
            discount = bestPrice.scaled(by: clamp01(world.pricing.lastMinuteDiscount))
        }

        guard let reservationID = ReservationEngine.book(
            unit: unit,
            archetype: archetype,
            adults: adults,
            children: children,
            arrival: arrival,
            departure: departure,
            price: bestPrice,
            discount: discount,
            in: &world
        ) else {
            world.bookkeeping.lostEnquiriesToday += 1
            return false
        }
        context.emit(.reservationCreated(reservationID))
        return true
    }

    private static func pickArchetype(world: inout World, date: GameDate) -> GroupArchetypeDefinition? {
        let definitions = world.catalog.archetypeIDs.compactMap { world.catalog.archetypes[$0] }
        guard !definitions.isEmpty else { return nil }
        let weights = definitions.map { $0.marketShare }
        guard let index = world.random.demand.weightedIndex(weights) else { return nil }
        return definitions[index]
    }

    /// Bookings cluster close to the stay, with a long tail of early planners.
    private static func sampleLeadTime(world: inout World, horizon: Int) -> Int {
        let roll = world.random.demand.nextUnit()
        let shaped = pow(roll, 2.1)
        return max(1, Int(shaped * Double(horizon)))
    }

    /// Most holiday parks turn over on Friday and Monday.
    private static func shiftToPreferredArrivalDay(_ date: GameDate, world: inout World) -> GameDate {
        let roll = world.random.demand.nextUnit()
        let target: Weekday
        if roll < 0.44 {
            target = .friday
        } else if roll < 0.72 {
            target = .monday
        } else if roll < 0.86 {
            target = .saturday
        } else {
            return date
        }
        let current = date.weekday.rawValue
        var delta = target.rawValue - current
        if delta < 0 { delta += 7 }
        return date.adding(days: delta)
    }

    public static func seasonFactor(for date: GameDate) -> Double {
        switch date.season {
        case .summer: return 1.75
        case .spring: return 1.05
        case .autumn: return 0.80
        case .winter: return 0.55
        }
    }

    public static func weekdayFactor(for date: GameDate) -> Double {
        switch date.weekday {
        case .friday: return 1.60
        case .saturday: return 1.45
        case .monday: return 0.95
        case .sunday: return 0.70
        case .thursday: return 0.75
        default: return 0.65
        }
    }

    /// School and public holiday windows, from `calendars.json`, so other countries differ by data.
    public static func calendarFactor(
        for date: GameDate,
        archetype: GroupArchetypeDefinition,
        world: World
    ) -> Double {
        guard let calendar = world.catalog.calendars[world.regionID] else { return 1.0 }
        for window in calendar.windows where isDate(date, inside: window) {
            if window.isSchoolHoliday {
                // Only families with school-age children are pinned to the school calendar.
                return 1.0 + (window.demandBoost - 1.0) * archetype.schoolHolidaySensitivity
            }
            return window.demandBoost
        }
        return 1.0
    }

    private static func isDate(_ date: GameDate, inside window: CalendarDefinition.Window) -> Bool {
        let value = date.month * 100 + date.dayOfMonth
        let start = window.startMonth * 100 + window.startDay
        let end = window.endMonth * 100 + window.endDay
        if start <= end {
            return value >= start && value <= end
        }
        // Window wraps the new year (e.g. 19 December – 3 January).
        return value >= start || value <= end
    }
}
