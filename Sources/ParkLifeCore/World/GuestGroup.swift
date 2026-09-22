import Foundation

public enum ReviewCategory: String, CaseIterable, Codable {
    case accommodation
    case cleanliness
    case facilities
    case food
    case staff
    case value
    case location
    case activities

    public var localizationKey: String { "reviewCategory.\(rawValue)" }
}

/// A single thing that happened during a stay and how it made the group feel.
///
/// Reviews are assembled from these, so every star in a review traces back to a real event.
public struct SatisfactionMoment: Codable, Hashable {
    public var category: ReviewCategory
    /// Signed contribution, typically `-1...1`.
    public var delta: Double
    public var reasonKey: String
    public var tick: Tick

    public init(category: ReviewCategory, delta: Double, reasonKey: String, tick: Tick) {
        self.category = category
        self.delta = delta
        self.reasonKey = reasonKey
        self.tick = tick
    }
}

public enum GroupState: String, Codable {
    case expected
    case arriving
    case checkedIn
    case checkedOut
    case cancelled
    case noShow
}

/// A travelling party. Guests act individually, but they book, pay and review together.
public struct GuestGroup: StoredEntity, Codable {

    public typealias Identifier = GroupID

    public let id: GroupID
    public var archetypeID: String
    public var memberIDs: [GuestID]
    public var reservationID: ReservationID?
    public var unitBuildingID: BuildingID?

    public var budget: Money
    public var spent: Money
    public var state: GroupState

    public var arrivalDate: GameDate
    public var departureDate: GameDate

    /// How good this group expects the holiday to be, `0...1`. Higher tiers and higher prices
    /// raise expectations, which is what stops "expensive = always bad".
    public var expectation: Double

    public var moments: [SatisfactionMoment]
    /// Weights for the overall review score, from the archetype.
    public var reviewWeights: [String: Double]

    public init(
        id: GroupID,
        archetypeID: String,
        memberIDs: [GuestID],
        budget: Money,
        arrivalDate: GameDate,
        departureDate: GameDate,
        expectation: Double,
        reviewWeights: [String: Double]
    ) {
        self.id = id
        self.archetypeID = archetypeID
        self.memberIDs = memberIDs
        self.reservationID = nil
        self.unitBuildingID = nil
        self.budget = budget
        self.spent = .zero
        self.state = .expected
        self.arrivalDate = arrivalDate
        self.departureDate = departureDate
        self.expectation = expectation
        self.moments = []
        self.reviewWeights = reviewWeights
    }

    public var size: Int { memberIDs.count }

    public var remainingBudget: Money {
        Money(cents: max(0, budget.cents - spent.cents))
    }

    public func canAfford(_ amount: Money) -> Bool {
        remainingBudget >= amount
    }

    public mutating func record(_ moment: SatisfactionMoment) {
        moments.append(moment)
        // Bounded: a two-week stay with a big group must not grow without limit.
        if moments.count > 240 {
            moments.removeFirst(moments.count - 240)
        }
    }

    /// Mean score for a category on the 1–5 star scale.
    public func score(for category: ReviewCategory) -> Double {
        var total = 3.0
        for moment in moments where moment.category == category {
            total += moment.delta
        }
        return clamp(total, 1.0, 5.0)
    }

    public func weight(for category: ReviewCategory) -> Double {
        reviewWeights[category.rawValue] ?? 1.0
    }

    /// Categories this group actually experienced (had at least one moment in).
    public var experiencedCategories: [ReviewCategory] {
        var seen: [ReviewCategory] = []
        for category in ReviewCategory.allCases {
            if moments.contains(where: { $0.category == category }) {
                seen.append(category)
            }
        }
        return seen
    }
}
