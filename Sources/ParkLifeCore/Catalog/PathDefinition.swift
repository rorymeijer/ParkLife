import Foundation

/// A buildable surface (footpath, cycle path, plaza, bridge).
///
/// Paths are not buildings: they occupy a tile's *surface*, many tiles at a time, and they are
/// what the walkable network is derived from. Keeping them a separate definition type avoids
/// pretending a path is a 1×1 building with special cases everywhere.
public struct PathDefinition: Codable {
    public let id: String
    public let nameKey: String
    /// Surface identifier, e.g. `"footpath"`. Kept as a string so content JSON stays readable
    /// rather than carrying raw enum numbers.
    public let surfaceID: String
    public let costPerTile: Money
    public let demolitionRefundFraction: Double
    public let art: String
    public let researchID: String?
    public let scenery: Double

    public var surface: SurfaceType {
        switch surfaceID {
        case "footpath": return .footpath
        case "cyclePath": return .cyclePath
        case "plaza": return .plaza
        case "bridge": return .bridge
        case "road": return .road
        default: return .footpath
        }
    }
}

/// Fictional given names used to populate guests and staff.
///
/// Original content only — no names, brands or places are taken from any existing product
/// (ASSET POLICY §54).
public struct NameCatalog: Codable {
    public let adultNames: [String]
    public let childNames: [String]
    public let staffNames: [String]
    public let surnames: [String]
}
