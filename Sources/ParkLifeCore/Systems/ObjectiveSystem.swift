import Foundation

/// Where an objective currently stands.
public struct ObjectiveStatus {
    public let definition: ObjectiveDefinition
    public let currentValue: Double
    public let isMetNow: Bool
    public let sustainedDays: Int
    public let isComplete: Bool

    /// Progress toward the target, `0...1`, for a progress bar.
    public var progress: Double {
        guard definition.target != 0 else { return isComplete ? 1 : 0 }
        switch definition.comparison {
        case .atLeast:
            return clamp01(currentValue / definition.target)
        case .atMost:
            return currentValue <= definition.target ? 1 : clamp01(definition.target / max(currentValue, 0.0001))
        }
    }
}

/// Evaluates data-driven objectives.
///
/// Objectives are `ObjectiveDefinition` rows from scenario JSON; nothing about a specific goal is
/// hardcoded here or in the UI (brief §33).
public enum ObjectiveSystem: SimulationSystem {

    public static let systemName = "Objectives"

    public static func update(world: inout World, context: inout TickContext) {
        guard context.isNewDay else { return }
        guard let scenarioID = world.scenarioID,
              let scenario = world.catalog.scenarios[scenarioID] else { return }

        for objective in scenario.objectives {
            let value = measure(objective.metric, in: world)
            let met = isMet(objective, value: value)
            let current = world.bookkeeping.objectiveSustainedDays[objective.id] ?? 0
            world.bookkeeping.objectiveSustainedDays[objective.id] = met ? current + 1 : 0
        }
    }

    public static func statuses(in world: World) -> [ObjectiveStatus] {
        guard let scenarioID = world.scenarioID,
              let scenario = world.catalog.scenarios[scenarioID] else { return [] }
        return scenario.objectives.map { objective in
            let value = measure(objective.metric, in: world)
            let met = isMet(objective, value: value)
            let sustained = world.bookkeeping.objectiveSustainedDays[objective.id] ?? 0
            return ObjectiveStatus(
                definition: objective,
                currentValue: value,
                isMetNow: met,
                sustainedDays: sustained,
                isComplete: met && sustained >= objective.sustainedDays
            )
        }
    }

    public static func allComplete(in world: World) -> Bool {
        let all = statuses(in: world)
        return !all.isEmpty && all.allSatisfy(\.isComplete)
    }

    public static func measure(_ metric: ObjectiveDefinition.Metric, in world: World) -> Double {
        switch metric {
        case .cash:
            return world.cash.euroValue
        case .annualRevenue:
            return StatisticsSystem.annualRevenue(in: world).euroValue
        case .occupancyPercent:
            return world.occupancyRate * 100
        case .guestSatisfaction:
            return world.reputation.guestSatisfaction
        case .reviewScore:
            return world.reputation.averageReviewStars
        case .totalGuestsHosted:
            return Double(world.statistics.totalGuestsHosted)
        case .consecutiveProfitableMonths:
            return Double(world.bookkeeping.consecutiveProfitableMonths)
        case .reputation:
            return world.reputation.overall
        case .sustainabilityRating:
            return world.reputation.sustainability
        }
    }

    private static func isMet(_ objective: ObjectiveDefinition, value: Double) -> Bool {
        switch objective.comparison {
        case .atLeast: return value >= objective.target
        case .atMost: return value <= objective.target
        }
    }
}
