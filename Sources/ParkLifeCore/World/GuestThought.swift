import Foundation

/// Every thought a guest can have.
///
/// Each case is produced by a *measured* condition in the simulation — see the table in
/// docs/SIMULATION.md §4. None of these are random flavour text.
public enum ThoughtKind: String, CaseIterable, Codable {
    case beautifulPark
    case cottageTooFarFromPool
    case cottageTooFarFromRestaurant
    case cottageWasDirty
    case cottageIsLovely
    case expensive
    case goodValue
    case queueTooLong
    case tooCrowded
    case notEnoughForChildren
    case nothingToDo
    case poolIsFantastic
    case foodWasGood
    case foodWasDisappointing
    case cantFindToilet
    case cantReachDestination
    case tooFarToWalk
    case lovelyWeather
    case miserableWeather
    case parkIsLittered
    case friendlyStaff
    case longWaitAtReception

    public var localizationKey: String { "thought.\(rawValue)" }

    public var isPositive: Bool {
        switch self {
        case .beautifulPark, .cottageIsLovely, .goodValue, .poolIsFantastic,
             .foodWasGood, .lovelyWeather, .friendlyStaff:
            return true
        default:
            return false
        }
    }

    /// Which part of the review this thought feeds.
    public var reviewCategory: ReviewCategory {
        switch self {
        case .beautifulPark, .cottageTooFarFromPool, .cottageTooFarFromRestaurant,
             .tooFarToWalk, .cantReachDestination:
            return .location
        case .cottageWasDirty, .parkIsLittered:
            return .cleanliness
        case .cottageIsLovely:
            return .accommodation
        case .expensive, .goodValue:
            return .value
        case .queueTooLong, .tooCrowded, .cantFindToilet, .longWaitAtReception:
            return .facilities
        case .notEnoughForChildren, .nothingToDo, .poolIsFantastic:
            return .activities
        case .foodWasGood, .foodWasDisappointing:
            return .food
        case .lovelyWeather, .miserableWeather:
            return .location
        case .friendlyStaff:
            return .staff
        }
    }
}

public struct GuestThought: Codable, Hashable {

    public var kind: ThoughtKind
    /// Strength of the feeling, `0...1`.
    public var magnitude: Double
    public var tick: Tick
    /// Optional subject (usually a `BuildingID` raw value).
    public var subject: UInt32?

    public init(kind: ThoughtKind, magnitude: Double, tick: Tick, subject: UInt32? = nil) {
        self.kind = kind
        self.magnitude = clamp01(magnitude)
        self.tick = tick
        self.subject = subject
    }

    public var localizedText: LocalizedText {
        LocalizedText(kind.localizationKey)
    }
}
