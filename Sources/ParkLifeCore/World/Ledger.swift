import Foundation

public enum TransactionKind: String, Codable {
    case revenue
    case expense
}

public struct LedgerEntry: Codable {

    public var tick: Tick
    public var kind: TransactionKind
    /// Raw value of either a `RevenueCategory` or an `ExpenseCategory`.
    public var category: String
    /// Always positive; `kind` carries the sign.
    public var amount: Money
    /// Optional entity the transaction relates to (usually a building).
    public var reference: UInt32?

    public init(tick: Tick, kind: TransactionKind, category: String, amount: Money, reference: UInt32?) {
        self.tick = tick
        self.kind = kind
        self.category = category
        self.amount = amount
        self.reference = reference
    }

    public var signedAmount: Money {
        kind == .revenue ? amount : Money(cents: -amount.cents)
    }
}

/// A single period's totals, pre-aggregated.
public struct PeriodTotals: Codable {

    public var periodIndex: Int
    public var revenueByCategory: [String: Int]
    public var expenseByCategory: [String: Int]

    public init(periodIndex: Int) {
        self.periodIndex = periodIndex
        self.revenueByCategory = [:]
        self.expenseByCategory = [:]
    }

    public var revenue: Money {
        Money(cents: revenueByCategory.values.reduce(0, +))
    }

    public var expenses: Money {
        Money(cents: expenseByCategory.values.reduce(0, +))
    }

    public var profit: Money {
        Money(cents: revenue.cents - expenses.cents)
    }

    public mutating func add(_ entry: LedgerEntry) {
        switch entry.kind {
        case .revenue:
            revenueByCategory[entry.category, default: 0] += entry.amount.cents
        case .expense:
            expenseByCategory[entry.category, default: 0] += entry.amount.cents
        }
    }
}

/// The company books.
///
/// Aggregates are maintained incrementally as transactions arrive. Dashboards read the
/// aggregates; nothing ever rescans the entry history to draw a chart (brief §37).
public struct Ledger: Codable {

    /// Recent entries, newest last. Capped — long-term history lives in the aggregates.
    public private(set) var entries: [LedgerEntry]
    public private(set) var dailyTotals: [PeriodTotals]
    public private(set) var weeklyTotals: [PeriodTotals]
    public private(set) var monthlyTotals: [PeriodTotals]

    public private(set) var lifetimeRevenue: Money
    public private(set) var lifetimeExpenses: Money

    public var entryLimit: Int = 5_000
    public var dailyLimit: Int = 800
    public var weeklyLimit: Int = 260
    public var monthlyLimit: Int = 240

    public init() {
        self.entries = []
        self.dailyTotals = []
        self.weeklyTotals = []
        self.monthlyTotals = []
        self.lifetimeRevenue = .zero
        self.lifetimeExpenses = .zero
    }

    public mutating func record(
        _ kind: TransactionKind,
        category: String,
        amount: Money,
        tick: Tick,
        reference: UInt32? = nil
    ) {
        guard amount.cents > 0 else { return }
        let entry = LedgerEntry(tick: tick, kind: kind, category: category, amount: amount, reference: reference)
        entries.append(entry)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }

        switch kind {
        case .revenue: lifetimeRevenue += amount
        case .expense: lifetimeExpenses += amount
        }

        let date = GameDate(minutesSinceEpoch: tick)
        append(entry, to: &dailyTotals, periodIndex: date.dayIndex, limit: dailyLimit)
        append(entry, to: &weeklyTotals, periodIndex: date.weekIndex, limit: weeklyLimit)
        append(entry, to: &monthlyTotals, periodIndex: date.monthIndex, limit: monthlyLimit)
    }

    private func append(_ entry: LedgerEntry, to totals: inout [PeriodTotals], periodIndex: Int, limit: Int) {
        if let last = totals.last, last.periodIndex == periodIndex {
            totals[totals.count - 1].add(entry)
        } else {
            var period = PeriodTotals(periodIndex: periodIndex)
            period.add(entry)
            totals.append(period)
            if totals.count > limit {
                totals.removeFirst(totals.count - limit)
            }
        }
    }

    public func totals(forDay dayIndex: Int) -> PeriodTotals? {
        dailyTotals.last(where: { $0.periodIndex == dayIndex })
    }

    public var lifetimeProfit: Money {
        Money(cents: lifetimeRevenue.cents - lifetimeExpenses.cents)
    }

    /// Profit over the most recent `days` complete daily buckets.
    public func trailingProfit(days: Int) -> Money {
        let recent = dailyTotals.suffix(days)
        return Money(cents: recent.reduce(0) { $0 + $1.profit.cents })
    }

    public func trailingRevenue(days: Int) -> Money {
        let recent = dailyTotals.suffix(days)
        return Money(cents: recent.reduce(0) { $0 + $1.revenue.cents })
    }
}

/// A bank loan.
public struct Loan: Codable {
    public var principal: Money
    public var outstanding: Money
    /// Annual interest rate, e.g. `0.045`.
    public var annualRate: Double
    public var takenAtTick: Tick
    public var termDays: Int

    public init(principal: Money, annualRate: Double, takenAtTick: Tick, termDays: Int) {
        self.principal = principal
        self.outstanding = principal
        self.annualRate = annualRate
        self.takenAtTick = takenAtTick
        self.termDays = termDays
    }

    /// Interest accruing for one day.
    public var dailyInterest: Money {
        outstanding.scaled(by: annualRate / 365.0)
    }

    /// Straight-line principal repayment per day.
    public var dailyPrincipal: Money {
        guard termDays > 0 else { return .zero }
        return principal.scaled(by: 1.0 / Double(termDays))
    }
}
