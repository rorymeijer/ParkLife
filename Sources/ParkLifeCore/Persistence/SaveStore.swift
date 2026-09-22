import Foundation

/// Reads and writes save slots on disk.
///
/// Writes are atomic (temp file + rename) and keep a `.bak` of the previous payload, so an
/// interrupted or failed write can never destroy a good save — the single most important property
/// of a save system for a long-running management game.
public final class SaveStore {

    public static let manualSlotCount = 6
    public static let autosaveSlot = -1

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The standard location: `Application Support/ParkLife/saves`.
    public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("ParkLife", isDirectory: true)
            .appendingPathComponent("saves", isDirectory: true)
    }

    // MARK: - Paths

    private func baseName(for slot: Int) -> String {
        slot == SaveStore.autosaveSlot ? "autosave" : "slot-\(slot)"
    }

    public func saveURL(slot: Int) -> URL {
        directory.appendingPathComponent("\(baseName(for: slot)).\(SaveFormat.fileExtension)")
    }

    public func backupURL(slot: Int) -> URL {
        directory.appendingPathComponent("\(baseName(for: slot)).\(SaveFormat.fileExtension).bak")
    }

    public func metadataURL(slot: Int) -> URL {
        directory.appendingPathComponent("\(baseName(for: slot)).meta.json")
    }

    // MARK: - Writing

    @discardableResult
    public func save(world: World, slot: Int, playTimeSeconds: Int = 0) throws -> SaveMetadata {
        let metadata = SaveMetadata.make(from: world, slot: slot, playTimeSeconds: playTimeSeconds)
        let data = try SaveFormat.encode(world: world, metadata: metadata)

        let target = saveURL(slot: slot)
        let temporary = target.appendingPathExtension("tmp")

        do {
            // 1. Write the new contents to a temporary file.
            try data.write(to: temporary, options: [.atomic])
            // 2. Keep the previous good save as a backup.
            if fileManager.fileExists(atPath: target.path) {
                let backup = backupURL(slot: slot)
                if fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.removeItem(at: backup)
                }
                try? fileManager.moveItem(at: target, to: backup)
            }
            // 3. Swap the temporary file in. Either the old or the new file is always present.
            try fileManager.moveItem(at: temporary, to: target)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw SaveError.writeFailed(String(describing: error))
        }

        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try? metadataEncoder.encode(metadata).write(to: metadataURL(slot: slot), options: [.atomic])

        ParkLog.shared.info(.save, "Saved slot \(slot) (\(data.count) bytes)")
        return metadata
    }

    // MARK: - Reading

    public func load(slot: Int, catalog: ContentCatalog) throws -> World {
        let url = saveURL(slot: slot)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SaveError.notFound(baseName(for: slot))
        }
        do {
            return try loadWorld(from: url, catalog: catalog)
        } catch {
            // Damaged primary file: offer the backup rather than losing the game.
            let backup = backupURL(slot: slot)
            guard fileManager.fileExists(atPath: backup.path) else { throw error }
            ParkLog.shared.warning(.save, "Slot \(slot) is damaged, falling back to the backup")
            return try loadWorld(from: backup, catalog: catalog)
        }
    }

    private func loadWorld(from url: URL, catalog: ContentCatalog) throws -> World {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SaveError.notFound(url.lastPathComponent)
        }
        let decoded = try SaveFormat.decode(data)
        let world = try decoded.payload.makeWorld(catalog: catalog)
        ParkLog.shared.info(
            .save,
            "Loaded \(url.lastPathComponent) (format \(decoded.formatVersion), migrated: \(decoded.migrated))"
        )
        return world
    }

    /// Slot metadata for the load screen. Reads only sidecars, so it is instant regardless of how
    /// big the saves are.
    public func listSlots() -> [SaveMetadata] {
        var result: [SaveMetadata] = []
        let decoder = JSONDecoder()
        for slot in [SaveStore.autosaveSlot] + Array(0..<SaveStore.manualSlotCount) {
            let url = metadataURL(slot: slot)
            guard let data = try? Data(contentsOf: url),
                  let metadata = try? decoder.decode(SaveMetadata.self, from: data) else { continue }
            guard fileManager.fileExists(atPath: saveURL(slot: slot).path) else { continue }
            result.append(metadata)
        }
        return result
    }

    public func hasSave(slot: Int) -> Bool {
        fileManager.fileExists(atPath: saveURL(slot: slot).path)
    }

    public func delete(slot: Int) throws {
        try? fileManager.removeItem(at: saveURL(slot: slot))
        try? fileManager.removeItem(at: backupURL(slot: slot))
        try? fileManager.removeItem(at: metadataURL(slot: slot))
    }

    /// Raw bytes for a slot, for the optional iCloud sync layer. The core never knows what the
    /// app does with them.
    public func rawData(slot: Int) throws -> Data {
        try Data(contentsOf: saveURL(slot: slot))
    }

    public func writeRawData(_ data: Data, slot: Int) throws {
        // Validate before overwriting anything: a bad cloud payload must not eat a local save.
        _ = try SaveFormat.decode(data)
        let target = saveURL(slot: slot)
        let temporary = target.appendingPathExtension("tmp")
        try data.write(to: temporary, options: [.atomic])
        if fileManager.fileExists(atPath: target.path) {
            let backup = backupURL(slot: slot)
            try? fileManager.removeItem(at: backup)
            try? fileManager.moveItem(at: target, to: backup)
        }
        try fileManager.moveItem(at: temporary, to: target)
    }
}
