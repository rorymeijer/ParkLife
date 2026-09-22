import SwiftUI
import ParkLifeCore

/// Development tools.
///
/// Compiled into DEBUG builds only — the whole view is wrapped in `#if DEBUG`, and the button that
/// opens it is too, so nothing here ships in a release build (brief §46).
#if DEBUG
struct DebugMenuView: View {

    @EnvironmentObject private var session: GameSession
    @State private var fastForwardDays = 7

    var body: some View {
        List {
            Section(NSLocalizedString("debug.money", comment: "")) {
                ForEach([10_000, 100_000, 1_000_000], id: \.self) { amount in
                    Button {
                        session.debugAddMoney(Money(euros: amount))
                    } label: {
                        Label(Money(euros: amount).description, systemImage: "plus.circle")
                    }
                }
            }

            Section(NSLocalizedString("debug.time", comment: "")) {
                Stepper(
                    String(format: NSLocalizedString("debug.fastForwardDays", comment: ""), fastForwardDays),
                    value: $fastForwardDays,
                    in: 1...60
                )
                Button {
                    session.debugRun(ticks: fastForwardDays * GameDate.minutesPerDay)
                } label: {
                    Label(NSLocalizedString("debug.fastForward", comment: ""), systemImage: "forward.end")
                }
                Button {
                    session.debugRun(ticks: 60)
                } label: {
                    Label(NSLocalizedString("debug.advanceHour", comment: ""), systemImage: "forward")
                }
            }

            Section(NSLocalizedString("debug.weather", comment: "")) {
                ForEach(WeatherCondition.allCases, id: \.self) { condition in
                    Button {
                        session.debugSetWeather(condition)
                    } label: {
                        Text(NSLocalizedString(condition.localizationKey, comment: ""))
                    }
                }
            }

            Section(NSLocalizedString("debug.simulation", comment: "")) {
                Button {
                    session.debugBreakRandomBuilding()
                } label: {
                    Label(NSLocalizedString("debug.breakBuilding", comment: ""), systemImage: "wrench.and.screwdriver")
                }
                Button {
                    session.debugSetReputation(0.9)
                } label: {
                    Label(NSLocalizedString("debug.raiseReputation", comment: ""), systemImage: "star")
                }
                Button {
                    session.debugSetReputation(0.2)
                } label: {
                    Label(NSLocalizedString("debug.lowerReputation", comment: ""), systemImage: "star.slash")
                }
                Button {
                    session.debugDirtyAllUnits()
                } label: {
                    Label(NSLocalizedString("debug.dirtyUnits", comment: ""), systemImage: "sparkles")
                }
            }

            Section(NSLocalizedString("debug.diagnostics", comment: "")) {
                ForEach(session.debugDiagnostics(), id: \.0) { item in
                    LabeledContent(item.0, value: item.1)
                }
            }
        }
        .navigationTitle(Text(NSLocalizedString("debug.title", comment: "")))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension GameSession {

    func debugAddMoney(_ amount: Money) {
        engine?.debugMutate { world in
            world.cash += amount
        }
        refreshSnapshot()
    }

    func debugRun(ticks: Int) {
        engine?.run(ticks: ticks)
        refreshSnapshot()
    }

    func debugSetWeather(_ condition: WeatherCondition) {
        engine?.debugMutate { world in
            world.weather.condition = condition
        }
        refreshSnapshot()
    }

    func debugSetReputation(_ value: Double) {
        engine?.debugMutate { world in
            world.reputation.overall = value
        }
        refreshSnapshot()
    }

    func debugBreakRandomBuilding() {
        engine?.debugMutate { world in
            guard let id = world.index.facilityIDs.first else { return }
            world.buildings.modify(id) { $0.condition = 0.1 }
        }
        refreshSnapshot()
    }

    func debugDirtyAllUnits() {
        engine?.debugMutate { world in
            for id in world.index.accommodationIDs {
                world.buildings.modify(id) { building in
                    if building.accommodation?.state == .ready {
                        building.accommodation?.state = .dirty
                        building.accommodation?.cleanliness = 0.2
                    }
                }
            }
        }
        refreshSnapshot()
    }

    func debugDiagnostics() -> [(String, String)] {
        guard let engine, let world = self.world else { return [] }
        return [
            ("Tick", "\(world.clock.tick)"),
            ("Date", world.date.description),
            ("Guests", "\(world.guests.count)"),
            ("Active parties", "\(world.activeGroupIDs.count)"),
            ("Reservations", "\(world.reservations.count)"),
            ("Buildings", "\(world.buildings.count)"),
            ("Walkable tiles", "\(world.navigation.network.walkableCount)"),
            ("Path components", "\(world.navigation.network.componentCount)"),
            ("Flow fields", "\(world.navigation.registeredDestinations.count)"),
            ("Queued path requests", "\(world.navigation.pendingRequestCount)"),
            ("Scheduled wake-ups", "\(world.schedule.count)"),
            ("Ticks run", "\(engine.totalTicksRun)"),
            ("Last tick (ms)", String(format: "%.3f", engine.lastTickDurationSeconds * 1_000))
        ]
    }
}
#endif
