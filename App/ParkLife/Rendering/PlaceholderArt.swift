import SpriteKit
import UIKit
import ParkLifeCore

/// Procedurally generated placeholder artwork.
///
/// Original, generated in code, and deliberately simple: gameplay systems come first and final art
/// must never block them (Rule 9, ASSET POLICY §54). Every texture is keyed by the *art*
/// identifier from the content catalog, which is separate from the simulation id — so dropping in
/// real sprites later means shipping files named after those identifiers and deleting this file.
enum PlaceholderArt {

    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    private static var cache: [String: SKTexture] = [:]

    // MARK: - Terrain

    static func terrainTexture(_ terrain: TerrainType, surface: SurfaceType) -> SKTexture {
        let key = "terrain-\(terrain.rawValue)-\(surface.rawValue)"
        if let cached = cache[key] { return cached }
        let texture = SKTexture(image: diamondImage(fill: colour(terrain: terrain, surface: surface)))
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    private static func colour(terrain: TerrainType, surface: SurfaceType) -> UIColor {
        switch surface {
        case .footpath: return UIColor(red: 0.85, green: 0.79, blue: 0.66, alpha: 1)
        case .cyclePath: return UIColor(red: 0.74, green: 0.68, blue: 0.60, alpha: 1)
        case .plaza: return UIColor(red: 0.88, green: 0.86, blue: 0.82, alpha: 1)
        case .road: return UIColor(red: 0.42, green: 0.42, blue: 0.44, alpha: 1)
        case .bridge: return UIColor(red: 0.66, green: 0.50, blue: 0.33, alpha: 1)
        case .none:
            switch terrain {
            case .grass: return UIColor(red: 0.52, green: 0.72, blue: 0.38, alpha: 1)
            case .sand: return UIColor(red: 0.90, green: 0.84, blue: 0.62, alpha: 1)
            case .water: return UIColor(red: 0.34, green: 0.60, blue: 0.80, alpha: 1)
            case .forest: return UIColor(red: 0.28, green: 0.52, blue: 0.30, alpha: 1)
            case .rock: return UIColor(red: 0.58, green: 0.57, blue: 0.55, alpha: 1)
            case .paved: return UIColor(red: 0.78, green: 0.77, blue: 0.75, alpha: 1)
            }
        }
    }

    private static func diamondImage(fill: UIColor) -> UIImage {
        let size = CGSize(width: tileWidth, height: tileHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width / 2, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height / 2))
            path.close()
            fill.setFill()
            path.fill()
            fill.withAlphaComponent(0.35).darkened().setStroke()
            path.lineWidth = 1
            path.stroke()
            _ = context
        }
    }

    // MARK: - Buildings

    /// Artwork for one building, chosen by category.
    ///
    /// Cottages and the pool are drawn as actual buildings — a pitched roof, walls with windows,
    /// a glazed hall with water inside — because they are what the player looks at most. Every
    /// shape here is generated in code and original to this project (ASSET POLICY §54).
    static func buildingTexture(art: String, category: BuildingCategory, footprint: GridSize) -> SKTexture {
        let key = "building-\(art)-\(footprint.width)x\(footprint.height)"
        if let cached = cache[key] { return cached }

        let image: UIImage
        switch category {
        case .accommodation:
            image = cottageImage(art: art, footprint: footprint)
        case .pool:
            image = poolHallImage(footprint: footprint)
        case .food, .retail, .activity, .service, .staff, .decoration, .infrastructure, .path:
            image = blockImage(art: art, category: category, footprint: footprint)
        }

        let texture = SKTexture(image: image)
        // Linear, not nearest: these are drawn at device scale and the park is usually viewed
        // zoomed out, where nearest-neighbour turns every roof edge into a staircase.
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    // MARK: Isometric helpers

    /// The four corners of a footprint's top face, and the drop to the foot of its walls.
    ///
    /// `roofRise` leaves headroom at the top of the image for a ridge. The sprite is anchored at
    /// the bottom of the texture, so growing upwards costs nothing in alignment.
    private struct Massing {
        let size: CGSize
        let north: CGPoint
        let east: CGPoint
        let south: CGPoint
        let west: CGPoint
        let wallHeight: CGFloat
        let roofRise: CGFloat

        init(footprint: GridSize, wallHeight: CGFloat, roofRise: CGFloat) {
            // Qualified: a nested type does not see the enclosing type's statics unqualified.
            let baseWidth = PlaceholderArt.tileWidth * CGFloat(footprint.width + footprint.height) / 2
            let baseHeight = PlaceholderArt.tileHeight * CGFloat(footprint.width + footprint.height) / 2
            let halfW = baseWidth / 2
            let halfH = baseHeight / 2
            self.size = CGSize(width: baseWidth, height: roofRise + baseHeight + wallHeight)
            self.north = CGPoint(x: halfW, y: roofRise)
            self.east = CGPoint(x: baseWidth, y: roofRise + halfH)
            self.south = CGPoint(x: halfW, y: roofRise + baseHeight)
            self.west = CGPoint(x: 0, y: roofRise + halfH)
            self.wallHeight = wallHeight
            self.roofRise = roofRise
        }

        var centre: CGPoint { CGPoint(x: (west.x + east.x) / 2, y: (north.y + south.y) / 2) }

        func dropped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: point.y + wallHeight)
        }

        /// Pulls a corner of the top face towards the centre, for an inset deck or basin.
        func inset(_ point: CGPoint, by factor: CGFloat) -> CGPoint {
            let middle = centre
            return CGPoint(
                x: middle.x + (point.x - middle.x) * factor,
                y: middle.y + (point.y - middle.y) * factor
            )
        }
    }

    private static func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.close()
        return path
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// A point on a wall face. `u` runs along the top edge from `a` to `b`, `v` down the wall.
    private static func wallPoint(
        _ a: CGPoint, _ b: CGPoint, u: CGFloat, v: CGFloat, drop: CGFloat
    ) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u + drop * v)
    }

    /// A rectangle in a wall's own plane — a window or a door, skewed to sit flat on the wall.
    private static func wallPanel(
        _ a: CGPoint, _ b: CGPoint, drop: CGFloat,
        u0: CGFloat, u1: CGFloat, v0: CGFloat, v1: CGFloat
    ) -> UIBezierPath {
        polygon([
            wallPoint(a, b, u: u0, v: v0, drop: drop),
            wallPoint(a, b, u: u1, v: v0, drop: drop),
            wallPoint(a, b, u: u1, v: v1, drop: drop),
            wallPoint(a, b, u: u0, v: v1, drop: drop)
        ])
    }

    // MARK: Cottages

    private struct CottagePalette {
        let wall: UIColor
        let wallShade: UIColor
        let roof: UIColor
        let roofShade: UIColor
        let trim: UIColor
        let glass: UIColor
        let door: UIColor
    }

    /// Stable per-type colours, so a basic cottage and a premium lodge are visibly different
    /// buildings rather than the same box in two shades.
    private static func cottagePalette(seed: String) -> CottagePalette {
        var hasher = FNV1a()
        hasher.combine(seed)
        let digest = hasher.digest

        let wallHue = 0.06 + CGFloat(digest % 50) / 1000.0
        let wallSaturation = 0.14 + CGFloat((digest / 50) % 16) / 100.0
        let roofHue = 0.015 + CGFloat((digest / 800) % 70) / 1000.0
        let litWindows = (digest / 64) % 3 != 0

        let wall = UIColor(hue: wallHue, saturation: wallSaturation, brightness: 0.92, alpha: 1)
        let roof = UIColor(hue: roofHue, saturation: 0.50, brightness: 0.60, alpha: 1)
        return CottagePalette(
            wall: wall,
            wallShade: wall.darkened(by: 0.17),
            roof: roof,
            roofShade: roof.darkened(by: 0.15),
            trim: UIColor(white: 0.97, alpha: 1),
            glass: litWindows
                ? UIColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 1)
                : UIColor(red: 0.36, green: 0.46, blue: 0.54, alpha: 1),
            door: UIColor(hue: roofHue, saturation: 0.55, brightness: 0.45, alpha: 1)
        )
    }

    /// A gabled holiday cottage.
    ///
    /// The ridge runs back-left to front-right so the gable end faces the camera, which is where
    /// the door goes; the long wall on the left carries the windows.
    private static func cottageImage(art: String, footprint: GridSize) -> UIImage {
        let wallHeight = height(for: .accommodation)
        let massing = Massing(footprint: footprint, wallHeight: wallHeight, roofRise: wallHeight * 0.62)
        let palette = cottagePalette(seed: art)

        let north = massing.north
        let east = massing.east
        let south = massing.south
        let west = massing.west
        // Ridge ends sit directly above the midpoints of the two gable edges.
        let ridgeBack = CGPoint(
            x: (west.x + north.x) / 2,
            y: (west.y + north.y) / 2 - massing.roofRise
        )
        let ridgeFront = CGPoint(
            x: (south.x + east.x) / 2,
            y: (south.y + east.y) / 2 - massing.roofRise
        )

        let renderer = UIGraphicsImageRenderer(size: massing.size)
        return renderer.image { _ in
            // Long wall, facing front-left.
            palette.wallShade.setFill()
            polygon([west, south, massing.dropped(south), massing.dropped(west)]).fill()
            // Gable wall, facing front-right, plus its triangle up to the ridge.
            palette.wall.setFill()
            polygon([south, east, massing.dropped(east), massing.dropped(south)]).fill()
            polygon([south, east, ridgeFront]).fill()
            // The far gable, mostly hidden behind the roof but visible at the very top.
            palette.wallShade.setFill()
            polygon([west, north, ridgeBack]).fill()

            drawCottageOpenings(massing: massing, palette: palette)

            // Roof last: its eaves land exactly on the wall tops, so nothing is overdrawn.
            palette.roofShade.setFill()
            polygon([ridgeBack, west, south, ridgeFront]).fill()
            palette.roof.setFill()
            polygon([ridgeBack, north, east, ridgeFront]).fill()

            // Ridge line and a chimney near the front gable.
            palette.roofShade.darkened(by: 0.10).setStroke()
            let ridge = UIBezierPath()
            ridge.move(to: ridgeBack)
            ridge.addLine(to: ridgeFront)
            ridge.lineWidth = 1.5
            ridge.stroke()

            drawChimney(at: lerp(ridgeBack, ridgeFront, 0.30), palette: palette, scale: wallHeight)
        }
    }

    private static func drawCottageOpenings(massing: Massing, palette: CottagePalette) {
        let drop = massing.wallHeight

        // Two windows along the long wall.
        for u in [CGFloat(0.22), CGFloat(0.60)] {
            palette.trim.setFill()
            wallPanel(massing.west, massing.south, drop: drop,
                      u0: u, u1: u + 0.20, v0: 0.22, v1: 0.66).fill()
            palette.glass.setFill()
            wallPanel(massing.west, massing.south, drop: drop,
                      u0: u + 0.03, u1: u + 0.17, v0: 0.28, v1: 0.60).fill()
        }

        // Door on the gable end, reaching the ground, with a window beside it.
        palette.door.setFill()
        wallPanel(massing.south, massing.east, drop: drop,
                  u0: 0.30, u1: 0.48, v0: 0.30, v1: 1.0).fill()
        palette.trim.setFill()
        wallPanel(massing.south, massing.east, drop: drop,
                  u0: 0.60, u1: 0.82, v0: 0.24, v1: 0.64).fill()
        palette.glass.setFill()
        wallPanel(massing.south, massing.east, drop: drop,
                  u0: 0.63, u1: 0.79, v0: 0.30, v1: 0.58).fill()
    }

    private static func drawChimney(at point: CGPoint, palette: CottagePalette, scale: CGFloat) {
        let width = max(5, scale * 0.20)
        let stackHeight = max(10, scale * 0.46)
        palette.roofShade.setFill()
        UIBezierPath(rect: CGRect(
            x: point.x - width / 2, y: point.y - stackHeight, width: width, height: stackHeight
        )).fill()
        palette.wall.darkened(by: 0.08).setFill()
        UIBezierPath(rect: CGRect(
            x: point.x - width / 2 - 1, y: point.y - stackHeight - 2, width: width + 2, height: 3
        )).fill()
    }

    // MARK: The pool

    /// A swimming pool: a glazed enclosure around a sunken, coped basin.
    ///
    /// Nested inset rings do the work — coping, then the basin wall in deeper water, then the
    /// surface — which reads as depth from this angle without needing real geometry for the hole.
    /// An earlier version roofed the whole thing in glass; the water disappeared under it, which
    /// defeated the point of drawing a pool at all.
    private static func poolHallImage(footprint: GridSize) -> UIImage {
        let wallHeight = height(for: .pool)
        let massing = Massing(footprint: footprint, wallHeight: wallHeight, roofRise: 0)

        let deck = UIColor(red: 0.89, green: 0.89, blue: 0.86, alpha: 1)
        let coping = UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1)
        let waterDeep = UIColor(red: 0.10, green: 0.42, blue: 0.62, alpha: 1)
        let water = UIColor(red: 0.18, green: 0.62, blue: 0.82, alpha: 1)
        let waterLight = UIColor(red: 0.55, green: 0.85, blue: 0.94, alpha: 1)
        let plinth = UIColor(red: 0.74, green: 0.76, blue: 0.78, alpha: 1)
        let glazing = UIColor(red: 0.72, green: 0.90, blue: 0.95, alpha: 1)
        let mullion = UIColor(red: 0.62, green: 0.68, blue: 0.72, alpha: 1)

        let north = massing.north
        let east = massing.east
        let south = massing.south
        let west = massing.west

        let renderer = UIGraphicsImageRenderer(size: massing.size)
        return renderer.image { _ in
            // Enclosure walls: a plinth with a band of glazing above it.
            plinth.setFill()
            polygon([west, south, massing.dropped(south), massing.dropped(west)]).fill()
            polygon([south, east, massing.dropped(east), massing.dropped(south)]).fill()
            glazing.darkened(by: 0.06).setFill()
            wallPanel(west, south, drop: massing.wallHeight, u0: 0.04, u1: 0.96, v0: 0.10, v1: 0.62).fill()
            glazing.setFill()
            wallPanel(south, east, drop: massing.wallHeight, u0: 0.04, u1: 0.96, v0: 0.10, v1: 0.62).fill()
            mullion.setStroke()
            for u in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75)] {
                for wall in [(west, south), (south, east)] {
                    let bar = UIBezierPath()
                    bar.move(to: wallPoint(wall.0, wall.1, u: u, v: 0.10, drop: massing.wallHeight))
                    bar.addLine(to: wallPoint(wall.0, wall.1, u: u, v: 0.62, drop: massing.wallHeight))
                    bar.lineWidth = 1
                    bar.stroke()
                }
            }

            // Poolside deck.
            deck.setFill()
            polygon([north, east, south, west]).fill()

            let corners = [north, east, south, west]
            let ring: (CGFloat) -> [CGPoint] = { factor in
                corners.map { massing.inset($0, by: factor) }
            }
            // Coping, basin wall, then the water surface itself.
            coping.setFill()
            polygon(ring(0.86)).fill()
            waterDeep.setFill()
            polygon(ring(0.80)).fill()
            let surface = ring(0.72)
            water.setFill()
            polygon(surface).fill()

            // Lane lines run the length of the basin.
            waterLight.withAlphaComponent(0.85).setStroke()
            for t in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75)] {
                let lane = UIBezierPath()
                lane.move(to: lerp(surface[3], surface[2], t))
                lane.addLine(to: lerp(surface[0], surface[1], t))
                lane.lineWidth = 1.2
                lane.stroke()
            }
            // A ladder on the near edge. The lane lines already give the water its texture;
            // freehand "ripples" at this size just read as scratches across them.
            coping.setStroke()
            let ladderFoot = lerp(surface[2], surface[1], 0.35)
            for offset in [CGFloat(-3), CGFloat(3)] {
                let rail = UIBezierPath()
                rail.move(to: CGPoint(x: ladderFoot.x + offset, y: ladderFoot.y + 2))
                rail.addLine(to: CGPoint(x: ladderFoot.x + offset, y: ladderFoot.y - 8))
                rail.lineWidth = 1.5
                rail.stroke()
            }
            for step in [CGFloat(0), CGFloat(4)] {
                let rung = UIBezierPath()
                rung.move(to: CGPoint(x: ladderFoot.x - 3, y: ladderFoot.y - 4 - step))
                rung.addLine(to: CGPoint(x: ladderFoot.x + 3, y: ladderFoot.y - 4 - step))
                rung.lineWidth = 1.2
                rung.stroke()
            }
        }
    }

    // MARK: Everything else

    /// A simple extruded block sized to the footprint, tinted by category.
    private static func blockImage(art: String, category: BuildingCategory, footprint: GridSize) -> UIImage {
        let baseWidth = tileWidth * CGFloat(footprint.width + footprint.height) / 2
        let baseHeight = tileHeight * CGFloat(footprint.width + footprint.height) / 2
        let bodyHeight = height(for: category)
        let size = CGSize(width: baseWidth, height: baseHeight + bodyHeight)

        let tint = colour(for: category, seed: art)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let halfW = baseWidth / 2
            let halfH = baseHeight / 2

            tint.lightened().setFill()
            polygon([
                CGPoint(x: halfW, y: 0),
                CGPoint(x: baseWidth, y: halfH),
                CGPoint(x: halfW, y: baseHeight),
                CGPoint(x: 0, y: halfH)
            ]).fill()

            tint.darkened().setFill()
            polygon([
                CGPoint(x: 0, y: halfH),
                CGPoint(x: halfW, y: baseHeight),
                CGPoint(x: halfW, y: baseHeight + bodyHeight),
                CGPoint(x: 0, y: halfH + bodyHeight)
            ]).fill()

            tint.setFill()
            polygon([
                CGPoint(x: baseWidth, y: halfH),
                CGPoint(x: halfW, y: baseHeight),
                CGPoint(x: halfW, y: baseHeight + bodyHeight),
                CGPoint(x: baseWidth, y: halfH + bodyHeight)
            ]).fill()
        }
    }

    private static func height(for category: BuildingCategory) -> CGFloat {
        switch category {
        case .accommodation: return 34
        case .food, .retail: return 30
        case .pool: return 40
        case .service, .staff: return 28
        case .activity: return 20
        case .infrastructure: return 26
        case .decoration: return 16
        case .path: return 2
        }
    }

    private static func colour(for category: BuildingCategory, seed: String) -> UIColor {
        // A stable per-art hue jitter so neighbouring buildings are not identical.
        var hasher = FNV1a()
        hasher.combine(seed)
        let jitter = CGFloat(hasher.digest % 1_000) / 1_000.0 * 0.05 - 0.025

        let base: (CGFloat, CGFloat, CGFloat)
        switch category {
        case .accommodation: base = (0.08, 0.55, 0.85)
        case .food: base = (0.02, 0.60, 0.88)
        case .retail: base = (0.12, 0.55, 0.90)
        case .activity: base = (0.15, 0.62, 0.86)
        case .pool: base = (0.55, 0.55, 0.88)
        case .service: base = (0.60, 0.35, 0.80)
        case .staff: base = (0.70, 0.30, 0.72)
        case .decoration: base = (0.30, 0.55, 0.70)
        case .infrastructure: base = (0.09, 0.30, 0.70)
        case .path: base = (0.10, 0.20, 0.85)
        }
        return UIColor(hue: base.0 + jitter, saturation: base.1, brightness: base.2, alpha: 1)
    }

    // MARK: - People

    static func guestTexture(ageBand: AgeBand) -> SKTexture {
        let key = "guest-\(ageBand.rawValue)"
        if let cached = cache[key] { return cached }
        let height: CGFloat = ageBand == .child ? 14 : 20
        let tint: UIColor
        switch ageBand {
        case .child: tint = UIColor(red: 0.95, green: 0.62, blue: 0.30, alpha: 1)
        case .teen: tint = UIColor(red: 0.85, green: 0.45, blue: 0.62, alpha: 1)
        case .adult: tint = UIColor(red: 0.30, green: 0.45, blue: 0.85, alpha: 1)
        case .senior: tint = UIColor(red: 0.55, green: 0.55, blue: 0.62, alpha: 1)
        }
        let texture = SKTexture(image: personImage(height: height, tint: tint))
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    static func staffTexture() -> SKTexture {
        let key = "staff"
        if let cached = cache[key] { return cached }
        let texture = SKTexture(
            image: personImage(height: 20, tint: UIColor(red: 0.95, green: 0.85, blue: 0.20, alpha: 1))
        )
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    private static func personImage(height: CGFloat, tint: UIColor) -> UIImage {
        let size = CGSize(width: 10, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            tint.setFill()
            UIBezierPath(roundedRect: CGRect(x: 2, y: height * 0.35, width: 6, height: height * 0.65), cornerRadius: 2).fill()
            UIColor(red: 0.98, green: 0.85, blue: 0.72, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 2.5, y: 0, width: 5, height: height * 0.36)).fill()
        }
    }

    // MARK: - Highlights

    static func highlightTexture(valid: Bool) -> SKTexture {
        let key = "highlight-\(valid)"
        if let cached = cache[key] { return cached }
        let colour = valid
            ? UIColor(red: 0.25, green: 0.85, blue: 0.40, alpha: 0.55)
            : UIColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 0.55)
        let texture = SKTexture(image: diamondImage(fill: colour))
        cache[key] = texture
        return texture
    }

    static func selectionTexture() -> SKTexture {
        let key = "selection"
        if let cached = cache[key] { return cached }
        let texture = SKTexture(
            image: diamondImage(fill: UIColor(red: 1.0, green: 0.95, blue: 0.35, alpha: 0.55))
        )
        cache[key] = texture
        return texture
    }
}

private extension UIColor {

    func darkened(by amount: CGFloat = 0.18) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: max(0, brightness - amount), alpha: alpha)
    }

    func lightened(by amount: CGFloat = 0.14) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness + amount), alpha: alpha)
    }
}
