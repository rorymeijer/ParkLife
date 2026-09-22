import Foundation

/// Owns the world and runs the tick loop.
///
/// Fixed-step: real time is accumulated and converted into whole simulated minutes, capped by both
/// a tick count and a wall-clock budget. A slow device loses simulated time instead of frame rate,
/// and rendering FPS can never change the outcome of a game.
public final class SimulationEngine {

    public private(set) var world: World
    public private(set) var tuning: SimulationTuning
    public private(set) var history: BuildHistory
    /// Events produced by the most recent tick, for the app layer to react to.
    public private(set) var lastTickEvents: [SimulationEvent]

    /// Hard caps for one `advance` call.
    public var maximumTicksPerCall: Int = 64
    public var tickBudgetSeconds: Double = 0.008

    public private(set) var lastTickDurationSeconds: Double = 0
    public private(set) var totalTicksRun: Int = 0

    /// The tick order. Order is load-bearing — needs drift before decisions, spending before
    /// settlement — and is asserted by `SystemOrderTests`.
    public static let systemOrder: [String] = [
        TimeSystem.systemName,
        WeatherSystem.systemName,
        DemandSystem.systemName,
        ReservationSystem.systemName,
        ArrivalSystem.systemName,
        GuestAISystem.systemName,
        MovementSystem.systemName,
        FacilitySystem.systemName,
        AccommodationSystem.systemName,
        StaffSystem.systemName,
        EconomySystem.systemName,
        ResearchSystem.systemName,
        ReviewSystem.systemName,
        ReputationSystem.systemName,
        StatisticsSystem.systemName,
        ObjectiveSystem.systemName,
        NotificationSystem.systemName
    ]

    public init(world: World) {
        self.world = world
        self.tuning = SimulationTuning.forDifficulty(world.difficulty)
        self.history = BuildHistory()
        self.lastTickEvents = []
    }

    public var date: GameDate { world.date }
    public var speed: GameSpeed { world.clock.speed }

    // MARK: - Driving time

    /// Runs whole ticks for the elapsed real time. Returns how many ticks actually ran.
    @discardableResult
    public func advance(realSeconds: Double) -> Int {
        let requested = world.clock.pendingTicks(forRealSeconds: realSeconds, maximumTicks: maximumTicksPerCall)
        guard requested > 0 else { return 0 }

        let started = Date()
        var executed = 0
        for _ in 0..<requested {
            runTick()
            executed += 1
            // Budget guard: never spend more than the frame can afford, whatever the speed setting.
            if Date().timeIntervalSince(started) > tickBudgetSeconds {
                break
            }
        }
        lastTickDurationSeconds = Date().timeIntervalSince(started) / Double(max(1, executed))
        return executed
    }

    /// Runs exactly `count` ticks, ignoring speed. Used by tests, debug tools and fast-forward.
    public func run(ticks count: Int) {
        for _ in 0..<max(0, count) {
            runTick()
        }
    }

    /// Runs one simulated minute through every system, in order.
    public func runTick() {
        let previousDate = world.clock.date
        world.clock.advanceOneTick()

        var context = TickContext(
            tick: world.clock.tick,
            date: world.clock.date,
            previousDate: previousDate,
            tuning: tuning
        )
        context.dueEvents = world.schedule.drain(upTo: context.tick)

        TimeSystem.update(world: &world, context: &context)
        WeatherSystem.update(world: &world, context: &context)
        DemandSystem.update(world: &world, context: &context)
        ReservationSystem.update(world: &world, context: &context)
        ArrivalSystem.update(world: &world, context: &context)
        GuestAISystem.update(world: &world, context: &context)
        MovementSystem.update(world: &world, context: &context)
        FacilitySystem.update(world: &world, context: &context)
        AccommodationSystem.update(world: &world, context: &context)
        StaffSystem.update(world: &world, context: &context)
        EconomySystem.update(world: &world, context: &context)
        ResearchSystem.update(world: &world, context: &context)
        ReviewSystem.update(world: &world, context: &context)
        ReputationSystem.update(world: &world, context: &context)
        StatisticsSystem.update(world: &world, context: &context)
        ObjectiveSystem.update(world: &world, context: &context)
        NotificationSystem.update(world: &world, context: &context)

        // Navigation maintenance: stale flow fields are rebuilt a couple per tick, so a build
        // action never spikes a frame.
        let worldCopy = world
        world.navigation.refreshStaleFields(
            goalsProvider: { worldCopy.accessTiles(for: $0) },
            tick: context.tick
        )

        lastTickEvents = context.events
        totalTicksRun += 1
    }

    // MARK: - Intents

    @discardableResult
    public func submit(_ intent: GameIntent) -> Result<Void, IntentRejection> {
        switch intent {
        case .setSpeed(let speed):
            world.clock.speed = speed

        case .build(let action):
            let validation = BuildService.validate(action, in: world)
            guard validation.isValid else {
                return .failure(.buildFailed(validation.failure ?? .nothingToRemove))
            }
            guard let record = BuildService.apply(action, to: &world) else {
                return .failure(.buildFailed(validation.failure ?? .nothingToRemove))
            }
            history.push(record)

        case .undoBuild:
            guard let record = history.popUndo() else { return .failure(.nothingToUndo) }
            _ = BuildService.undo(record, in: &world)
            history.pushRedo(record)

        case .redoBuild:
            guard let record = history.popRedo() else { return .failure(.nothingToRedo) }
            guard let replayed = BuildService.redo(record, in: &world) else {
                return .failure(.nothingToRedo)
            }
            history.push(replayed)

        case .setAccommodationPrice(let definitionID, let price):
            world.pricing.accommodationOverrides[definitionID] = price

        case .setUnitPrice(let id, let price):
            guard world.buildings[id]?.accommodation != nil else { return .failure(.unknownEntity) }
            world.buildings.modify(id) { $0.accommodation?.nightlyPriceOverride = price }

        case .setFacilityPrice(let definitionID, let price):
            world.pricing.facilityOverrides[definitionID] = price

        case .setAccommodationMultiplier(let value):
            world.pricing.accommodationMultiplier = clamp(value, 0.4, 3.0)

        case .setSeasonalPricing(let enabled):
            world.pricing.seasonalPricingEnabled = enabled

        case .setLastMinuteDiscount(let value):
            world.pricing.lastMinuteDiscount = clamp01(value)

        case .hireStaff(let roleID):
            guard StaffSystem.hire(roleID: roleID, world: &world) != nil else {
                return .failure(.unknownEntity)
            }

        case .dismissStaff(let id):
            guard StaffSystem.dismiss(id, world: &world) else { return .failure(.unknownEntity) }

        case .setStaffShift(let id, let start, let end):
            guard world.staff[id] != nil else { return .failure(.unknownEntity) }
            world.staff.modify(id) { member in
                member.shiftStartMinute = clamp(start, 0, 1_439)
                member.shiftEndMinute = clamp(end, 0, 1_439)
            }

        case .openFacility(let id, let isOpen):
            guard world.buildings[id]?.facility != nil else { return .failure(.unknownEntity) }
            world.buildings.modify(id) { $0.facility?.isOpen = isOpen }

        case .startResearch(let id):
            guard ResearchSystem.start(id, in: &world) else { return .failure(.notAllowed) }

        case .takeLoan(let amount, let termDays):
            guard EconomySystem.takeLoan(amount: amount, termDays: termDays, world: &world) else {
                return .failure(.notAllowed)
            }

        case .markNotificationsRead:
            world.notifications.markAllRead()

        case .dismissNotification(let id):
            world.notifications.dismiss(id)
        }
        return .success(())
    }

    // MARK: - Snapshot

    public func snapshot(viewport: GridRect? = nil) -> WorldSnapshot {
        world.snapshot(viewport: viewport)
    }

    /// Replaces the world wholesale — used by save loading.
    public func replaceWorld(_ newWorld: World) {
        world = newWorld
        world.rebuildDerivedState()
        tuning = SimulationTuning.forDifficulty(world.difficulty)
        history.clear()
        lastTickEvents = []
    }

    #if DEBUG
    /// Direct world mutation, for development tools only.
    ///
    /// Compiled out of release builds entirely, so shipped code has no way to poke the world
    /// outside the intent pipeline (brief §46).
    public func debugMutate(_ body: (inout World) -> Void) {
        body(&world)
        world.rebuildDerivedState()
    }
    #endif

    /// Stable hash of the world, for determinism tests and save verification.
    public func worldHash() throws -> UInt64 {
        let payload = try SaveGame(world: world)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return FNV1a.hash(try encoder.encode(payload))
    }
}
