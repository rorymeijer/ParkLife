import Foundation

/// Currency amount in whole euro cents.
///
/// Money is an integer type on purpose: the economy must be deterministic and reproducible
/// across devices, and floating point accumulation of thousands of small transactions drifts.
public struct Money: Hashable, Comparable, Codable, CustomStringConvertible {

    public var cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    public init(euros: Int) {
        self.cents = euros * 100
    }

    public static let zero = Money(cents: 0)

    public static func euros(_ amount: Int) -> Money {
        Money(cents: amount * 100)
    }

    /// Rounds half away from zero, so `2.005` style values never silently truncate downwards.
    public static func euros(_ amount: Double) -> Money {
        Money(cents: Int((amount * 100).rounded()))
    }

    public var euroValue: Double {
        Double(cents) / 100.0
    }

    public var isZero: Bool { cents == 0 }
    public var isPositive: Bool { cents > 0 }
    public var isNegative: Bool { cents < 0 }
    public var magnitude: Money { Money(cents: abs(cents)) }

    // MARK: - Arithmetic

    public static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    public static func * (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents * rhs) }
    public static func * (lhs: Int, rhs: Money) -> Money { Money(cents: lhs * rhs.cents) }
    public static prefix func - (value: Money) -> Money { Money(cents: -value.cents) }

    public static func += (lhs: inout Money, rhs: Money) { lhs.cents += rhs.cents }
    public static func -= (lhs: inout Money, rhs: Money) { lhs.cents -= rhs.cents }

    /// Scales by a factor, rounding to the nearest cent.
    public func scaled(by factor: Double) -> Money {
        Money(cents: Int((Double(cents) * factor).rounded()))
    }

    /// Splits an amount into `parts` shares that sum exactly back to the original.
    public func split(into parts: Int) -> [Money] {
        guard parts > 0 else { return [] }
        let base = cents / parts
        let remainder = cents - base * parts
        var result = [Money](repeating: Money(cents: base), count: parts)
        for index in 0..<abs(remainder) {
            result[index].cents += remainder > 0 ? 1 : -1
        }
        return result
    }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    public var description: String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        return "\(sign)€\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }

    // MARK: - Codable (encoded as a bare integer of cents)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.cents = try container.decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cents)
    }
}
