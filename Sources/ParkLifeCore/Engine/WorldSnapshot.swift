import Foundation

/// An immutable view of the world for rendering and the HUD.
///
/// The renderer receives one of these and nothing else — it has no reference to `World` and cannot
/// mutate simulation state even by accident (brief §41, Rule 3).
public struct WorldSnapshot {

    public struct TileSample {
        public let point: GridPoint
        public let terrain: TerrainType
        public let surface: SurfaceType
        public let elevation: Int
        public let scenery: Double
        public let congestion: Double
        public let buildingID: BuildingID?
    }

    public struct BuildingSprite {
        public let id: BuildingID
        public let definitionID: String
        public let art: String
        public let origin: GridPoint
        public let footprint: GridSize
        public let rotation: Rotation
        public let condition: Double
        public let category: BuildingCategory
        /// Localisation key describing the current state, e.g. `unitState.occupied`.
        public let stateKey: String?
        public let queueLength: Int
    }

    public struct GuestSprite {
        public let id: GuestID
        public let position: WorldPoint
        public let ageBand: AgeBand
        public let happiness: Double
        public let activityKey: String
        public let isVisible: Bool
    }

    public struct StaffSprite {
        public let id: StaffID
        public let position: WorldPoint
        public let roleID: String
        public let isWorking: Bool
    }

    public struct HUD {
        public let date: GameDate
        public let speed: GameSpeed
        public let cash: Money
        public let guestsOnSite: Int
        public let occupancyPercent: Int
        public let reputationStars: Double
        public let averageHappiness: Double
        public let weather: WeatherCondition
        public let temperature: Double
        public let unreadNotifications: Int
        public let unitsReady: Int
        public let unitsDirty: Int
        public let arrivalsToday: Int
        public let departuresToday: Int
    }

    public let tick: Tick
    public let hud: HUD
    public let tiles: [TileSample]
    public let buildings: [BuildingSprite]
    public let guests: [GuestSprite]
    public let staff: [StaffSprite]

    public init(
        tick: Tick,
        hud: HUD,
        tiles: [TileSample],
        buildings: [BuildingSprite],
        guests: [GuestSprite],
        staff: [StaffSprite]
    ) {
        self.tick = tick
        self.hud = hud
        self.tiles = tiles
        self.buildings = buildings
        self.guests = guests
        self.staff = staff
    }
}

extension World {

    /// Builds a render snapshot.
    ///
    /// - Parameter viewport: tiles to include. Passing `nil` includes the whole map, which is only
    ///   appropriate for tests and the minimap — the renderer always passes the visible rect so
    ///   node count is tied to the screen, not to park size.
    public func snapshot(viewport: GridRect? = nil) -> WorldSnapshot {
        let rect = (viewport ?? GridRect(x: 0, y: 0, width: tiles.size.width, height: tiles.size.height))
            .clamped(to: tiles.size)

        var tileSamples: [WorldSnapshot.TileSample] = []
        if !rect.isEmpty {
            tileSamples.reserveCapacity(rect.size.tileCount)
            for y in rect.minY...rect.maxY {
                for x in rect.minX...rect.maxX {
                    let point = GridPoint(x: x, y: y)
                    tileSamples.append(
                        WorldSnapshot.TileSample(
                            point: point,
                            terrain: tiles.terrain(at: point),
                            surface: tiles.surface(at: point),
                            elevation: tiles.elevation(at: point),
                            scenery: tiles.scenery(at: point),
                            congestion: navigation.congestionLevel(at: point),
                            buildingID: tiles.building(at: point)
                        )
                    )
                }
            }
        }

        var buildingSprites: [WorldSnapshot.BuildingSprite] = []
        for id in buildings.sortedIDs {
            guard let instance = buildings[id], let definition = catalog.buildings[instance.definitionID] else { continue }
            let footprint = instance.rotation.apply(to: definition.footprint)
            let footprintRect = GridRect(origin: instance.origin, size: footprint)
            guard rect.intersects(footprintRect) else { continue }
            buildingSprites.append(
                WorldSnapshot.BuildingSprite(
                    id: id,
                    definitionID: definition.id,
                    art: definition.art,
                    origin: instance.origin,
                    footprint: footprint,
                    rotation: instance.rotation,
                    condition: instance.condition,
                    category: definition.category,
                    stateKey: instance.accommodation?.state.localizationKey,
                    queueLength: instance.facility?.queue.count ?? 0
                )
            )
        }

        var guestSprites: [WorldSnapshot.GuestSprite] = []
        for guest in guests.items {
            guard guest.activity != .offPark, guest.activity != .departed else { continue }
            let visible = rect.contains(guest.tile)
            guard visible || viewport == nil else { continue }
            guestSprites.append(
                WorldSnapshot.GuestSprite(
                    id: guest.id,
                    position: guest.position,
                    ageBand: guest.ageBand,
                    happiness: guest.happiness,
                    activityKey: guest.activity.localizationKey,
                    isVisible: visible
                )
            )
        }

        var staffSprites: [WorldSnapshot.StaffSprite] = []
        for member in staff.items {
            let visible = rect.contains(member.position.tile)
            guard visible || viewport == nil else { continue }
            var working = false
            if case .working = member.activity { working = true }
            staffSprites.append(
                WorldSnapshot.StaffSprite(
                    id: member.id,
                    position: member.position,
                    roleID: member.roleID,
                    isWorking: working
                )
            )
        }

        let counts = AccommodationSystem.unitCounts(in: self)
        let hud = WorldSnapshot.HUD(
            date: date,
            speed: clock.speed,
            cash: cash,
            guestsOnSite: guestsOnSite,
            occupancyPercent: Int((occupancyRate * 100).rounded()),
            reputationStars: reputation.starRating,
            averageHappiness: averageGuestHappiness,
            weather: weather.condition,
            temperature: weather.temperature,
            unreadNotifications: notifications.unreadCount,
            unitsReady: counts[.ready] ?? 0,
            unitsDirty: (counts[.dirty] ?? 0) + (counts[.cleaning] ?? 0),
            arrivalsToday: bookkeeping.arrivalsToday,
            departuresToday: bookkeeping.departuresToday
        )

        return WorldSnapshot(
            tick: tick,
            hud: hud,
            tiles: tileSamples,
            buildings: buildingSprites,
            guests: guestSprites,
            staff: staffSprites
        )
    }
}
