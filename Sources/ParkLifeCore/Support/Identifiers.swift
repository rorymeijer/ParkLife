import Foundation

/// Typed entity identifier. Wrapping the raw integer stops a `GuestID` ever being passed where a
/// `BuildingID` is expected, which is a whole class of simulation bug removed at compile time.
public protocol EntityIdentifier: Hashable, Codable, Comparable, CustomStringConvertible {
    var raw: UInt32 { get }
    init(raw: UInt32)
}

extension EntityIdentifier {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(raw: try container.decode(UInt32.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.raw < rhs.raw }

    public var description: String { "#\(raw)" }
}

public struct GuestID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct GroupID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct BuildingID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct ReservationID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct StaffID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct TaskID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct ReviewID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

public struct NotificationID: EntityIdentifier {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}

/// Allocates monotonically increasing ids per entity kind. Serialised with the save so ids stay
/// stable and unique across sessions.
public struct IDAllocator: Codable {

    private var counters: [String: UInt32]

    public init() {
        self.counters = [:]
    }

    public mutating func next<T: EntityIdentifier>(_ type: T.Type) -> T {
        let key = String(describing: type)
        let value = (counters[key] ?? 0) + 1
        counters[key] = value
        return T(raw: value)
    }

    /// Highest id handed out so far for a kind (0 when none).
    public func issued<T: EntityIdentifier>(_ type: T.Type) -> UInt32 {
        counters[String(describing: type)] ?? 0
    }
}
