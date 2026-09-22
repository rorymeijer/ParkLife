import Foundation

/// A player construction intent. Intents are validated and applied by `BuildService`; nothing
/// outside that service mutates the tile map or the building store.
public enum BuildAction {
    case placeBuilding(definitionID: String, origin: GridPoint, rotation: Rotation)
    case placePath(definitionID: String, tiles: [GridPoint])
    case demolishBuilding(BuildingID)
    case removePath(tiles: [GridPoint])
}

public enum BuildFailure: String, Codable {
    case unknownDefinition
    case outOfBounds
    case tileOccupied
    case terrainNotBuildable
    case notEnoughMoney
    case notResearched
    case unitIsOccupied
    case nothingToRemove
    case entranceCannotBeDemolished

    public var localizationKey: String { "buildError.\(rawValue)" }
}

/// Result of checking an action before it is applied — this is what drives the green/red
/// placement preview.
public struct BuildValidation {

    public let isValid: Bool
    public let cost: Money
    public let failure: BuildFailure?
    /// Tiles that are the reason the action is invalid, for highlighting in the preview.
    public let offendingTiles: [GridPoint]
    /// Placement is legal but the object will not be usable until a path reaches it.
    public let warnsNoPathAccess: Bool

    public static func valid(cost: Money, warnsNoPathAccess: Bool = false) -> BuildValidation {
        BuildValidation(
            isValid: true,
            cost: cost,
            failure: nil,
            offendingTiles: [],
            warnsNoPathAccess: warnsNoPathAccess
        )
    }

    public static func invalid(_ failure: BuildFailure, cost: Money = .zero, tiles: [GridPoint] = []) -> BuildValidation {
        BuildValidation(
            isValid: false,
            cost: cost,
            failure: failure,
            offendingTiles: tiles,
            warnsNoPathAccess: false
        )
    }
}

/// Enough information to undo an applied action.
public struct BuildRecord {

    public enum Kind {
        case placedBuilding(BuildingID)
        case placedPath(tiles: [GridPoint], previousSurfaces: [SurfaceType])
        case demolishedBuilding(instance: BuildingInstance)
        case removedPath(tiles: [GridPoint], previousSurfaces: [SurfaceType])
    }

    public let kind: Kind
    /// The intent that produced this record, kept so redo simply re-runs it.
    public let action: BuildAction
    /// Net cash change the action caused; undo reverses exactly this.
    public let cashDelta: Money
    public let tick: Tick

    public init(kind: Kind, action: BuildAction, cashDelta: Money, tick: Tick) {
        self.kind = kind
        self.action = action
        self.cashDelta = cashDelta
        self.tick = tick
    }
}

/// Undo/redo stack for construction.
public struct BuildHistory {

    public private(set) var undoStack: [BuildRecord]
    public private(set) var redoStack: [BuildRecord]
    public var limit: Int = 50

    public init() {
        self.undoStack = []
        self.redoStack = []
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func push(_ record: BuildRecord) {
        undoStack.append(record)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        // A fresh action invalidates the redo branch.
        redoStack.removeAll()
    }

    public mutating func popUndo() -> BuildRecord? {
        undoStack.popLast()
    }

    public mutating func pushRedo(_ record: BuildRecord) {
        redoStack.append(record)
    }

    public mutating func popRedo() -> BuildRecord? {
        redoStack.popLast()
    }

    public mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
