import SwiftUI
import ParkLifeCore

// MARK: - Finances

struct FinancePanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                Section(NSLocalizedString("finance.position", comment: "")) {
                    LabeledContent(NSLocalizedString("finance.cash", comment: ""), value: world.cash.description)
                    LabeledContent(NSLocalizedString("finance.netWorth", comment: ""), value: world.netWorth.description)
                    LabeledContent(
                        NSLocalizedString("finance.debt", comment: ""),
                        value: Money(cents: world.loans.reduce(0) { $0 + $1.outstanding.cents }).description
                    )
                    LabeledContent(
                        NSLocalizedString("finance.profit7", comment: ""),
                        value: world.ledger.trailingProfit(days: 7).description
                    )
                    LabeledContent(
                        NSLocalizedString("finance.revenue30", comment: ""),
                        value: world.ledger.trailingRevenue(days: 30).description
                    )
                }

                Section(NSLocalizedString("finance.profitTrend", comment: "")) {
                    SparklineView(
                        values: world.statistics.dailySeries(.profit)?.recent(30) ?? [],
                        positiveIsGood: true
                    )
                    .frame(height: 70)
                    .accessibilityLabel(Text(NSLocalizedString("finance.profitTrend", comment: "")))
                }

                if let yesterday = world.ledger.totals(forDay: world.date.dayIndex - 1) {
                    Section(NSLocalizedString("finance.yesterdayRevenue", comment: "")) {
                        ForEach(RevenueCategory.allCases, id: \.self) { category in
                            let amount = yesterday.revenueByCategory[category.rawValue] ?? 0
                            if amount > 0 {
                                LabeledContent(
                                    NSLocalizedString(category.localizationKey, comment: ""),
                                    value: Money(cents: amount).description
                                )
                            }
                        }
                    }
                    Section(NSLocalizedString("finance.yesterdayExpenses", comment: "")) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { category in
                            let amount = yesterday.expenseByCategory[category.rawValue] ?? 0
                            if amount > 0 {
                                LabeledContent(
                                    NSLocalizedString(category.localizationKey, comment: ""),
                                    value: Money(cents: amount).description
                                )
                            }
                        }
                    }
                }

                Section(NSLocalizedString("finance.pricing", comment: "")) {
                    VStack(alignment: .leading) {
                        Text(
                            String(
                                format: NSLocalizedString("finance.accommodationMultiplier", comment: ""),
                                world.pricing.accommodationMultiplier
                            )
                        )
                        .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { world.pricing.accommodationMultiplier },
                                set: { session.submit(.setAccommodationMultiplier($0)) }
                            ),
                            in: 0.5...2.0,
                            step: 0.05
                        )
                    }
                    Toggle(
                        NSLocalizedString("finance.seasonalPricing", comment: ""),
                        isOn: Binding(
                            get: { world.pricing.seasonalPricingEnabled },
                            set: { session.submit(.setSeasonalPricing($0)) }
                        )
                    )
                    VStack(alignment: .leading) {
                        Text(
                            String(
                                format: NSLocalizedString("finance.lastMinuteDiscount", comment: ""),
                                Int(world.pricing.lastMinuteDiscount * 100)
                            )
                        )
                        .font(.subheadline)
                        Slider(
                            value: Binding(
                                get: { world.pricing.lastMinuteDiscount },
                                set: { session.submit(.setLastMinuteDiscount($0)) }
                            ),
                            in: 0...0.4,
                            step: 0.05
                        )
                    }
                }

                Section(NSLocalizedString("finance.borrowing", comment: "")) {
                    ForEach([50_000, 150_000, 400_000], id: \.self) { amount in
                        Button {
                            session.submit(.takeLoan(amount: Money(euros: amount), termDays: 365 * 3))
                        } label: {
                            Label(
                                String(
                                    format: NSLocalizedString("finance.borrow", comment: ""),
                                    Money(euros: amount).description
                                ),
                                systemImage: "banknote"
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Reservations

struct ReservationsPanel: View {

    @EnvironmentObject private var session: GameSession

    var body: some View {
        List {
            if let world = session.world {
                let today = world.date.dayIndex

                Section(NSLocalizedString("reservations.occupancy", comment: "")) {
                    OccupancyCalendarView(world: world)
                        .frame(height: 96)
                }

                Section(NSLocalizedString("reservations.forecast", comment: "")) {
                    SparklineView(
                        values: ReservationSystem.revenueForecast(days: 21, from: today, in: world).map(\.euroValue),
                        positiveIsGood: true
                    )
                    .frame(height: 60)
                }

                Section(NSLocalizedString("reservations.arrivalsToday", comment: "")) {
                    let arrivals = ReservationSystem.arrivals(on: today, in: world)
                    if arrivals.isEmpty {
                        Text(NSLocalizedString("reservations.none", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(arrivals, id: \.id.raw) { reservation in
                            reservationRow(reservation, world: world)
                        }
                    }
                }

                Section(NSLocalizedString("reservations.departuresToday", comment: "")) {
                    let departures = ReservationSystem.departures(on: today, in: world)
                    if departures.isEmpty {
                        Text(NSLocalizedString("reservations.none", comment: ""))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(departures, id: \.id.raw) { reservation in
                            reservationRow(reservation, world: world)
                        }
                    }
                }

                Section(NSLocalizedString("reservations.upcoming", comment: "")) {
                    let upcoming = world.reservations.items
                        .filter { $0.status.holdsUnit && $0.arrival.dayIndex > today }
                        .sorted { $0.arrival.minutesSinceEpoch < $1.arrival.minutesSinceEpoch }
                        .prefix(25)
                    ForEach(Array(upcoming), id: \.id.raw) { reservation in
                        reservationRow(reservation, world: world)
                    }
                }
            }
        }
    }

    private func reservationRow(_ reservation: Reservation, world: World) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(unitName(reservation, world: world))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(reservation.totalPrice.description)
                    .font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 8) {
                Text(
                    String(
                        format: NSLocalizedString("reservations.party", comment: ""),
                        reservation.adults, reservation.children
                    )
                )
                Text("·")
                Text(String(format: NSLocalizedString("reservations.nights", comment: ""), reservation.nights))
                Text("·")
                Text(NSLocalizedString(reservation.status.localizationKey, comment: ""))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func unitName(_ reservation: Reservation, world: World) -> String {
        guard let unit = reservation.unitBuildingID,
              let definition = world.definition(ofBuilding: unit) else {
            return NSLocalizedString("reservations.unassigned", comment: "")
        }
        return NSLocalizedString(definition.nameKey, comment: "") + " #\(unit.raw)"
    }
}

/// Four weeks of occupancy at a glance.
struct OccupancyCalendarView: View {

    let world: World

    var body: some View {
        let today = world.date.dayIndex
        let units = max(1, world.index.accommodationIDs.count)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<4, id: \.self) { week in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { day in
                        let dayIndex = today + week * 7 + day
                        let occupied = ReservationSystem.occupiedUnits(on: dayIndex, in: world)
                        let ratio = Double(occupied) / Double(units)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colour(for: ratio))
                            .frame(height: 16)
                            .overlay(
                                Text("\(Int((ratio * 100).rounded()))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                            .accessibilityLabel(
                                Text(
                                    String(
                                        format: NSLocalizedString("reservations.occupancyDay", comment: ""),
                                        occupied, units
                                    )
                                )
                            )
                    }
                }
            }
        }
    }

    private func colour(for ratio: Double) -> Color {
        Color(hue: 0.33 * min(max(ratio, 0), 1), saturation: 0.6, brightness: 0.45 + 0.3 * ratio)
    }
}

// MARK: - Statistics

struct StatisticsPanel: View {

    @EnvironmentObject private var session: GameSession

    private let metrics: [StatisticMetric] = [
        .occupancy, .revenue, .expenses, .profit, .satisfaction, .reviewScore,
        .guestsOnSite, .energyKWh, .waterLitres, .staffCount
    ]

    var body: some View {
        List {
            if let world = session.world {
                ForEach(metrics, id: \.self) { metric in
                    Section(NSLocalizedString(metric.localizationKey, comment: "")) {
                        let values = world.statistics.dailySeries(metric)?.recent(30) ?? []
                        if values.isEmpty {
                            Text(NSLocalizedString("statistics.noData", comment: ""))
                                .foregroundStyle(.secondary)
                        } else {
                            SparklineView(values: values, positiveIsGood: metric != .expenses)
                                .frame(height: 60)
                            LabeledContent(
                                NSLocalizedString("statistics.latest", comment: ""),
                                value: String(format: "%.1f", values.last ?? 0)
                            )
                        }
                    }
                }

                Section(NSLocalizedString("statistics.lifetime", comment: "")) {
                    LabeledContent(
                        NSLocalizedString("statistics.guestsHosted", comment: ""),
                        value: "\(world.statistics.totalGuestsHosted)"
                    )
                    LabeledContent(
                        NSLocalizedString("statistics.nightsSold", comment: ""),
                        value: "\(world.statistics.totalNightsSold)"
                    )
                    LabeledContent(
                        NSLocalizedString("statistics.reviews", comment: ""),
                        value: "\(world.statistics.totalReviews)"
                    )
                }
            }
        }
    }
}

/// A tiny line chart. Written by hand so the app has no chart dependency and works on any
/// deployment target we support.
struct SparklineView: View {

    let values: [Double]
    let positiveIsGood: Bool

    var body: some View {
        GeometryReader { proxy in
            let minimum = values.min() ?? 0
            let maximum = values.max() ?? 1
            let span = maximum - minimum
            let safeSpan = span == 0 ? 1 : span

            ZStack {
                if minimum < 0 && maximum > 0 {
                    let zeroY = proxy.size.height * (1 - (0 - minimum) / safeSpan)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: zeroY))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: zeroY))
                    }
                    .stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = values.count > 1
                            ? proxy.size.width * Double(index) / Double(values.count - 1)
                            : proxy.size.width / 2
                        let y = proxy.size.height * (1 - (value - minimum) / safeSpan)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColour, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
    }

    private var lineColour: Color {
        guard let first = values.first, let last = values.last, values.count > 1 else { return .accentColor }
        let improving = last >= first
        return (improving == positiveIsGood) ? .green : .orange
    }
}
