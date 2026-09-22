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

    /// A simple extruded block sized to the footprint, tinted by category.
    static func buildingTexture(art: String, category: BuildingCategory, footprint: GridSize) -> SKTexture {
        let key = "building-\(art)-\(footprint.width)x\(footprint.height)"
        if let cached = cache[key] { return cached }

        let baseWidth = tileWidth * CGFloat(footprint.width + footprint.height) / 2
        let baseHeight = tileHeight * CGFloat(footprint.width + footprint.height) / 2
        let bodyHeight = height(for: category)
        let size = CGSize(width: baseWidth, height: baseHeight + bodyHeight)

        let tint = colour(for: category, seed: art)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let halfW = baseWidth / 2
            let halfH = baseHeight / 2

            // Roof: the isometric diamond of the footprint.
            let roof = UIBezierPath()
            roof.move(to: CGPoint(x: halfW, y: 0))
            roof.addLine(to: CGPoint(x: baseWidth, y: halfH))
            roof.addLine(to: CGPoint(x: halfW, y: baseHeight))
            roof.addLine(to: CGPoint(x: 0, y: halfH))
            roof.close()
            tint.lightened().setFill()
            roof.fill()

            // Left wall.
            let left = UIBezierPath()
            left.move(to: CGPoint(x: 0, y: halfH))
            left.addLine(to: CGPoint(x: halfW, y: baseHeight))
            left.addLine(to: CGPoint(x: halfW, y: baseHeight + bodyHeight))
            left.addLine(to: CGPoint(x: 0, y: halfH + bodyHeight))
            left.close()
            tint.darkened().setFill()
            left.fill()

            // Right wall.
            let right = UIBezierPath()
            right.move(to: CGPoint(x: baseWidth, y: halfH))
            right.addLine(to: CGPoint(x: halfW, y: baseHeight))
            right.addLine(to: CGPoint(x: halfW, y: baseHeight + bodyHeight))
            right.addLine(to: CGPoint(x: baseWidth, y: halfH + bodyHeight))
            right.close()
            tint.setFill()
            right.fill()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
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
        // A stable per-art hue jitter so neighbouring cottages are not identical.
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
