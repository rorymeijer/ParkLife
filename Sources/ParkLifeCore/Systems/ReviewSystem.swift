import Foundation

/// Turns a completed stay into a review.
///
/// The score is the sum of what actually happened, and the text is assembled from the strongest
/// real moments — there is no phrase bank and no random star rating (brief §26).
public enum ReviewSystem: SimulationSystem {

    public static let systemName = "Reviews"

    public static func update(world: inout World, context: inout TickContext) {
        var checkedOut: [GroupID] = []
        for event in context.events {
            if case .groupCheckedOut(let groupID) = event {
                checkedOut.append(groupID)
            }
        }
        for groupID in checkedOut {
            writeReview(groupID: groupID, world: &world, context: &context)
        }
    }

    private static func writeReview(groupID: GroupID, world: inout World, context: inout TickContext) {
        guard let group = world.groups[groupID] else { return }

        var scores: [ReviewCategoryScore] = []
        var weightedTotal = 0.0
        var weightSum = 0.0
        for category in ReviewCategory.allCases {
            let stars = group.score(for: category)
            // Only categories the party actually experienced are rated.
            guard group.moments.contains(where: { $0.category == category }) else { continue }
            scores.append(ReviewCategoryScore(category: category, stars: stars))
            let weight = group.weight(for: category)
            weightedTotal += stars * weight
            weightSum += weight
        }

        let overall = weightSum > 0 ? clamp(weightedTotal / weightSum, 1.0, 5.0) : 3.0

        // Highlights: the strongest moments, aggregated by reason so one bad meal does not fill
        // the whole review.
        var byReason: [String: Double] = [:]
        for moment in group.moments {
            byReason[moment.reasonKey, default: 0] += moment.delta
        }
        let positives = byReason.filter { $0.value > 0.2 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)
        let negatives = byReason.filter { $0.value < -0.2 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)

        let review = Review(
            id: world.ids.next(ReviewID.self),
            groupID: groupID,
            archetypeID: group.archetypeID,
            tick: context.tick,
            overallStars: overall,
            categoryScores: scores,
            positiveKeys: Array(positives.prefix(3)),
            negativeKeys: Array(negatives.prefix(3)),
            nights: group.arrivalDate.nights(until: group.departureDate),
            partySize: group.memberIDs.count
        )
        world.record(review: review)
        context.emit(.reviewPosted(review.id, overall))
        ParkLog.shared.debug(.guest, "Review from group \(groupID): \(String(format: "%.1f", overall))★")
    }
}
