import Foundation

/// What a scheduled wake-up means.
public enum ScheduledEventKind: String, Codable {
    case guestWake
    case guestFinishActivity
    case unitTurnaroundComplete
    case facilityServiceComplete
    case staffTaskComplete
    case marketingCampaignEnded
    case dailySettlement
}

public struct ScheduledEvent: Comparable, Codable {

    public var tick: Tick
    /// Monotonic tie-breaker: two events on the same tick must fire in a defined order,
    /// otherwise the simulation is not reproducible.
    public var sequence: UInt32
    public var kind: ScheduledEventKind
    public var entity: UInt32

    public init(tick: Tick, sequence: UInt32, kind: ScheduledEventKind, entity: UInt32) {
        self.tick = tick
        self.sequence = sequence
        self.kind = kind
        self.entity = entity
    }

    public static func < (lhs: ScheduledEvent, rhs: ScheduledEvent) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        return lhs.sequence < rhs.sequence
    }

    public static func == (lhs: ScheduledEvent, rhs: ScheduledEvent) -> Bool {
        lhs.tick == rhs.tick && lhs.sequence == rhs.sequence
            && lhs.kind == rhs.kind && lhs.entity == rhs.entity
    }
}

/// Tick-ordered wake-up queue — the backbone of simulation level of detail.
///
/// A sleeping guest, a guest sitting in a restaurant and a cottage in turnaround all cost
/// *nothing* per tick: they are parked here and woken on an exact future tick. At night a
/// three-thousand-guest park does almost no work.
public struct ScheduleQueue: Codable {

    private var heap: MinHeap<ScheduledEvent>
    private var nextSequence: UInt32

    public init() {
        self.heap = MinHeap<ScheduledEvent>()
        self.nextSequence = 0
    }

    public var count: Int { heap.count }
    public var isEmpty: Bool { heap.isEmpty }

    public mutating func schedule(_ kind: ScheduledEventKind, entity: UInt32, at tick: Tick) {
        let event = ScheduledEvent(tick: tick, sequence: nextSequence, kind: kind, entity: entity)
        nextSequence &+= 1
        heap.insert(event)
    }

    /// Removes and returns every event due at or before `tick`, in firing order.
    public mutating func drain(upTo tick: Tick) -> [ScheduledEvent] {
        var due: [ScheduledEvent] = []
        while let next = heap.min, next.tick <= tick {
            guard let event = heap.removeMin() else { break }
            due.append(event)
        }
        return due
    }

    public var pendingEvents: [ScheduledEvent] {
        heap.storage.sorted()
    }

    enum CodingKeys: String, CodingKey {
        case events
        case nextSequence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let events = try container.decode([ScheduledEvent].self, forKey: .events)
        self.heap = MinHeap<ScheduledEvent>(events)
        self.nextSequence = try container.decode(UInt32.self, forKey: .nextSequence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heap.storage.sorted(), forKey: .events)
        try container.encode(nextSequence, forKey: .nextSequence)
    }
}
