import Foundation

/// Persistent per-system bookkeeping.
///
/// Systems themselves are stateless (they are enums of pure functions over the world), so anything
/// they need to remember between ticks lives here and is saved with the game.
public struct SimulationBookkeeping: Codable {

    public var lastDemandDay: Int
    public var lastSettlementDay: Int
    public var lastStatisticsHour: Int
    public var lastStatisticsDay: Int
    public var lastResearchWeek: Int
    /// Enquiries that could not be satisfied, per day — a direct signal that the park is
    /// undersupplied or overpriced.
    public var lostEnquiriesToday: Int
    public var lostEnquiriesPriceToday: Int
    public var arrivalsToday: Int
    public var departuresToday: Int
    public var consecutiveProfitableMonths: Int
    public var lastProfitMonthIndex: Int
    /// Consecutive days each objective has been met, keyed by objective id.
    public var objectiveSustainedDays: [String: Int]

    public init() {
        self.lastDemandDay = Int.min
        self.lastSettlementDay = Int.min
        self.lastStatisticsHour = Int.min
        self.lastStatisticsDay = Int.min
        self.lastResearchWeek = Int.min
        self.lostEnquiriesToday = 0
        self.lostEnquiriesPriceToday = 0
        self.arrivalsToday = 0
        self.departuresToday = 0
        self.consecutiveProfitableMonths = 0
        self.lastProfitMonthIndex = Int.min
        self.objectiveSustainedDays = [:]
    }
}

/// Things that happened during a tick, published to statistics, notifications and the app layer.
///
/// Systems never call each other directly; they emit events. That decoupling is what keeps the
/// tick order meaningful and the cause of any effect traceable.
public enum SimulationEvent {
    case hourElapsed(Int)
    case dayElapsed(Int)
    case weekElapsed(Int)
    case seasonChanged(Season)
    case reservationCreated(ReservationID)
    case reservationCancelled(ReservationID)
    case groupArrived(GroupID)
    case groupCheckedIn(GroupID)
    case groupCheckedOut(GroupID)
    case groupNoShow(GroupID)
    case guestSpent(GuestID, Money, RevenueCategory)
    case guestThought(GuestID, ThoughtKind)
    case facilityVisited(BuildingID)
    case unitNeedsCleaning(BuildingID)
    case unitCleaned(BuildingID)
    case reviewPosted(ReviewID, Double)
    case researchCompleted(String)
    case staffTaskCompleted(TaskID)
}

/// Everything a system needs for one tick.
public struct TickContext {

    public let tick: Tick
    public let date: GameDate
    public let previousDate: GameDate
    public let tuning: SimulationTuning
    /// Scheduled wake-ups that came due this tick.
    public var dueEvents: [ScheduledEvent]
    public var events: [SimulationEvent]

    public init(tick: Tick, date: GameDate, previousDate: GameDate, tuning: SimulationTuning) {
        self.tick = tick
        self.date = date
        self.previousDate = previousDate
        self.tuning = tuning
        self.dueEvents = []
        self.events = []
    }

    public var isNewHour: Bool { date.hour != previousDate.hour || date.dayIndex != previousDate.dayIndex }
    public var isNewDay: Bool { date.dayIndex != previousDate.dayIndex }
    public var isNewWeek: Bool { date.weekIndex != previousDate.weekIndex }
    public var isNewMonth: Bool { date.monthIndex != previousDate.monthIndex }

    public mutating func emit(_ event: SimulationEvent) {
        events.append(event)
    }

    public func dueEvents(ofKind kind: ScheduledEventKind) -> [ScheduledEvent] {
        dueEvents.filter { $0.kind == kind }
    }
}

/// A stage of the tick.
///
/// Systems are ordered and the order is asserted by tests — "needs drift before decisions" and
/// "spending before settlement" are load-bearing, not incidental.
public protocol SimulationSystem {
    static var systemName: String { get }
    static func update(world: inout World, context: inout TickContext)
}
