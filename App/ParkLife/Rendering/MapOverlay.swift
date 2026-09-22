import SwiftUI
import UIKit
import ParkLifeCore

/// Data overlays drawn on top of the park.
///
/// Each one reads a scalar the simulation already computes, so adding an overlay is a matter of
/// naming the value, not of adding rendering state.
enum MapOverlay: String, CaseIterable, Identifiable {
    case none
    case scenery
    case congestion
    case occupancy
    case cleanliness

    var id: String { rawValue }

    var localizationKey: String { "overlay.\(rawValue)" }

    var symbolName: String {
        switch self {
        case .none: return "map"
        case .scenery: return "leaf"
        case .congestion: return "person.3"
        case .occupancy: return "bed.double"
        case .cleanliness: return "sparkles"
        }
    }

    /// Value in `0...1` for a tile, or `nil` when this overlay does not colour that tile.
    func value(for tile: WorldSnapshot.TileSample, snapshot: WorldSnapshot) -> Double? {
        switch self {
        case .none:
            return nil
        case .scenery:
            return (tile.scenery + 1.0) / 2.0
        case .congestion:
            return tile.congestion > 0.02 ? tile.congestion : nil
        case .occupancy:
            guard let buildingID = tile.buildingID,
                  let building = snapshot.buildings.first(where: { $0.id == buildingID }),
                  let stateKey = building.stateKey else { return nil }
            return stateKey == "unitState.occupied" ? 1.0 : 0.15
        case .cleanliness:
            guard tile.surface != .none else { return nil }
            return 1.0 - tile.congestion
        }
    }

    /// Colour-blind-safe ramp: it varies in lightness as well as hue, and every overlay is also
    /// labelled in the legend (brief §48).
    func uiColour(for value: Double) -> UIColor {
        let clamped = CGFloat(min(max(value, 0), 1))
        switch self {
        case .none:
            return .clear
        case .scenery:
            return UIColor(hue: 0.33, saturation: 0.55, brightness: 0.35 + 0.5 * clamped, alpha: 1)
        case .congestion:
            return UIColor(hue: 0.08 - 0.08 * clamped, saturation: 0.75, brightness: 0.45 + 0.4 * clamped, alpha: 1)
        case .occupancy:
            return UIColor(hue: 0.58, saturation: 0.6, brightness: 0.35 + 0.5 * clamped, alpha: 1)
        case .cleanliness:
            return UIColor(hue: 0.52, saturation: 0.45, brightness: 0.35 + 0.5 * clamped, alpha: 1)
        }
    }

    func colour(for value: Double) -> Color {
        Color(uiColour(for: value))
    }
}
