import Foundation
import Combine
import SwiftUI
import OSLog
import ParkLifeCore

/// The app-side owner of the simulation.
///
/// This is the only place that touches `SimulationEngine`. Views read published values and send
/// intents; they never reach into the world. That boundary is what keeps simulation logic out of
/// SwiftUI (brief §41, Rule 3).
@MainActor
final class GameSession: ObservableObject {

    // MARK: Published state for the UI

    @Published private(set) var snapshot: WorldSnapshot?
    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?
    @Published var selection: Selection = .none
    @Published var buildMode: BuildMode = .off
    @Published var activeOverlay: MapOverlay = .none
    @Published private(set) var lastIntentRejection: String?

    enum Selection: Equatable {
        case none
        case building(BuildingID)
        case guest(GuestID)
        case staff(StaffID)
        case tile(GridPoint)
    }

    enum BuildMode: Equatable {
        case off
        case path(String)
        case building(String, Rotation)
        case demolish
    }

    // MARK: Simulation

    private(set) var engine: SimulationEngine?
    private(set) var catalog: ContentCatalog?
    private var store: SaveStore?

    private var lastFrameTime: TimeInterval?
    private var playTimeSeconds: Int = 0
    private var autosaveAccumulator: TimeInterval = 0
    /// Autosave every five real minutes.
    private let autosaveInterval: TimeInterval = 300

    /// Viewport the renderer is currently showing, used to keep snapshots small.
    var viewport: GridRect?

    private let logger = Logger(subsystem: "com.parklife.game", category: "session")

    init() {
        ParkLog.shared.addSink(OSLogSink())
        #if DEBUG
        ParkLog.shared.setMinimumLevel(.debug)
        #else
        ParkLog.shared.setMinimumLevel(.warning)
        #endif
        start()
    }

    // MARK: - Lifecycle

    func start() {
        do {
            let catalog = try ContentCatalog.bundled()
            self.catalog = catalog
            self.store = try? SaveStore(directory: SaveStore.defaultDirectory())

            let world = try GameSetup.makeDemoPark(catalog: catalog)
            let engine = SimulationEngine(world: world)
            self.engine = engine

            #if DEBUG
            applyScreenshotOptions(to: engine)
            #endif

            refreshSnapshot()
            isReady = true

            #if DEBUG
            if ScreenshotOptions.isActive {
                // The capture script waits for this line rather than guessing how long the
                // warm-up takes. Without it a slow simulator gets photographed mid-load.
                print("PARKLIFE_SCREENSHOT_READY")
                fflush(stdout)
            }
            #endif
        } catch {
            loadError = String(describing: error)
            logger.error("Could not start a game: \(String(describing: error))")
        }
    }

    #if DEBUG
    /// Puts the session into the state an automated screenshot run asked for.
    private func applyScreenshotOptions(to engine: SimulationEngine) {
        guard ScreenshotOptions.isActive else { return }

        // Run the simulation forward so the park is populated — an empty park makes a poor
        // screenshot and, more to the point, would not show that any of this works.
        let days = ScreenshotOptions.warmupDays
        if days > 0 {
            // A day at a time, with progress on stdout: if the capture script ever times out
            // waiting for the ready marker, the log says how far the warm-up actually got
            // instead of leaving us to guess.
            let started = Date()
            for day in 1...days {
                engine.run(ticks: GameDate.minutesPerDay)
                if day % 5 == 0 || day == days {
                    let elapsed = Date().timeIntervalSince(started)
                    print(String(format: "PARKLIFE_WARMUP day %d/%d (%.1fs)", day, days, elapsed))
                    fflush(stdout)
                }
            }
            ParkLog.shared.info(.sim, "Screenshot warm-up: \(days) simulated days")
        }
        engine.submit(.setSpeed(.paused))

        if let overlay = ScreenshotOptions.overlay {
            activeOverlay = overlay
        }

        switch ScreenshotOptions.selection {
        case "cottage":
            // Prefer an occupied cottage: it has the most to show.
            let occupied = engine.world.index.accommodationIDs.first {
                engine.world.buildings[$0]?.accommodation?.state == .occupied
            }
            if let id = occupied ?? engine.world.index.accommodationIDs.first {
                selection = .building(id)
            }
        case "pool":
            if let id = engine.world.index.facilities(ofKind: .pool).first {
                selection = .building(id)
            }
        case "guest":
            if let guest = engine.world.guests.items.first(where: { $0.activity != .departed }) {
                selection = .guest(guest.id)
            }
        default:
            break
        }

        if let definitionID = ScreenshotOptions.buildDefinition {
            buildMode = .building(definitionID, .none)
        }
    }
    #endif

    func newGame(scenarioID: String) {
        guard let catalog else { return }
        do {
            let world = try GameSetup.newGame(scenarioID: scenarioID, catalog: catalog)
            engine = SimulationEngine(world: world)
            selection = .none
            buildMode = .off
            refreshSnapshot()
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - Driving time

    /// Called once per rendered frame by the scene. Converts real time into simulated ticks.
    func advance(to currentTime: TimeInterval) {
        guard let engine else { return }
        defer { lastFrameTime = currentTime }
        guard let last = lastFrameTime else { return }
        // A long gap (backgrounded app) should not fast-forward the whole park.
        let delta = min(currentTime - last, 0.25)
        guard delta > 0 else { return }

        playTimeSeconds += Int(delta)
        engine.advance(realSeconds: delta)
        refreshSnapshot()

        autosaveAccumulator += delta
        if autosaveAccumulator >= autosaveInterval {
            autosaveAccumulator = 0
            autosave()
        }
    }

    func refreshSnapshot() {
        guard let engine else { return }
        snapshot = engine.snapshot(viewport: viewport)
    }

    // MARK: - Intents

    func submit(_ intent: GameIntent) {
        guard let engine else { return }
        switch engine.submit(intent) {
        case .success:
            lastIntentRejection = nil
        case .failure(let rejection):
            lastIntentRejection = describe(rejection)
        }
        refreshSnapshot()
    }

    private func describe(_ rejection: IntentRejection) -> String {
        switch rejection {
        case .buildFailed(let failure): return NSLocalizedString(failure.localizationKey, comment: "")
        case .nothingToUndo: return NSLocalizedString("intent.nothingToUndo", comment: "")
        case .nothingToRedo: return NSLocalizedString("intent.nothingToRedo", comment: "")
        case .unknownEntity: return NSLocalizedString("intent.unknownEntity", comment: "")
        case .notAllowed: return NSLocalizedString("intent.notAllowed", comment: "")
        }
    }

    // MARK: - Building

    /// Validates the current build mode against a tile, for the placement preview.
    func previewValidation(at tile: GridPoint) -> BuildValidation? {
        guard let engine else { return nil }
        switch buildMode {
        case .off:
            return nil
        case .path(let id):
            return BuildService.validate(.placePath(definitionID: id, tiles: [tile]), in: engine.world)
        case .building(let id, let rotation):
            return BuildService.validate(
                .placeBuilding(definitionID: id, origin: tile, rotation: rotation),
                in: engine.world
            )
        case .demolish:
            guard let buildingID = engine.world.tiles.building(at: tile) else { return nil }
            return BuildService.validate(.demolishBuilding(buildingID), in: engine.world)
        }
    }

    func handleTap(on tile: GridPoint) {
        guard let engine else { return }
        switch buildMode {
        case .off:
            if let buildingID = engine.world.tiles.building(at: tile) {
                selection = .building(buildingID)
            } else {
                selection = .tile(tile)
            }
        case .path(let id):
            submit(.build(.placePath(definitionID: id, tiles: [tile])))
        case .building(let id, let rotation):
            submit(.build(.placeBuilding(definitionID: id, origin: tile, rotation: rotation)))
        case .demolish:
            if let buildingID = engine.world.tiles.building(at: tile) {
                submit(.build(.demolishBuilding(buildingID)))
            } else if engine.world.tiles.surface(at: tile) != .none {
                submit(.build(.removePath(tiles: [tile])))
            }
        }
    }

    /// Drag-to-draw for paths.
    func handleDrag(over tiles: [GridPoint]) {
        guard case .path(let id) = buildMode, !tiles.isEmpty else { return }
        submit(.build(.placePath(definitionID: id, tiles: tiles)))
    }

    func rotateBuildSelection() {
        if case .building(let id, let rotation) = buildMode {
            buildMode = .building(id, rotation.next)
        }
    }

    // MARK: - Saving

    @discardableResult
    func save(slot: Int) -> Bool {
        guard let engine, let store else { return false }
        do {
            try store.save(world: engine.world, slot: slot, playTimeSeconds: playTimeSeconds)
            return true
        } catch {
            loadError = String(describing: error)
            return false
        }
    }

    func autosave() {
        save(slot: SaveStore.autosaveSlot)
    }

    func load(slot: Int) {
        guard let engine, let store, let catalog else { return }
        do {
            let world = try store.load(slot: slot, catalog: catalog)
            engine.replaceWorld(world)
            selection = .none
            buildMode = .off
            refreshSnapshot()
        } catch {
            loadError = String(describing: error)
        }
    }

    func availableSlots() -> [SaveMetadata] {
        store?.listSlots() ?? []
    }

    // MARK: - Read-only accessors for panels

    var world: World? { engine?.world }

    var speed: GameSpeed { engine?.world.clock.speed ?? .paused }

    func cycleSpeed() {
        submit(.setSpeed(speed.next))
    }
}

/// Bridges ParkLifeCore's logging into the system log, keeping the core free of Apple imports.
private final class OSLogSink: LogSink {

    private let loggers: [LogCategory: Logger] = {
        var result: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            result[category] = Logger(subsystem: "com.parklife.game", category: category.rawValue)
        }
        return result
    }()

    func write(level: LogLevel, category: LogCategory, message: String) {
        guard let logger = loggers[category] else { return }
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}
