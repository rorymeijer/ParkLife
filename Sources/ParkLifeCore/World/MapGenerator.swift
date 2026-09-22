import Foundation

/// Builds a park's terrain from its `MapDefinition`.
///
/// Generation is deterministic from the map's own seed, which is why maps are a few lines of JSON
/// instead of ten thousand stored tile values — and why two players on the same map see the same
/// lake in the same place.
public enum MapGenerator {

    public static func generate(map: MapDefinition) -> TileMap {
        let size = map.size
        var tiles = TileMap(size: size)
        var random = SeededRandom(seed: map.generationSeed)

        // Gentle rolling elevation from summed value noise.
        let hillCount = 5
        var hills: [(x: Double, y: Double, height: Double, radius: Double)] = []
        for _ in 0..<hillCount {
            hills.append((
                x: random.nextDouble(in: 0...Double(size.width)),
                y: random.nextDouble(in: 0...Double(size.height)),
                height: random.nextDouble(in: 0.8...3.4),
                radius: random.nextDouble(in: 12...30)
            ))
        }

        for y in 0..<size.height {
            for x in 0..<size.width {
                var elevation = 0.0
                for hill in hills {
                    let dx = Double(x) - hill.x
                    let dy = Double(y) - hill.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < hill.radius {
                        let falloff = 1.0 - distance / hill.radius
                        elevation += hill.height * falloff * falloff
                    }
                }
                tiles.setElevation(Int(elevation.rounded()), at: GridPoint(x: x, y: y))
            }
        }

        // Water bodies, drawn as ellipses inscribed in the declared rectangles so lakes look
        // natural rather than like swimming pools.
        for feature in map.water {
            let centreX = Double(feature.x) + Double(feature.width) / 2.0
            let centreY = Double(feature.y) + Double(feature.height) / 2.0
            let radiusX = Double(feature.width) / 2.0
            let radiusY = Double(feature.height) / 2.0
            guard radiusX > 0, radiusY > 0 else { continue }
            for y in max(0, feature.y - 2)..<min(size.height, feature.y + feature.height + 2) {
                for x in max(0, feature.x - 2)..<min(size.width, feature.x + feature.width + 2) {
                    let normalX = (Double(x) + 0.5 - centreX) / radiusX
                    let normalY = (Double(y) + 0.5 - centreY) / radiusY
                    let distance = normalX * normalX + normalY * normalY
                    // Wobble the shoreline so it is not a perfect ellipse.
                    let wobble = random.nextDouble(in: -0.06...0.06)
                    let point = GridPoint(x: x, y: y)
                    if distance + wobble < 1.0 {
                        tiles.setTerrain(.water, at: point)
                        tiles.setElevation(0, at: point)
                    } else if distance + wobble < 1.22 {
                        tiles.setTerrain(.sand, at: point)
                        tiles.setElevation(0, at: point)
                    }
                }
            }
        }

        // Forest patches.
        for patch in map.forests {
            let radius = Double(patch.radius)
            for y in max(0, patch.y - patch.radius)..<min(size.height, patch.y + patch.radius + 1) {
                for x in max(0, patch.x - patch.radius)..<min(size.width, patch.x + patch.radius + 1) {
                    let point = GridPoint(x: x, y: y)
                    guard tiles.terrain(at: point) == .grass else { continue }
                    let dx = Double(x - patch.x)
                    let dy = Double(y - patch.y)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    guard distance <= radius else { continue }
                    let probability = patch.density * (1.0 - distance / radius)
                    if random.chance(probability) {
                        tiles.setTerrain(.forest, at: point)
                    }
                }
            }
        }

        // Clear a flat apron in front of the entrance so the park is always buildable from day one.
        let entrance = map.entrance
        let apron = GridRect(
            x: entrance.x - 4,
            y: entrance.y - 4,
            width: 9,
            height: 9
        ).clamped(to: size)
        if !apron.isEmpty {
            for point in apron.points {
                if tiles.terrain(at: point) == .forest {
                    tiles.setTerrain(.grass, at: point)
                }
                tiles.setElevation(0, at: point)
            }
        }

        tiles.markDirty(GridRect(x: 0, y: 0, width: size.width, height: size.height))
        ParkLog.shared.info(.content, "Generated map \(map.id) (\(size.width)×\(size.height))")
        return tiles
    }
}
