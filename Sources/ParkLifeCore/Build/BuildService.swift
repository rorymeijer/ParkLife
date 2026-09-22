import Foundation

/// Validates and applies construction.
///
/// Every build goes through here, which is what makes placement previews, costs, undo and the
/// path-network rebuild consistent — the UI cannot place a building by poking the tile map.
public enum BuildService {

    // MARK: - Validation

    public static func validate(_ action: BuildAction, in world: World) -> BuildValidation {
        switch action {
        case .placeBuilding(let definitionID, let origin, let rotation):
            return validatePlaceBuilding(definitionID: definitionID, origin: origin, rotation: rotation, world: world)
        case .placePath(let definitionID, let tiles):
            return validatePlacePath(definitionID: definitionID, tiles: tiles, world: world)
        case .demolishBuilding(let id):
            return validateDemolish(id: id, world: world)
        case .removePath(let tiles):
            return validateRemovePath(tiles: tiles, world: world)
        }
    }

    private static func validatePlaceBuilding(
        definitionID: String,
        origin: GridPoint,
        rotation: Rotation,
        world: World
    ) -> BuildValidation {
        guard let definition = world.catalog.buildings[definitionID] else {
            return .invalid(.unknownDefinition)
        }
        if let required = definition.researchID, !world.completedResearch.contains(required) {
            return .invalid(.notResearched)
        }
        let rect = GridRect(origin: origin, size: rotation.apply(to: definition.footprint))
        var offending: [GridPoint] = []
        for point in rect.points {
            guard world.tiles.contains(point) else {
                return .invalid(.outOfBounds, cost: definition.constructionCost, tiles: rect.points)
            }
            if world.tiles.building(at: point) != nil || world.tiles.surface(at: point) != .none {
                offending.append(point)
            } else if !world.tiles.terrain(at: point).isBuildable {
                offending.append(point)
            }
        }
        if !offending.isEmpty {
            let failure: BuildFailure = world.tiles.terrain(at: offending[0]).isBuildable
                ? .tileOccupied
                : .terrainNotBuildable
            return .invalid(failure, cost: definition.constructionCost, tiles: offending)
        }
        if world.cash < definition.constructionCost {
            return .invalid(.notEnoughMoney, cost: definition.constructionCost, tiles: [])
        }

        // Path access is a warning, not a rejection: players build a cottage first and connect it
        // afterwards, and blocking that is pure friction. Until it is connected the building simply
        // is not operational, and a notification says so.
        var warns = false
        if definition.requiresPathAdjacency {
            let entrances = definition.entranceOffsets.map { offset -> GridPoint in
                let rotated = rotation.apply(to: offset, in: definition.footprint)
                return GridPoint(x: origin.x + rotated.x, y: origin.y + rotated.y)
            }
            warns = !entrances.contains { point in
                point.orthogonalNeighbours.contains { world.tiles.isWalkable(at: $0) }
            }
        }
        return .valid(cost: definition.constructionCost, warnsNoPathAccess: warns)
    }

    private static func validatePlacePath(
        definitionID: String,
        tiles: [GridPoint],
        world: World
    ) -> BuildValidation {
        guard let definition = world.catalog.paths[definitionID] else {
            return .invalid(.unknownDefinition)
        }
        if let required = definition.researchID, !world.completedResearch.contains(required) {
            return .invalid(.notResearched)
        }
        var buildable: [GridPoint] = []
        var offending: [GridPoint] = []
        for point in tiles {
            guard world.tiles.contains(point) else {
                offending.append(point)
                continue
            }
            if world.tiles.building(at: point) != nil {
                offending.append(point)
                continue
            }
            let terrain = world.tiles.terrain(at: point)
            // Bridges are the only surface that may cross water.
            let allowed = terrain.isBuildable || (definition.surface == .bridge && terrain == .water)
            guard allowed else {
                offending.append(point)
                continue
            }
            if world.tiles.surface(at: point) != definition.surface {
                buildable.append(point)
            }
        }
        if buildable.isEmpty {
            return .invalid(offending.isEmpty ? .nothingToRemove : .terrainNotBuildable, tiles: offending)
        }
        let cost = definition.costPerTile * buildable.count
        if world.cash < cost {
            return .invalid(.notEnoughMoney, cost: cost, tiles: [])
        }
        return .valid(cost: cost)
    }

    private static func validateDemolish(id: BuildingID, world: World) -> BuildValidation {
        guard let instance = world.buildings[id], let definition = world.definition(of: instance) else {
            return .invalid(.nothingToRemove)
        }
        if definition.facility?.kind == .entrance {
            return .invalid(.entranceCannotBeDemolished)
        }
        if let accommodation = instance.accommodation, accommodation.state == .occupied {
            return .invalid(.unitIsOccupied)
        }
        if let facility = instance.facility, !facility.occupants.isEmpty || !facility.queue.isEmpty {
            return .invalid(.unitIsOccupied)
        }
        let refund = definition.constructionCost.scaled(by: definition.demolitionRefundFraction * instance.condition)
        return .valid(cost: Money(cents: -refund.cents))
    }

    private static func validateRemovePath(tiles: [GridPoint], world: World) -> BuildValidation {
        let removable = tiles.filter { world.tiles.contains($0) && world.tiles.surface(at: $0) != .none }
        guard !removable.isEmpty else {
            return .invalid(.nothingToRemove)
        }
        // Refund is based on the cheapest matching definition; paths are cheap and this keeps the
        // accounting honest without storing which definition laid each tile.
        var refund = Money.zero
        for point in removable {
            let surface = world.tiles.surface(at: point)
            if let definition = world.catalog.pathIDs.compactMap({ world.catalog.paths[$0] })
                .first(where: { $0.surface == surface }) {
                refund += definition.costPerTile.scaled(by: definition.demolitionRefundFraction)
            }
        }
        return .valid(cost: Money(cents: -refund.cents))
    }

    // MARK: - Application

    /// Applies an action. Returns `nil` when validation fails.
    @discardableResult
    public static func apply(_ action: BuildAction, to world: inout World) -> BuildRecord? {
        let validation = validate(action, in: world)
        guard validation.isValid else {
            ParkLog.shared.debug(.build, "Rejected \(action) — \(validation.failure?.rawValue ?? "unknown")")
            return nil
        }

        switch action {
        case .placeBuilding(let definitionID, let origin, let rotation):
            return applyPlaceBuilding(
                definitionID: definitionID,
                origin: origin,
                rotation: rotation,
                cost: validation.cost,
                warnsNoPathAccess: validation.warnsNoPathAccess,
                world: &world
            )

        case .placePath(let definitionID, let tiles):
            return applyPlacePath(definitionID: definitionID, tiles: tiles, world: &world)

        case .demolishBuilding(let id):
            return applyDemolish(id: id, world: &world)

        case .removePath(let tiles):
            return applyRemovePath(tiles: tiles, world: &world)
        }
    }

    private static func applyPlaceBuilding(
        definitionID: String,
        origin: GridPoint,
        rotation: Rotation,
        cost: Money,
        warnsNoPathAccess: Bool,
        world: inout World
    ) -> BuildRecord? {
        guard let definition = world.catalog.buildings[definitionID] else { return nil }
        let id = world.ids.next(BuildingID.self)
        let instance = BuildingInstance(
            id: id,
            definitionID: definitionID,
            origin: origin,
            rotation: rotation,
            builtAtTick: world.tick,
            accommodation: definition.isAccommodation ? AccommodationState() : nil,
            facility: definition.isFacility ? FacilityState() : nil
        )
        let rect = instance.footprintRect(definition: definition)
        for point in rect.points {
            world.tiles.setBuilding(id, at: point)
        }
        world.buildings.insert(instance)
        world.spend(cost, category: .construction, reference: id.raw)
        world.rebuildDerivedState()

        if warnsNoPathAccess {
            world.notifications.post(
                priority: .warning,
                text: LocalizedText("notification.buildingNotConnected", [.text(definition.nameKey)]),
                groupingKey: "notConnected",
                tick: world.tick,
                subject: id.raw,
                allocator: &world.ids
            )
        }
        ParkLog.shared.info(.build, "Placed \(definitionID) at \(origin)")
        return BuildRecord(
            kind: .placedBuilding(id),
            action: .placeBuilding(definitionID: definitionID, origin: origin, rotation: rotation),
            cashDelta: Money(cents: -cost.cents),
            tick: world.tick
        )
    }

    private static func applyPlacePath(
        definitionID: String,
        tiles: [GridPoint],
        world: inout World
    ) -> BuildRecord? {
        guard let definition = world.catalog.paths[definitionID] else { return nil }
        var changed: [GridPoint] = []
        var previous: [SurfaceType] = []
        for point in tiles {
            guard world.tiles.contains(point), world.tiles.building(at: point) == nil else { continue }
            let terrain = world.tiles.terrain(at: point)
            let allowed = terrain.isBuildable || (definition.surface == .bridge && terrain == .water)
            guard allowed else { continue }
            let existing = world.tiles.surface(at: point)
            guard existing != definition.surface else { continue }
            changed.append(point)
            previous.append(existing)
            world.tiles.setSurface(definition.surface, at: point)
        }
        guard !changed.isEmpty else { return nil }
        let cost = definition.costPerTile * changed.count
        world.spend(cost, category: .construction)
        world.rebuildDerivedState()
        ParkLog.shared.info(.build, "Laid \(changed.count) tiles of \(definitionID)")
        return BuildRecord(
            kind: .placedPath(tiles: changed, previousSurfaces: previous),
            action: .placePath(definitionID: definitionID, tiles: changed),
            cashDelta: Money(cents: -cost.cents),
            tick: world.tick
        )
    }

    private static func applyDemolish(id: BuildingID, world: inout World) -> BuildRecord? {
        guard let instance = world.buildings[id], let definition = world.definition(of: instance) else { return nil }
        let refund = definition.constructionCost.scaled(by: definition.demolitionRefundFraction * instance.condition)
        for point in instance.footprintRect(definition: definition).points {
            world.tiles.setBuilding(nil, at: point)
        }
        world.buildings.remove(id)
        world.navigation.removeDestination(id)
        world.earn(refund, category: .extras, reference: id.raw)
        world.rebuildDerivedState()
        ParkLog.shared.info(.build, "Demolished \(definition.id)")
        return BuildRecord(
            kind: .demolishedBuilding(instance: instance),
            action: .demolishBuilding(id),
            cashDelta: refund,
            tick: world.tick
        )
    }

    private static func applyRemovePath(tiles: [GridPoint], world: inout World) -> BuildRecord? {
        var changed: [GridPoint] = []
        var previous: [SurfaceType] = []
        var refund = Money.zero
        for point in tiles {
            guard world.tiles.contains(point) else { continue }
            let surface = world.tiles.surface(at: point)
            guard surface != .none else { continue }
            changed.append(point)
            previous.append(surface)
            if let definition = world.catalog.pathIDs.compactMap({ world.catalog.paths[$0] })
                .first(where: { $0.surface == surface }) {
                refund += definition.costPerTile.scaled(by: definition.demolitionRefundFraction)
            }
            world.tiles.setSurface(.none, at: point)
        }
        guard !changed.isEmpty else { return nil }
        world.earn(refund, category: .extras)
        world.rebuildDerivedState()
        return BuildRecord(
            kind: .removedPath(tiles: changed, previousSurfaces: previous),
            action: .removePath(tiles: changed),
            cashDelta: refund,
            tick: world.tick
        )
    }

    // MARK: - Undo / redo

    /// Reverses a record. Cash is restored exactly, so undo never leaks or prints money.
    @discardableResult
    public static func undo(_ record: BuildRecord, in world: inout World) -> Bool {
        switch record.kind {
        case .placedBuilding(let id):
            guard let instance = world.buildings[id], let definition = world.definition(of: instance) else { return false }
            for point in instance.footprintRect(definition: definition).points {
                world.tiles.setBuilding(nil, at: point)
            }
            world.buildings.remove(id)
            world.navigation.removeDestination(id)

        case .placedPath(let tiles, let previousSurfaces):
            for (offset, point) in tiles.enumerated() {
                world.tiles.setSurface(previousSurfaces[offset], at: point)
            }

        case .demolishedBuilding(let instance):
            guard let definition = world.definition(of: instance) else { return false }
            for point in instance.footprintRect(definition: definition).points {
                world.tiles.setBuilding(instance.id, at: point)
            }
            world.buildings.insert(instance)

        case .removedPath(let tiles, let previousSurfaces):
            for (offset, point) in tiles.enumerated() {
                world.tiles.setSurface(previousSurfaces[offset], at: point)
            }
        }
        // Reverse the exact cash movement rather than recomputing a refund.
        world.cash -= record.cashDelta
        world.rebuildDerivedState()
        return true
    }

    /// Re-applies a previously undone record by re-running the original intent.
    ///
    /// Re-placing a building allocates a fresh `BuildingID`; the object is identical but its
    /// identity is new, which is why redo returns the new record rather than reusing the old one.
    public static func redo(_ record: BuildRecord, in world: inout World) -> BuildRecord? {
        apply(record.action, to: &world)
    }
}
