import Foundation

/// FNV-1a 64-bit hash.
///
/// Used for save checksums and for the determinism world-hash. Swift's own `Hasher` is seeded
/// per process and therefore useless for anything that must be stable across runs.
public struct FNV1a {

    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x1000_0000_01b3

    private var value: UInt64 = FNV1a.offsetBasis

    public init() {}

    public mutating func combine(_ bytes: [UInt8]) {
        for byte in bytes {
            value ^= UInt64(byte)
            value = value &* FNV1a.prime
        }
    }

    public mutating func combine(_ data: Data) {
        for byte in data {
            value ^= UInt64(byte)
            value = value &* FNV1a.prime
        }
    }

    public mutating func combine(_ string: String) {
        combine(Array(string.utf8))
    }

    public var digest: UInt64 { value }

    public var hexDigest: String {
        FNV1a.hexString(of: value)
    }

    /// Manual hex formatting: `String(format:)` with a 64-bit integer has platform-dependent
    /// length modifiers, and this value ends up in save files.
    public static func hexString(of value: UInt64) -> String {
        let digits = Array("0123456789abcdef")
        var characters = [Character](repeating: "0", count: 16)
        var remaining = value
        var index = 15
        while index >= 0 {
            characters[index] = digits[Int(remaining & 0xF)]
            remaining >>= 4
            index -= 1
        }
        return String(characters)
    }

    public static func hash(_ data: Data) -> UInt64 {
        var hasher = FNV1a()
        hasher.combine(data)
        return hasher.digest
    }

    public static func hexString(_ data: Data) -> String {
        var hasher = FNV1a()
        hasher.combine(data)
        return hasher.hexDigest
    }
}
