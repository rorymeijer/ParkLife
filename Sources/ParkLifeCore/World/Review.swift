import Foundation

public struct ReviewCategoryScore: Codable, Hashable {
    public let category: ReviewCategory
    /// 1–5 stars.
    public let stars: Double

    public init(category: ReviewCategory, stars: Double) {
        self.category = category
        self.stars = stars
    }
}

/// A review written at checkout, derived entirely from what actually happened during the stay.
public struct Review: StoredEntity, Codable {

    public typealias Identifier = ReviewID

    public let id: ReviewID
    public var groupID: GroupID
    public var archetypeID: String
    public var tick: Tick
    public var overallStars: Double
    public var categoryScores: [ReviewCategoryScore]
    /// Localisation keys for the highlights, strongest first. Never a random phrase bank.
    public var positiveKeys: [String]
    public var negativeKeys: [String]
    public var nights: Int
    public var partySize: Int

    public init(
        id: ReviewID,
        groupID: GroupID,
        archetypeID: String,
        tick: Tick,
        overallStars: Double,
        categoryScores: [ReviewCategoryScore],
        positiveKeys: [String],
        negativeKeys: [String],
        nights: Int,
        partySize: Int
    ) {
        self.id = id
        self.groupID = groupID
        self.archetypeID = archetypeID
        self.tick = tick
        self.overallStars = overallStars
        self.categoryScores = categoryScores
        self.positiveKeys = positiveKeys
        self.negativeKeys = negativeKeys
        self.nights = nights
        self.partySize = partySize
    }

    public func stars(for category: ReviewCategory) -> Double? {
        categoryScores.first(where: { $0.category == category })?.stars
    }

    /// Assembled sentence keys the UI renders in order.
    public var bodyKeys: [String] {
        var keys: [String] = []
        keys.append(contentsOf: positiveKeys.prefix(2))
        keys.append(contentsOf: negativeKeys.prefix(2))
        if keys.isEmpty {
            keys.append(overallStars >= 3.5 ? "review.neutralPositive" : "review.neutralNegative")
        }
        return keys
    }
}
