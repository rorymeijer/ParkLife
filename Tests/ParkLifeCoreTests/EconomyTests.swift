import XCTest
@testable import ParkLifeCore

final class LedgerTests: XCTestCase {

    func testRevenueAndExpensesAggregate() {
        var ledger = Ledger()
        let day = GameDate(year: 2026, month: 5, day: 4, hour: 12)
        ledger.record(.revenue, category: RevenueCategory.accommodation.rawValue, amount: Money(euros: 500), tick: day.minutesSinceEpoch)
        ledger.record(.revenue, category: RevenueCategory.food.rawValue, amount: Money(euros: 120), tick: day.minutesSinceEpoch)
        ledger.record(.expense, category: ExpenseCategory.wages.rawValue, amount: Money(euros: 300), tick: day.minutesSinceEpoch)

        let totals = ledger.totals(forDay: day.dayIndex)
        XCTAssertEqual(totals?.revenue, Money(euros: 620))
        XCTAssertEqual(totals?.expenses, Money(euros: 300))
        XCTAssertEqual(totals?.profit, Money(euros: 320))
        XCTAssertEqual(ledger.lifetimeRevenue, Money(euros: 620))
        XCTAssertEqual(ledger.lifetimeProfit, Money(euros: 320))
    }

    func testDaysAreBucketedSeparately() {
        var ledger = Ledger()
        let first = GameDate(year: 2026, month: 5, day: 4, hour: 12).minutesSinceEpoch
        let second = GameDate(year: 2026, month: 5, day: 5, hour: 12).minutesSinceEpoch
        ledger.record(.revenue, category: "accommodation", amount: Money(euros: 100), tick: first)
        ledger.record(.revenue, category: "accommodation", amount: Money(euros: 250), tick: second)

        XCTAssertEqual(ledger.dailyTotals.count, 2)
        XCTAssertEqual(ledger.trailingRevenue(days: 1), Money(euros: 250))
        XCTAssertEqual(ledger.trailingRevenue(days: 2), Money(euros: 350))
    }

    func testEntriesAreCapped() {
        var ledger = Ledger()
        ledger.entryLimit = 50
        for index in 0..<200 {
            ledger.record(.revenue, category: "food", amount: Money(cents: 100), tick: index)
        }
        XCTAssertEqual(ledger.entries.count, 50)
        // Aggregates keep the full picture even though individual entries are dropped.
        XCTAssertEqual(ledger.lifetimeRevenue, Money(cents: 20_000))
    }

    func testZeroAmountsAreIgnored() {
        var ledger = Ledger()
        ledger.record(.revenue, category: "food", amount: .zero, tick: 0)
        XCTAssertTrue(ledger.entries.isEmpty)
    }
}

final class WorldEconomyTests: XCTestCase {

    func testEarningAndSpendingMoveCashAndBooks() throws {
        var world = try TestFixtures.demoPark()
        let openingCash = world.cash
        // The demo park is *built* through the ledger, so it already carries construction costs.
        // Measure the movement, not the absolute totals.
        let openingRevenue = world.ledger.lifetimeRevenue
        let openingExpenses = world.ledger.lifetimeExpenses

        world.earn(Money(euros: 250), category: .food)
        world.spend(Money(euros: 100), category: .wages)

        XCTAssertEqual(world.cash.cents, openingCash.cents + 25_000 - 10_000)
        XCTAssertEqual(world.ledger.lifetimeRevenue.cents - openingRevenue.cents, 25_000)
        XCTAssertEqual(world.ledger.lifetimeExpenses.cents - openingExpenses.cents, 10_000)
    }

    func testCashIsAlwaysOpeningPlusRevenueMinusExpenses() throws {
        let world = try GameSetup.newGame(scenarioID: "career-nl-1", catalog: TestFixtures.catalog)
        let opening = world.cash
        let engine = SimulationEngine(world: world)
        engine.run(ticks: 14 * GameDate.minutesPerDay)

        // Loan principal repayment is the one cash movement that is not a ledger expense, and this
        // scenario takes no loans — so the books must reconcile exactly.
        let expected = opening.cents
            + engine.world.ledger.lifetimeRevenue.cents
            - engine.world.ledger.lifetimeExpenses.cents
        XCTAssertEqual(engine.world.cash.cents, expected, "the books must reconcile to the cent")
    }

    func testDailySettlementChargesRunningCosts() throws {
        let engine = try TestFixtures.demoEngine()
        let opening = engine.world.cash
        engine.run(ticks: 3 * GameDate.minutesPerDay)

        XCTAssertGreaterThan(engine.world.ledger.lifetimeExpenses.cents, 0)
        let wages = engine.world.ledger.dailyTotals.reduce(0) {
            $0 + ($1.expenseByCategory[ExpenseCategory.wages.rawValue] ?? 0)
        }
        XCTAssertGreaterThan(wages, 0, "staff must be paid")
        let electricity = engine.world.ledger.dailyTotals.reduce(0) {
            $0 + ($1.expenseByCategory[ExpenseCategory.electricity.rawValue] ?? 0)
        }
        XCTAssertGreaterThan(electricity, 0, "the lights are on")
        XCTAssertLessThan(engine.world.cash.cents, opening.cents + 1, "an empty park loses money")
    }

    func testHarderDifficultyCostsMore() throws {
        func expensesAfterAWeek(_ difficulty: Difficulty) throws -> Int {
            var world = try TestFixtures.demoPark()
            world.difficulty = difficulty
            let engine = SimulationEngine(world: world)
            engine.run(ticks: 5 * GameDate.minutesPerDay)
            return engine.world.ledger.lifetimeExpenses.cents
        }
        XCTAssertGreaterThan(try expensesAfterAWeek(.hard), try expensesAfterAWeek(.relaxed))
    }

    func testLoanAddsCashAndAccruesInterest() throws {
        var world = try TestFixtures.demoPark()
        let opening = world.cash
        XCTAssertTrue(EconomySystem.takeLoan(amount: Money(euros: 100_000), termDays: 365, world: &world))
        XCTAssertEqual(world.cash.cents, opening.cents + 10_000_000)
        XCTAssertEqual(world.loans.count, 1)

        let engine = SimulationEngine(world: world)
        engine.run(ticks: 5 * GameDate.minutesPerDay)
        let interest = engine.world.ledger.dailyTotals.reduce(0) {
            $0 + ($1.expenseByCategory[ExpenseCategory.interest.rawValue] ?? 0)
        }
        XCTAssertGreaterThan(interest, 0, "borrowed money costs interest")
        XCTAssertLessThan(engine.world.loans[0].outstanding.cents, 10_000_000, "the loan is being repaid")
    }

    func testNetWorthCountsBuildingsAndDebt() throws {
        var world = try TestFixtures.demoPark()
        let withoutDebt = world.netWorth
        EconomySystem.takeLoan(amount: Money(euros: 50_000), termDays: 365, world: &world)
        // Borrowing adds cash and an equal liability, so net worth should barely move.
        XCTAssertEqual(world.netWorth.cents, withoutDebt.cents, accuracy: 100)
        XCTAssertGreaterThan(withoutDebt.cents, world.cash.cents, "buildings are worth something")
    }

    func testDifficultyNeverPenalisesTheStartingPositionUnfairly() {
        XCTAssertGreaterThan(Difficulty.relaxed.startingCash, Difficulty.hard.startingCash)
        XCTAssertGreaterThan(Difficulty.relaxed.demandMultiplier, Difficulty.hard.demandMultiplier)
        XCTAssertLessThan(Difficulty.relaxed.operatingCostMultiplier, Difficulty.hard.operatingCostMultiplier)
    }
}
