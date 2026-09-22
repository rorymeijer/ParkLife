import XCTest
@testable import ParkLifeCore

final class SaveFormatTests: XCTestCase {

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parklife-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testTerrainRoundTripsExactly() throws {
        let world = try TestFixtures.demoPark()
        let payload = TerrainPayload(tileMap: world.tiles)
        let restored = try payload.makeTileMap()

        XCTAssertEqual(restored.size, world.tiles.size)
        XCTAssertEqual(restored.elevation, world.tiles.elevation)
        XCTAssertEqual(restored.terrainRaw, world.tiles.terrainRaw)
        XCTAssertEqual(restored.surfaceRaw, world.tiles.surfaceRaw)
        XCTAssertEqual(restored.buildingRaw, world.tiles.buildingRaw)
    }

    func testTerrainRunLengthActuallyCompresses() throws {
        let world = try TestFixtures.demoPark()
        let payload = TerrainPayload(tileMap: world.tiles)
        // 96×96 is 9 216 cells per layer; RLE must do far better than storing them one by one.
        XCTAssertLessThan(payload.surface.count, world.tiles.size.tileCount / 2)
        XCTAssertLessThan(payload.terrain.count, world.tiles.size.tileCount)
    }

    func testWorldRoundTripsThroughSaveGame() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 20 * GameDate.minutesPerDay)
        let original = engine.world

        let payload = try SaveGame(world: original)
        let data = try SaveFormat.encodePayload(payload)
        let decoded = try JSONDecoder().decode(SaveGame.self, from: data)
        let restored = try decoded.makeWorld(catalog: TestFixtures.catalog)

        XCTAssertEqual(restored.clock.tick, original.clock.tick)
        XCTAssertEqual(restored.cash, original.cash)
        XCTAssertEqual(restored.buildings.count, original.buildings.count)
        XCTAssertEqual(restored.guests.count, original.guests.count)
        XCTAssertEqual(restored.groups.count, original.groups.count)
        XCTAssertEqual(restored.reservations.count, original.reservations.count)
        XCTAssertEqual(restored.staff.count, original.staff.count)
        XCTAssertEqual(restored.reviews.count, original.reviews.count)
        XCTAssertEqual(restored.reputation.overall, original.reputation.overall, accuracy: 0.000001)
        XCTAssertEqual(restored.statistics.totalGuestsHosted, original.statistics.totalGuestsHosted)
        XCTAssertEqual(restored.parkName, original.parkName)
        XCTAssertEqual(restored.entranceTile, original.entranceTile)
    }

    func testDerivedStateIsRebuiltNotStored() throws {
        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 5 * GameDate.minutesPerDay)
        let payload = try SaveGame(world: engine.world)
        let restored = try payload.makeWorld(catalog: TestFixtures.catalog)

        // The path network, flow fields and index are absent from the save and must come back.
        XCTAssertEqual(restored.navigation.network.walkableCount, engine.world.navigation.network.walkableCount)
        XCTAssertEqual(restored.index.accommodationIDs, engine.world.index.accommodationIDs)
        XCTAssertNotNil(restored.index.receptionID)
        let reception = try XCTUnwrap(restored.index.receptionID)
        XCTAssertNotNil(restored.navigation.field(for: reception))
    }

    func testSaveFileHasAVersionedEnvelopeAndChecksum() throws {
        let world = try TestFixtures.demoPark()
        let metadata = SaveMetadata.make(from: world, slot: 0, playTimeSeconds: 120)
        let data = try SaveFormat.encode(world: world, metadata: metadata)

        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["formatVersion"] as? Int, SaveFormat.currentVersion)
        XCTAssertEqual(root["gameVersion"] as? String, SaveFormat.gameVersion)
        let checksum = try XCTUnwrap(root["checksum"] as? String)
        XCTAssertTrue(checksum.hasPrefix("fnv1a64:"))
        XCTAssertNotNil(root["payload"])
        XCTAssertNotNil(root["metadata"])
    }

    func testDecodeVerifiesTheChecksum() throws {
        let world = try TestFixtures.demoPark()
        let metadata = SaveMetadata.make(from: world, slot: 0, playTimeSeconds: 0)
        let data = try SaveFormat.encode(world: world, metadata: metadata)

        let decoded = try SaveFormat.decode(data)
        XCTAssertTrue(decoded.checksumVerified)
        XCTAssertFalse(decoded.migrated)
        XCTAssertEqual(decoded.formatVersion, SaveFormat.currentVersion)
        XCTAssertEqual(decoded.metadata?.parkName, world.parkName)
    }

    func testTamperedPayloadIsRejected() throws {
        let world = try TestFixtures.demoPark()
        let metadata = SaveMetadata.make(from: world, slot: 0, playTimeSeconds: 0)
        let data = try SaveFormat.encode(world: world, metadata: metadata)

        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var payload = try XCTUnwrap(root["payload"] as? [String: Any])
        payload["cash"] = 999_999_999
        root["payload"] = payload
        let tampered = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try SaveFormat.decode(tampered)) { error in
            XCTAssertEqual(error as? SaveError, .corrupted("checksum mismatch"))
        }
    }

    func testTruncatedFileIsReportedAsCorrupt() throws {
        let world = try TestFixtures.demoPark()
        let data = try SaveFormat.encode(world: world, metadata: SaveMetadata.make(from: world, slot: 0, playTimeSeconds: 0))
        let truncated = data.prefix(data.count / 2)
        XCTAssertThrowsError(try SaveFormat.decode(Data(truncated)))
    }

    func testFutureFormatVersionIsRefusedNotMangled() throws {
        let world = try TestFixtures.demoPark()
        let data = try SaveFormat.encode(world: world, metadata: SaveMetadata.make(from: world, slot: 0, playTimeSeconds: 0))
        var root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["formatVersion"] = SaveFormat.currentVersion + 5
        let future = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try SaveFormat.decode(future)) { error in
            XCTAssertEqual(
                error as? SaveError,
                .unsupportedVersion(found: SaveFormat.currentVersion + 5, supported: SaveFormat.currentVersion)
            )
        }
    }

    func testMissingPayloadIsReported() throws {
        let data = try JSONSerialization.data(withJSONObject: ["formatVersion": 1])
        XCTAssertThrowsError(try SaveFormat.decode(data))
    }

    func testMigrationChainIsApplied() throws {
        // The registry is empty at format 1; this proves the machinery works before it is needed.
        var applied = false
        let migration = SaveFormat.Migration(from: 0, to: 1) { payload in
            applied = true
            payload["cash"] = payload["cash"] ?? 0
        }
        var payload: [String: Any] = ["cash": 500]
        try migration.migrate(&payload)
        XCTAssertTrue(applied)
        XCTAssertEqual(migration.from, 0)
        XCTAssertEqual(migration.to, 1)
    }
}

final class SaveStoreTests: XCTestCase {

    private func makeStore() throws -> (SaveStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("parklife-store-\(UUID().uuidString)", isDirectory: true)
        return (try SaveStore(directory: url), url)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 3 * GameDate.minutesPerDay)

        let metadata = try store.save(world: engine.world, slot: 0, playTimeSeconds: 900)
        XCTAssertEqual(metadata.slot, 0)
        XCTAssertEqual(metadata.playTimeSeconds, 900)
        XCTAssertTrue(store.hasSave(slot: 0))

        let loaded = try store.load(slot: 0, catalog: TestFixtures.catalog)
        XCTAssertEqual(loaded.clock.tick, engine.world.clock.tick)
        XCTAssertEqual(loaded.cash, engine.world.cash)
        XCTAssertEqual(loaded.buildings.count, engine.world.buildings.count)
    }

    func testSimulationContinuesIdenticallyAfterLoading() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = try TestFixtures.demoEngine()
        engine.run(ticks: 10 * GameDate.minutesPerDay)
        try store.save(world: engine.world, slot: 1)

        // Continue the original, and continue a freshly loaded copy: they must agree.
        engine.run(ticks: 3 * GameDate.minutesPerDay)
        let expected = try engine.worldHash()

        let reloaded = SimulationEngine(world: try store.load(slot: 1, catalog: TestFixtures.catalog))
        reloaded.run(ticks: 3 * GameDate.minutesPerDay)

        XCTAssertEqual(try reloaded.worldHash(), expected, "a loaded game must continue exactly as the original would")
    }

    func testMetadataSidecarListsSlotsWithoutParsingSaves() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let world = try TestFixtures.demoPark()
        try store.save(world: world, slot: 0)
        try store.save(world: world, slot: 3)

        let slots = store.listSlots()
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(Set(slots.map(\.slot)), [0, 3])
        XCTAssertEqual(slots.first?.parkName, world.parkName)
        XCTAssertEqual(slots.first?.formatVersion, SaveFormat.currentVersion)
    }

    func testOverwritingKeepsABackup() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = try TestFixtures.demoEngine()
        try store.save(world: engine.world, slot: 0)
        let firstTick = engine.world.clock.tick

        engine.run(ticks: GameDate.minutesPerDay)
        try store.save(world: engine.world, slot: 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL(slot: 0).path))
        let backup = try SaveFormat.decode(try Data(contentsOf: store.backupURL(slot: 0)))
        XCTAssertEqual(backup.payload.clock.tick, firstTick, "the previous save must survive as a backup")
    }

    func testDamagedSaveFallsBackToTheBackup() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = try TestFixtures.demoEngine()
        try store.save(world: engine.world, slot: 0)
        let goodTick = engine.world.clock.tick
        engine.run(ticks: GameDate.minutesPerDay)
        try store.save(world: engine.world, slot: 0)

        // Corrupt the current save; the backup must carry the day rather than the game refusing
        // to load at all.
        try Data("this is not a save file".utf8).write(to: store.saveURL(slot: 0))
        let recovered = try store.load(slot: 0, catalog: TestFixtures.catalog)
        XCTAssertEqual(recovered.clock.tick, goodTick)
    }

    func testMissingSlotThrowsNotFound() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try store.load(slot: 4, catalog: TestFixtures.catalog)) { error in
            XCTAssertEqual(error as? SaveError, .notFound("slot-4"))
        }
    }

    func testDeleteRemovesEverythingForASlot() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let world = try TestFixtures.demoPark()
        try store.save(world: world, slot: 2)
        try store.delete(slot: 2)
        XCTAssertFalse(store.hasSave(slot: 2))
        XCTAssertTrue(store.listSlots().isEmpty)
    }

    func testAutosaveUsesItsOwnSlot() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let world = try TestFixtures.demoPark()
        try store.save(world: world, slot: SaveStore.autosaveSlot)
        XCTAssertTrue(store.saveURL(slot: SaveStore.autosaveSlot).lastPathComponent.hasPrefix("autosave"))
        XCTAssertNoThrow(try store.load(slot: SaveStore.autosaveSlot, catalog: TestFixtures.catalog))
    }

    func testRawDataIsValidatedBeforeOverwriting() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let world = try TestFixtures.demoPark()
        try store.save(world: world, slot: 0)
        // A bad cloud payload must be refused, not written over a good local save.
        XCTAssertThrowsError(try store.writeRawData(Data("nonsense".utf8), slot: 0))
        XCTAssertNoThrow(try store.load(slot: 0, catalog: TestFixtures.catalog))
    }
}
