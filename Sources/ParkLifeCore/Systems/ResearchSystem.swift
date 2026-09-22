import Foundation

/// Weekly research progress. Unlocks are data-driven: a completed project simply adds its id to
/// `completedResearch`, and the catalog filters on that.
public enum ResearchSystem: SimulationSystem {

    public static let systemName = "Research"

    public static func update(world: inout World, context: inout TickContext) {
        guard context.isNewWeek else { return }
        guard world.bookkeeping.lastResearchWeek != context.date.weekIndex else { return }
        world.bookkeeping.lastResearchWeek = context.date.weekIndex

        guard let activeID = world.activeResearchID,
              let definition = world.catalog.research[activeID] else { return }

        world.spend(definition.costPerWeek, category: .research)
        world.researchWeeksElapsed += 1

        guard world.researchWeeksElapsed >= definition.weeksRequired else { return }
        world.completedResearch.append(activeID)
        world.completedResearch.sort()
        world.activeResearchID = nil
        world.researchWeeksElapsed = 0
        context.emit(.researchCompleted(activeID))
        ParkLog.shared.info(.sim, "Research completed: \(activeID)")
    }

    /// Projects whose prerequisites are met and which are not already done.
    public static func availableProjects(in world: World) -> [ResearchDefinition] {
        let completed = Set(world.completedResearch)
        return world.catalog.research.keys.sorted()
            .compactMap { world.catalog.research[$0] }
            .filter { definition in
                !completed.contains(definition.id)
                    && definition.prerequisites.allSatisfy { completed.contains($0) }
            }
    }

    @discardableResult
    public static func start(_ id: String, in world: inout World) -> Bool {
        guard world.catalog.research[id] != nil else { return false }
        guard !world.completedResearch.contains(id) else { return false }
        world.activeResearchID = id
        world.researchWeeksElapsed = 0
        return true
    }
}
