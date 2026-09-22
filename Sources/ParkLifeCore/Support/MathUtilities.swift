import Foundation

@inlinable
public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    Swift.min(Swift.max(value, lower), upper)
}

/// Clamps to the unit interval — needs, satisfaction, quality and ratings all live in `0...1`.
@inlinable
public func clamp01(_ value: Double) -> Double {
    clamp(value, 0.0, 1.0)
}

@inlinable
public func lerp(_ from: Double, _ to: Double, _ t: Double) -> Double {
    from + (to - from) * t
}

/// Maps `value` from one range to another, clamped to the destination range.
@inlinable
public func remap(_ value: Double, from source: ClosedRange<Double>, to destination: ClosedRange<Double>) -> Double {
    let span = source.upperBound - source.lowerBound
    guard span != 0 else { return destination.lowerBound }
    let t = clamp01((value - source.lowerBound) / span)
    return destination.lowerBound + t * (destination.upperBound - destination.lowerBound)
}

/// Exponentially weighted moving average step.
@inlinable
public func movingAverage(current: Double, sample: Double, weight: Double) -> Double {
    current * (1.0 - weight) + sample * weight
}

/// Run-length coding for the terrain grids.
///
/// A 96×96 map is 9 216 cells and is mostly uniform, so RLE turns a megabyte of JSON numbers
/// into a few hundred. Encoded as a flat `[value, runLength, value, runLength, …]` array.
public enum RunLength {

    public static func encode(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var run = 1
            while index + run < values.count && values[index + run] == value {
                run += 1
            }
            result.append(value)
            result.append(run)
            index += run
        }
        return result
    }

    public static func decode(_ encoded: [Int], expectedCount: Int) throws -> [Int] {
        guard encoded.count % 2 == 0 else {
            throw RunLengthError.malformed
        }
        var result: [Int] = []
        result.reserveCapacity(expectedCount)
        var index = 0
        while index < encoded.count {
            let value = encoded[index]
            let run = encoded[index + 1]
            guard run > 0, result.count + run <= expectedCount else {
                throw RunLengthError.malformed
            }
            result.append(contentsOf: repeatElement(value, count: run))
            index += 2
        }
        guard result.count == expectedCount else {
            throw RunLengthError.countMismatch(expected: expectedCount, found: result.count)
        }
        return result
    }

    public enum RunLengthError: Error, CustomStringConvertible {
        case malformed
        case countMismatch(expected: Int, found: Int)

        public var description: String {
            switch self {
            case .malformed:
                return "Run-length payload is malformed"
            case .countMismatch(let expected, let found):
                return "Run-length payload decoded \(found) values, expected \(expected)"
            }
        }
    }
}
