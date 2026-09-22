import SpriteKit
import UIKit
import ParkLifeCore

/// Draws the park.
///
/// The scene owns no simulation state whatsoever: it is handed a `WorldSnapshot` and turns it into
/// sprites. Swapping SpriteKit for something else later means rewriting this one file.
final class ParkScene: SKScene {

    // MARK: Dependencies

    private weak var session: GameSession?

    // MARK: Layers

    private let worldNode = SKNode()
    private let terrainLayer = SKNode()
    private let overlayLayer = SKNode()
    private let objectLayer = SKNode()
    private let highlightLayer = SKNode()

    private var terrainPool: SpriteNodePool!
    private var overlayPool: SpriteNodePool!
    private var buildingPool: SpriteNodePool!
    private var peoplePool: SpriteNodePool!
    private var highlightPool: SpriteNodePool!

    // MARK: Camera

    private let cameraNode = SKCameraNode()
    private var zoom: CGFloat = 1.0
    private let minimumZoom: CGFloat = 0.35
    private let maximumZoom: CGFloat = 2.2
    private var rotation: Rotation = .none
    private var mapSize = GridSize(width: 96, height: 96)

    private var projection: IsometricProjection {
        IsometricProjection(mapSize: mapSize, rotation: rotation)
    }

    /// Tile currently under the finger, used for the build preview.
    private var hoveredTile: GridPoint?
    private var dragTiles: [GridPoint] = []

    // MARK: Setup

    init(size: CGSize, session: GameSession) {
        self.session = session
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.42, green: 0.62, blue: 0.78, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("ParkScene is created in code")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        MainActor.assumeIsolated {
            configureIfNeeded(view: view)
        }
    }

    private var isConfigured = false

    private func configureIfNeeded(view: SKView) {
        guard !isConfigured else { return }
        isConfigured = true

        addChild(worldNode)
        worldNode.addChild(terrainLayer)
        worldNode.addChild(overlayLayer)
        worldNode.addChild(objectLayer)
        worldNode.addChild(highlightLayer)

        terrainPool = SpriteNodePool(parent: terrainLayer, prewarm: 900)
        overlayPool = SpriteNodePool(parent: overlayLayer, prewarm: 200)
        buildingPool = SpriteNodePool(parent: objectLayer, prewarm: 200)
        peoplePool = SpriteNodePool(parent: objectLayer, prewarm: 250)
        highlightPool = SpriteNodePool(parent: highlightLayer, prewarm: 64)

        camera = cameraNode
        cameraNode.setScale(zoom)
        addChild(cameraNode)

        if let world = session?.world {
            mapSize = world.tiles.size
            centre(on: world.entranceTile)
        }

        installGestures(on: view)
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        MainActor.assumeIsolated {
            guard let session else { return }
            session.viewport = visibleTileRect()
            session.advance(to: currentTime)
            if let snapshot = session.snapshot {
                apply(snapshot, session: session)
            }
        }
    }

    /// Turns a snapshot into sprites. This is the entire simulation→rendering boundary.
    private func apply(_ snapshot: WorldSnapshot, session: GameSession) {
        let projection = self.projection

        terrainPool.beginFrame()
        overlayPool.beginFrame()
        buildingPool.beginFrame()
        peoplePool.beginFrame()
        highlightPool.beginFrame()

        // Terrain.
        for tile in snapshot.tiles {
            let node = terrainPool.claim()
            node.texture = PlaceholderArt.terrainTexture(tile.terrain, surface: tile.surface)
            node.size = CGSize(width: PlaceholderArt.tileWidth, height: PlaceholderArt.tileHeight)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let screen = projection.project(WorldPoint(tile.point), elevation: tile.elevation)
            node.position = CGPoint(x: screen.x, y: -screen.y)
            node.zPosition = projection.depth(for: WorldPoint(tile.point), layer: 0)
            node.alpha = 1

            if let value = session.activeOverlay.value(for: tile, snapshot: snapshot) {
                let overlay = overlayPool.claim()
                overlay.texture = node.texture
                overlay.size = node.size
                overlay.position = node.position
                overlay.zPosition = node.zPosition + 1
                overlay.color = UIColor(session.activeOverlay.colour(for: value))
                overlay.colorBlendFactor = 0.75
                overlay.alpha = 0.7
            }
        }

        // Buildings, drawn back to front by their footprint's far corner.
        for building in snapshot.buildings {
            let node = buildingPool.claim()
            node.texture = PlaceholderArt.buildingTexture(
                art: building.art,
                category: building.category,
                footprint: building.footprint
            )
            node.size = node.texture?.size() ?? .zero
            node.anchorPoint = CGPoint(x: 0.5, y: 0.0)

            // Anchor on the footprint's north corner so the diamond lines up with the tiles.
            let anchor = WorldPoint(
                x: Double(building.origin.x),
                y: Double(building.origin.y + building.footprint.height)
            )
            let screen = projection.project(anchor)
            node.position = CGPoint(x: screen.x, y: -screen.y)
            node.zPosition = projection.depth(
                for: WorldPoint(
                    x: Double(building.origin.x + building.footprint.width),
                    y: Double(building.origin.y + building.footprint.height)
                ),
                layer: 10
            )
            // Buildings in poor repair visibly fade.
            node.alpha = 0.55 + 0.45 * building.condition
            node.colorBlendFactor = 0
            if case .building(let selected) = session.selection, selected == building.id {
                node.color = .white
                node.colorBlendFactor = 0.35
            }
        }

        // Guests and staff.
        for guest in snapshot.guests {
            let node = peoplePool.claim()
            node.texture = PlaceholderArt.guestTexture(ageBand: guest.ageBand)
            node.size = node.texture?.size() ?? .zero
            node.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            let screen = projection.project(guest.position)
            node.position = CGPoint(x: screen.x, y: -screen.y)
            node.zPosition = projection.depth(for: guest.position, layer: 20)
            // Unhappy guests read as duller even before you tap them.
            node.colorBlendFactor = CGFloat(1.0 - guest.happiness) * 0.5
            node.color = .darkGray
        }

        for member in snapshot.staff {
            let node = peoplePool.claim()
            node.texture = PlaceholderArt.staffTexture()
            node.size = node.texture?.size() ?? .zero
            node.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            let screen = projection.project(member.position)
            node.position = CGPoint(x: screen.x, y: -screen.y)
            node.zPosition = projection.depth(for: member.position, layer: 21)
            node.colorBlendFactor = 0
        }

        drawHighlights(session: session, projection: projection, snapshot: snapshot)

        terrainPool.endFrame()
        overlayPool.endFrame()
        buildingPool.endFrame()
        peoplePool.endFrame()
        highlightPool.endFrame()
    }

    private func drawHighlights(session: GameSession, projection: IsometricProjection, snapshot: WorldSnapshot) {
        var tiles: [(GridPoint, Bool)] = []

        if session.buildMode != .off, let hovered = hoveredTile {
            let validation = session.previewValidation(at: hovered)
            let valid = validation?.isValid ?? false
            if case .building(let definitionID, let rotation) = session.buildMode,
               let definition = session.world?.catalog.buildings[definitionID] {
                let footprint = rotation.apply(to: definition.footprint)
                for point in GridRect(origin: hovered, size: footprint).points {
                    tiles.append((point, valid))
                }
            } else {
                tiles.append((hovered, valid))
            }
            for point in dragTiles {
                tiles.append((point, true))
            }
        }

        if case .tile(let point) = session.selection {
            tiles.append((point, true))
        }

        for (point, valid) in tiles {
            let node = highlightPool.claim()
            node.texture = PlaceholderArt.highlightTexture(valid: valid)
            node.size = CGSize(width: PlaceholderArt.tileWidth, height: PlaceholderArt.tileHeight)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let elevation = snapshot.tiles.first(where: { $0.point == point })?.elevation ?? 0
            let screen = projection.project(WorldPoint(point), elevation: elevation)
            node.position = CGPoint(x: screen.x, y: -screen.y)
            node.zPosition = projection.depth(for: WorldPoint(point), layer: 5)
        }
    }

    // MARK: - Camera

    private func centre(on tile: GridPoint) {
        let screen = projection.project(WorldPoint(tile))
        cameraNode.position = CGPoint(x: screen.x, y: -screen.y)
    }

    /// The tile rectangle currently visible, with a margin so panning does not pop.
    private func visibleTileRect() -> GridRect {
        let halfWidth = size.width * zoom / 2
        let halfHeight = size.height * zoom / 2
        let corners = [
            CGPoint(x: cameraNode.position.x - halfWidth, y: cameraNode.position.y - halfHeight),
            CGPoint(x: cameraNode.position.x + halfWidth, y: cameraNode.position.y - halfHeight),
            CGPoint(x: cameraNode.position.x - halfWidth, y: cameraNode.position.y + halfHeight),
            CGPoint(x: cameraNode.position.x + halfWidth, y: cameraNode.position.y + halfHeight)
        ]
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for corner in corners {
            let world = projection.unproject(ScreenPoint(x: Double(corner.x), y: Double(-corner.y)))
            let tile = world.tile
            minX = Swift.min(minX, tile.x)
            minY = Swift.min(minY, tile.y)
            maxX = Swift.max(maxX, tile.x)
            maxY = Swift.max(maxY, tile.y)
        }
        let margin = 3
        return GridRect(
            x: minX - margin,
            y: minY - margin,
            width: (maxX - minX) + margin * 2 + 1,
            height: (maxY - minY) + margin * 2 + 1
        ).clamped(to: mapSize)
    }

    func rotateCamera() {
        MainActor.assumeIsolated {
            rotation = rotation.next
        }
    }

    // MARK: - Input

    private func installGestures(on view: SKView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)

        let draw = UILongPressGestureRecognizer(target: self, action: #selector(handleDraw(_:)))
        draw.minimumPressDuration = 0.12
        draw.allowableMovement = .greatestFiniteMagnitude
        view.addGestureRecognizer(draw)
        draw.require(toFail: tap)
    }

    @objc private func handlePan(_ recogniser: UIPanGestureRecognizer) {
        MainActor.assumeIsolated {
            guard let view = self.view else { return }
            let translation = recogniser.translation(in: view)
            cameraNode.position.x -= translation.x * zoom
            cameraNode.position.y += translation.y * zoom
            recogniser.setTranslation(.zero, in: view)
        }
    }

    @objc private func handlePinch(_ recogniser: UIPinchGestureRecognizer) {
        MainActor.assumeIsolated {
            guard recogniser.state == .changed || recogniser.state == .ended else { return }
            zoom = Swift.min(Swift.max(zoom / recogniser.scale, minimumZoom), maximumZoom)
            cameraNode.setScale(zoom)
            recogniser.scale = 1
        }
    }

    @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
        MainActor.assumeIsolated {
            guard let view = self.view, let session else { return }
            let location = recogniser.location(in: view)
            guard let tile = tile(atViewPoint: location) else { return }
            hoveredTile = tile
            session.handleTap(on: tile)
        }
    }

    @objc private func handleDraw(_ recogniser: UILongPressGestureRecognizer) {
        MainActor.assumeIsolated {
            guard let view = self.view, let session else { return }
            let location = recogniser.location(in: view)
            guard let tile = tile(atViewPoint: location) else { return }

            switch recogniser.state {
            case .began:
                dragTiles = [tile]
                hoveredTile = tile
            case .changed:
                hoveredTile = tile
                if dragTiles.last != tile {
                    dragTiles.append(tile)
                }
            case .ended, .cancelled, .failed:
                if case .path = session.buildMode, dragTiles.count > 1 {
                    session.handleDrag(over: dragTiles)
                } else if dragTiles.count <= 1 {
                    session.handleTap(on: tile)
                }
                dragTiles.removeAll()
            default:
                break
            }
        }
    }

    private func tile(atViewPoint point: CGPoint) -> GridPoint? {
        let scenePoint = convertPoint(fromView: point)
        let elevations = session?.world?.tiles
        return projection.tile(
            at: ScreenPoint(x: Double(scenePoint.x), y: Double(-scenePoint.y)),
            elevationLookup: { elevations?.elevation(at: $0) ?? 0 }
        )
    }

    // MARK: - Diagnostics

    var nodeStatistics: (terrain: Int, buildings: Int, people: Int) {
        (terrainPool?.activeCount ?? 0, buildingPool?.activeCount ?? 0, peoplePool?.activeCount ?? 0)
    }
}
