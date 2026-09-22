import Foundation

/// Deterministic SplitMix64 generator.
///
/// The simulation must reproduce exactly from a seed, so it never uses `SystemRandomNumberGenerator`,
/// `Int.random(in:)` without a generator, or anything else seeded by the OS.
public struct SeededRandom: RandomNumberGenerator, Codable {

    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `[0, 1)`.
    public mutating func nextUnit() -> Double {
        // 53 significant bits, the most a Double can represent exactly.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }

    public mutating func pick<T>(_ elements: [T]) -> T? {
        guard !elements.isEmpty else { return nil }
        return elements[nextInt(in: 0...(elements.count - 1))]
    }

    /// Picks an index proportionally to `weights`. Non-positive weights are ignored.
    public mutating func weightedIndex(_ weights: [Double]) -> Int? {
        var total = 0.0
        for weight in weights where weight > 0 { total += weight }
        guard total > 0 else { return nil }
        var roll = nextUnit() * total
        for (index, weight) in weights.enumerated() where weight > 0 {
            roll -= weight
            if roll <= 0 { return index }
        }
        return weights.lastIndex(where: { $0 > 0 })
    }

    /// Box–Muller normal sample, clamped to ±4σ so extreme tails cannot break tuning.
    public mutating func gaussian(mean: Double, standardDeviation: Double) -> Double {
        let u1 = max(nextUnit(), 1e-12)
        let u2 = nextUnit()
        let magnitude = (-2.0 * log(u1)).squareRoot()
        let z = magnitude * cos(2.0 * Double.pi * u2)
        return mean + standardDeviation * max(-4.0, min(4.0, z))
    }

    /// Knuth's Poisson sampler for small means, normal approximation above 30.
    public mutating func poisson(mean: Double) -> Int {
        guard mean > 0 else { return 0 }
        if mean > 30 {
            return max(0, Int(gaussian(mean: mean, standardDeviation: mean.squareRoot()).rounded()))
        }
        let limit = exp(-mean)
        var product = 1.0
        var count = 0
        while true {
            product *= nextUnit()
            if product <= limit { return count }
            count += 1
            if count > 512 { return count }
        }
    }
}

/// Independent random streams, one per subsystem.
///
/// Separate streams mean that adding a weather roll cannot shift guest behaviour, so balance
/// changes in one system stay comparable across runs.
public struct RandomStreams: Codable {

    public var demand: SeededRandom
    public var guestSpawn: SeededRandom
    public var guestBehaviour: SeededRandom
    public var weather: SeededRandom
    public var incidents: SeededRandom
    public var reviews: SeededRandom
    public var staff: SeededRandom

    public init(masterSeed: UInt64) {
        func derive(_ salt: UInt64) -> SeededRandom {
            var mixer = SeededRandom(seed: masterSeed &+ salt &* 0x9E37_79B9_7F4A_7C15)
            _ = mixer.next()
            return SeededRandom(seed: mixer.next())
        }
        self.demand = derive(1)
        self.guestSpawn = derive(2)
        self.guestBehaviour = derive(3)
        self.weather = derive(4)
        self.incidents = derive(5)
        self.reviews = derive(6)
        self.staff = derive(7)
    }
}
