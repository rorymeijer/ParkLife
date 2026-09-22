import Foundation

/// Daily settlement: running costs, wages, utilities, loans and tax.
///
/// Settled once a day in the small hours rather than trickled per tick, so the books are readable
/// and the player is never asked to do accounting (brief §15).
public enum EconomySystem: SimulationSystem {

    public static let systemName = "Economy"

    public static let settlementMinuteOfDay = 3 * 60

    public static func update(world: inout World, context: inout TickContext) {
        guard context.date.minuteOfDay == settlementMinuteOfDay else { return }
        guard world.bookkeeping.lastSettlementDay != context.date.dayIndex else { return }
        world.bookkeeping.lastSettlementDay = context.date.dayIndex

        let costScale = world.difficulty.operatingCostMultiplier
        settleOperatingCosts(world: &world, context: context, scale: costScale)
        settleWages(world: &world, scale: costScale)
        settleUtilities(world: &world, context: context, scale: costScale)
        settleLoans(world: &world)

        if context.isNewMonth {
            settleMonthlyTax(world: &world, context: context)
        }
    }

    private static func settleOperatingCosts(world: inout World, context: TickContext, scale: Double) {
        var operating = Money.zero
        var insurance = Money.zero
        for building in world.buildings.items {
            guard let definition = world.catalog.buildings[building.definitionID] else { continue }
            operating += definition.dailyOperatingCost
            if let accommodation = definition.accommodation, building.accommodation?.state == .occupied {
                operating += accommodation.dailyOperatingCost
            }
            insurance += context.tuning.insurancePerBuildingPerDay
        }
        world.spend(operating.scaled(by: scale), category: .maintenance)
        world.spend(insurance.scaled(by: scale), category: .insurance)
    }

    private static func settleWages(world: inout World, scale: Double) {
        var wages = Money.zero
        for member in world.staff.items {
            // Monthly salary spread evenly across a 30-day month.
            wages += member.monthlySalary.scaled(by: 1.0 / 30.0)
        }
        world.spend(wages.scaled(by: scale), category: .wages)
    }

    private static func settleUtilities(world: inout World, context: TickContext, scale: Double) {
        var kilowattHours = 0.0
        var litres = 0.0

        // Heating and cooling track how far the weather is from comfortable.
        let temperatureLoad = 1.0 + clamp01(abs(world.weather.dailyMeanTemperature - 19.0) / 22.0)

        for building in world.buildings.items {
            guard let definition = world.catalog.buildings[building.definitionID] else { continue }
            if let accommodation = definition.accommodation {
                let occupied = building.accommodation?.state == .occupied
                // An empty cottage still ticks over at a fraction of the cost.
                let factor = occupied ? 1.0 : 0.18
                kilowattHours += accommodation.energyPerNightKWh * factor * temperatureLoad
                litres += accommodation.waterPerNightLitres * factor
            }
            if let facility = definition.facility {
                let visits = Double(building.facility?.visitsToday ?? 0)
                kilowattHours += Double(facility.capacity) * 0.55 * temperatureLoad
                litres += visits * (facility.kind == .pool ? 42.0 : 6.0)
            }
        }

        let electricity = context.tuning.electricityPricePerKWh.scaled(by: kilowattHours)
        let water = context.tuning.waterPricePerCubicMetre.scaled(by: litres / 1_000.0)
        let waste = context.tuning.wasteCostPerGuestPerDay * max(0, world.guestsOnSite)

        world.spend(electricity.scaled(by: scale), category: .electricity)
        world.spend(water.scaled(by: scale), category: .water)
        world.spend(waste.scaled(by: scale), category: .waste)

        world.statistics.recordDaily(.energyKWh, period: world.date.dayIndex, value: kilowattHours)
        world.statistics.recordDaily(.waterLitres, period: world.date.dayIndex, value: litres)
    }

    private static func settleLoans(world: inout World) {
        guard !world.loans.isEmpty else { return }
        var interestTotal = Money.zero
        var repaidTotal = Money.zero
        for index in world.loans.indices {
            let interest = world.loans[index].dailyInterest
            let principal = Money(
                cents: min(world.loans[index].dailyPrincipal.cents, world.loans[index].outstanding.cents)
            )
            interestTotal += interest
            repaidTotal += principal
            world.loans[index].outstanding -= principal
        }
        world.loans.removeAll { $0.outstanding.cents <= 0 }
        world.spend(interestTotal, category: .interest)
        if repaidTotal.cents > 0 {
            // Principal repayment is a balance-sheet movement, not a running cost, but it still
            // leaves the bank account.
            world.cash -= repaidTotal
        }
    }

    private static func settleMonthlyTax(world: inout World, context: TickContext) {
        let monthIndex = context.previousDate.monthIndex
        guard let totals = world.ledger.monthlyTotals.last(where: { $0.periodIndex == monthIndex }) else { return }
        let profit = totals.profit
        if profit.cents > 0 {
            world.spend(profit.scaled(by: context.tuning.profitTaxRate), category: .tax)
        }
        // Objective tracking: consecutive profitable months.
        if world.bookkeeping.lastProfitMonthIndex != monthIndex {
            world.bookkeeping.lastProfitMonthIndex = monthIndex
            world.bookkeeping.consecutiveProfitableMonths = profit.cents > 0
                ? world.bookkeeping.consecutiveProfitableMonths + 1
                : 0
        }
    }

    // MARK: - Loans

    @discardableResult
    public static func takeLoan(amount: Money, termDays: Int, world: inout World, rate: Double? = nil) -> Bool {
        guard amount.cents > 0 else { return false }
        let effectiveRate = rate ?? SimulationTuning().defaultLoanRate
        world.loans.append(
            Loan(principal: amount, annualRate: effectiveRate, takenAtTick: world.tick, termDays: termDays)
        )
        world.cash += amount
        ParkLog.shared.info(.economy, "Took a loan of \(amount) over \(termDays) days")
        return true
    }

    public static func totalDebt(in world: World) -> Money {
        Money(cents: world.loans.reduce(0) { $0 + $1.outstanding.cents })
    }
}
