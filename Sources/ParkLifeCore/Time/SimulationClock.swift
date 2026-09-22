import Foundation

public enum GameSpeed: String, CaseIterable, Codable {
    case paused
    case normal
    case fast
    case veryFast
    case maximum

    /// Simulated minutes per real second.
    public var ticksPerSecond: Double {
        switch self {
        case .paused: return 0
        case .normal: return 2
        case .fast: return 4
        case .veryFast: return 8
        case .maximum: return 64
        }
    }

    public var localizationKey: String { "speed.\(rawValue)" }

    public var displayLabel: String {
        switch self {
        case .paused: return "❚❚"
        case .normal: return "1×"
        case .fast: return "2×"
        case .veryFast: return "4×"
        case .maximum: return "▶▶"
        }
    }

    public var next: GameSpeed {
        let all = GameSpeed.allCases
        guard let index = all.firstIndex(of: self) else { return .normal }
        return all[(index + 1) % all.count]
    }
}

/// The simulation clock.
///
/// Fixed-step: real time is accumulated and converted into whole ticks. The number of ticks run
/// per call is capped by both a count and a wall-clock budget, so a slow device loses simulated
/// time instead of dropping frames — and rendering frame rate can never influence outcomes.
public struct SimulationClock: Codable {

    public private(set) var tick: Tick
    public var speed: GameSpeed
    private var accumulator: Double

    public init(startDate: GameDate = GameDate(year: 2026, month: 3, day: 1, hour: 8), speed: GameSpeed = .normal) {
        self.tick = startDate.minutesSinceEpoch
        self.speed = speed
        self.accumulator = 0
    }

    public var date: GameDate {
        GameDate(minutesSinceEpoch: tick)
    }

    /// Number of whole ticks that should run for `realSeconds`, capped by `maximumTicks`.
    /// Leftover fractional time is preserved in the accumulator, so time does not drift.
    public mutating func pendingTicks(forRealSeconds realSeconds: Double, maximumTicks: Int) -> Int {
        guard speed != .paused, realSeconds > 0 else { return 0 }
        accumulator += realSeconds * speed.ticksPerSecond
        let whole = Int(accumulator)
        guard whole > 0 else { return 0 }
        let granted = min(whole, maximumTicks)
        accumulator -= Double(granted)
        // If we could not keep up, drop the backlog rather than spiralling.
        if whole > granted {
            accumulator = 0
        }
        return granted
    }

    public mutating func advanceOneTick() {
        tick += 1
    }

    /// Used by tests and debug tools to jump forward without running systems.
    public mutating func setTick(_ newValue: Tick) {
        tick = newValue
        accumulator = 0
    }

    enum CodingKeys: String, CodingKey {
        case tick
        case speed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tick = try container.decode(Tick.self, forKey: .tick)
        self.speed = try container.decodeIfPresent(GameSpeed.self, forKey: .speed) ?? .normal
        self.accumulator = 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tick, forKey: .tick)
        try container.encode(speed, forKey: .speed)
    }
}
