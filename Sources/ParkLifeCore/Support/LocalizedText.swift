import Foundation

/// A user-facing string produced by the simulation.
///
/// The core never produces English prose. It emits a localisation *key* plus typed arguments,
/// and the app resolves it against `Localizable.strings`. This is what makes Dutch, German and
/// French possible later without touching simulation code (brief §49).
public struct LocalizedText: Hashable, Codable {

    public enum Argument: Hashable, Codable {
        case text(String)
        case integer(Int)
        case number(Double)
        case money(Money)
        case minutes(Int)
    }

    public var key: String
    public var arguments: [Argument]

    public init(_ key: String, _ arguments: [Argument] = []) {
        self.key = key
        self.arguments = arguments
    }

    /// Readable fallback used by tests, logs and any missing translation.
    public var developerDescription: String {
        guard !arguments.isEmpty else { return key }
        let rendered = arguments.map { argument -> String in
            switch argument {
            case .text(let value): return value
            case .integer(let value): return String(value)
            case .number(let value): return String(format: "%.2f", value)
            case .money(let value): return value.description
            case .minutes(let value): return "\(value)m"
            }
        }
        return "\(key)(\(rendered.joined(separator: ", ")))"
    }
}
