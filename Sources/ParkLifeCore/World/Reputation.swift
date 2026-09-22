import Foundation

/// Park standing, driven entirely by reviews and measured conditions.
public struct Reputation: Codable {

    /// Overall, `0...1`.
    public var overall: Double
    public var cleanliness: Double
    public var service: Double
    public var safety: Double
    public var sustainability: Double
    public var valueForMoney: Double

    /// Rolling mean review score in stars, and how many reviews it is based on.
    public var averageReviewStars: Double
    public var reviewCount: Int
    /// Rolling mean guest satisfaction while on site, `0...1`.
    public var guestSatisfaction: Double

    public init() {
        // A brand new park is an unknown quantity, not a bad one.
        self.overall = 0.5
        self.cleanliness = 0.7
        self.service = 0.6
        self.safety = 0.8
        self.sustainability = 0.5
        self.valueForMoney = 0.5
        self.averageReviewStars = 3.0
        self.reviewCount = 0
        self.guestSatisfaction = 0.7
    }

    /// Star rating shown to the player, 1–5.
    public var starRating: Double {
        clamp(1.0 + overall * 4.0, 1.0, 5.0)
    }

    /// Folds a new review in. The weight decays as the sample grows, so an established park
    /// is not whipsawed by one bad weekend, but a new park moves fast.
    public mutating func apply(review: Review) {
        let weight = clamp(1.0 / Double(max(6, min(reviewCount, 60))), 0.016, 0.18)
        averageReviewStars = movingAverage(current: averageReviewStars, sample: review.overallStars, weight: weight)
        reviewCount += 1

        let normalised = clamp01((review.overallStars - 1.0) / 4.0)
        overall = movingAverage(current: overall, sample: normalised, weight: weight)

        for score in review.categoryScores {
            let value = clamp01((score.stars - 1.0) / 4.0)
            switch score.category {
            case .cleanliness:
                cleanliness = movingAverage(current: cleanliness, sample: value, weight: weight)
            case .staff:
                service = movingAverage(current: service, sample: value, weight: weight)
            case .value:
                valueForMoney = movingAverage(current: valueForMoney, sample: value, weight: weight)
            default:
                break
            }
        }
    }

    /// Demand multiplier derived from standing. A brand new park still gets some business.
    public var demandFactor: Double {
        clamp(0.4 + 1.2 * overall, 0.4, 1.6)
    }
}
