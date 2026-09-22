import SwiftUI
import ParkLifeCore

/// The persistent status bar: money, date, weather, occupancy, guests, rating and alerts.
struct HUDView: View {

    @EnvironmentObject private var session: GameSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showingDebugMenu: Bool

    /// iPad has room for the full set of figures on one line; a phone does not.
    private var isWide: Bool { sizeClass == .regular }

    var body: some View {
        if let hud = session.snapshot?.hud {
            VStack(spacing: 6) {
                // A VStack is as wide as its widest child, and this bar was it: with the figures
                // and six speed buttons on one line it demanded roughly 470pt against a phone's
                // ~378pt. The whole overlay column then took that width and was centred, clipping
                // the inspector and the navigation bar off both edges along with the HUD. On a
                // narrow screen the two halves get a line each instead.
                Group {
                    if isWide {
                        HStack(spacing: 10) {
                            statistics(hud)
                            Spacer(minLength: 4)
                            speedControls
                        }
                    } else {
                        VStack(spacing: 6) {
                            HStack(spacing: 10) {
                                statistics(hud)
                                Spacer(minLength: 4)
                            }
                            HStack(spacing: 10) {
                                Spacer(minLength: 0)
                                speedControls
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Label(dateText(hud.date), systemImage: "calendar")
                    Divider().frame(height: 18)
                    Label(
                        "\(Int(hud.temperature.rounded()))°C  \(NSLocalizedString(hud.weather.localizationKey, comment: ""))",
                        systemImage: weatherSymbol(hud.weather)
                    )
                    Spacer(minLength: 0)
                    Label("\(hud.arrivalsToday)", systemImage: "arrow.down.to.line")
                        .accessibilityLabel(Text(NSLocalizedString("hud.arrivalsToday", comment: "")))
                    Label("\(hud.departuresToday)", systemImage: "arrow.up.to.line")
                        .accessibilityLabel(Text(NSLocalizedString("hud.departuresToday", comment: "")))
                    if hud.unitsDirty > 0 {
                        Label("\(hud.unitsDirty)", systemImage: "sparkles")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text(NSLocalizedString("hud.awaitingCleaning", comment: "")))
                    }
                }
                .font(.caption)
                // Shrink rather than run off the edge: the date and weather strings are
                // localised and their length is not something this layout can assume.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
            .padding(.top, 6)
        }
    }

    /// The figures themselves. Guests and rating are dropped on a phone: a narrow bar needs
    /// fewer figures, not smaller ones.
    @ViewBuilder
    private func statistics(_ hud: WorldSnapshot.HUD) -> some View {
        statistic(
            symbol: "eurosign.circle.fill",
            value: hud.cash.compactDescription,
            label: NSLocalizedString("hud.cash", comment: ""),
            tint: hud.cash.isNegative ? .red : .primary
        )
        if isWide {
            Divider().frame(height: 26)
            statistic(
                symbol: "person.3.fill",
                value: "\(hud.guestsOnSite)",
                label: NSLocalizedString("hud.guests", comment: "")
            )
        }
        Divider().frame(height: 26)
        statistic(
            symbol: "bed.double.fill",
            value: "\(hud.occupancyPercent)%",
            label: NSLocalizedString("hud.occupancy", comment: "")
        )
        if isWide {
            Divider().frame(height: 26)
            statistic(
                symbol: "star.fill",
                value: String(format: "%.1f", hud.reputationStars),
                label: NSLocalizedString("hud.rating", comment: "")
            )
        }
    }

    private var speedControls: some View {
        HStack(spacing: isWide ? 6 : 4) {
            ForEach(GameSpeed.allCases, id: \.self) { speed in
                Button {
                    session.submit(.setSpeed(speed))
                } label: {
                    Text(speed.displayLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(minWidth: isWide ? 34 : 28, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .tint(session.speed == speed ? .accentColor : .secondary)
                .accessibilityLabel(Text(NSLocalizedString(speed.localizationKey, comment: "")))
            }
            #if DEBUG
            Button {
                showingDebugMenu = true
            } label: {
                Image(systemName: "ladybug")
                    .frame(minWidth: isWide ? 34 : 28, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text(NSLocalizedString("debug.title", comment: "")))
            #endif
        }
    }

    /// One HUD figure and its caption.
    ///
    /// `lineLimit(1)` is load-bearing, not cosmetic: without it a long value with no spaces in
    /// it — a seven-figure cash balance — is wrapped one character per line when the bar runs
    /// short of width, and the whole HUD becomes unreadable.
    ///
    /// It deliberately does *not* use `fixedSize(horizontal:)` to achieve that. Doing so pushes
    /// an oversized ideal width up through the shared overlay stack, which on a phone shifted the
    /// entire UI sideways and clipped the inspector and the navigation bar along with the HUD.
    /// Shrinking the text is the correct escape valve; demanding more room than exists is not.
    private func statistic(symbol: String, value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(value, systemImage: symbol)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    private func dateText(_ date: GameDate) -> String {
        String(
            format: NSLocalizedString("hud.dateFormat", comment: ""),
            NSLocalizedString(date.weekday.localizationKey, comment: ""),
            date.dayOfMonth,
            NSLocalizedString("month.\(date.month)", comment: ""),
            date.gameYear,
            date.hour,
            date.minute
        )
    }

    private func weatherSymbol(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .cloudy: return "cloud"
        case .lightRain: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .storm: return "cloud.bolt.rain"
        case .fog: return "cloud.fog"
        case .snow: return "cloud.snow"
        }
    }
}
