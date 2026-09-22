import Foundation

public enum SaveError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case corrupted(String)
    case unsupportedVersion(found: Int, supported: Int)
    case migrationFailed(from: Int, to: Int, reason: String)
    case contentMissing(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .notFound(let slot):
            return "No save found at \(slot)"
        case .corrupted(let reason):
            return "Save file is damaged: \(reason)"
        case .unsupportedVersion(let found, let supported):
            return "Save was written by a newer version of ParkLife (format \(found), this build supports \(supported))"
        case .migrationFailed(let from, let to, let reason):
            return "Could not upgrade save from format \(from) to \(to): \(reason)"
        case .contentMissing(let what):
            return "This save needs content that is not installed: \(what)"
        case .writeFailed(let reason):
            return "Could not write the save: \(reason)"
        }
    }
}

/// Lightweight information shown on the load screen, stored in a sidecar file so listing saves
/// never parses a full world.
public struct SaveMetadata: Codable, Equatable {

    public var slot: Int
    public var parkName: String
    public var companyName: String
    public var inGameMinutes: Int
    public var cashCents: Int
    public var guestCount: Int
    public var occupancyPercent: Int
    public var reputation: Double
    public var playTimeSeconds: Int
    public var formatVersion: Int
    public var gameVersion: String
    public var savedAtEpochSeconds: Int

    public init(
        slot: Int,
        parkName: String,
        companyName: String,
        inGameMinutes: Int,
        cashCents: Int,
        guestCount: Int,
        occupancyPercent: Int,
        reputation: Double,
        playTimeSeconds: Int,
        formatVersion: Int,
        gameVersion: String,
        savedAtEpochSeconds: Int
    ) {
        self.slot = slot
        self.parkName = parkName
        self.companyName = companyName
        self.inGameMinutes = inGameMinutes
        self.cashCents = cashCents
        self.guestCount = guestCount
        self.occupancyPercent = occupancyPercent
        self.reputation = reputation
        self.playTimeSeconds = playTimeSeconds
        self.formatVersion = formatVersion
        self.gameVersion = gameVersion
        self.savedAtEpochSeconds = savedAtEpochSeconds
    }

    public var inGameDate: GameDate { GameDate(minutesSinceEpoch: inGameMinutes) }

    public static func make(from world: World, slot: Int, playTimeSeconds: Int) -> SaveMetadata {
        SaveMetadata(
            slot: slot,
            parkName: world.parkName,
            companyName: world.companyName,
            inGameMinutes: world.clock.tick,
            cashCents: world.cash.cents,
            guestCount: world.guestsOnSite,
            occupancyPercent: Int((world.occupancyRate * 100).rounded()),
            reputation: world.reputation.overall,
            playTimeSeconds: playTimeSeconds,
            formatVersion: SaveFormat.currentVersion,
            gameVersion: SaveFormat.gameVersion,
            savedAtEpochSeconds: Int(Date().timeIntervalSince1970)
        )
    }
}

/// Versioning, checksums and migration.
public enum SaveFormat {

    /// Bumped on every breaking payload change, with a migration shipped in the same commit.
    public static let currentVersion = 1
    public static let gameVersion = "0.2.0"
    public static let fileExtension = "parklife"

    /// A step that upgrades a raw payload dictionary from one format version to the next.
    public struct Migration {
        public let from: Int
        public let to: Int
        public let migrate: (inout [String: Any]) throws -> Void

        public init(from: Int, to: Int, migrate: @escaping (inout [String: Any]) throws -> Void) {
            self.from = from
            self.to = to
            self.migrate = migrate
        }
    }

    /// Registered migrations, applied in order.
    ///
    /// Empty today because format 1 is the first release. The machinery is here and tested so that
    /// the first breaking change is a data problem, not an architecture problem.
    public static let migrations: [Migration] = []

    // MARK: - Encoding

    /// Canonical encoding: sorted keys, so the same world always produces the same bytes and the
    /// checksum is meaningful.
    public static func encodePayload(_ payload: SaveGame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    public static func checksum(for payload: SaveGame) throws -> String {
        "fnv1a64:" + FNV1a.hexString(try encodePayload(payload))
    }

    /// Builds the complete file contents.
    ///
    /// The payload bytes are the exact output of `encodePayload` — the envelope is assembled
    /// around them rather than re-serialised, so the bytes the checksum describes are the bytes
    /// written to disk.
    public static func encode(world: World, metadata: SaveMetadata) throws -> Data {
        let payload = try SaveGame(world: world)
        let payloadData = try encodePayload(payload)
        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.sortedKeys]
        let metadataData = try metadataEncoder.encode(metadata)
        let digest = try checksum(for: payload)

        var out = Data()
        out.append(Data("{\"formatVersion\":\(currentVersion),".utf8))
        out.append(Data("\"gameVersion\":\"\(gameVersion)\",".utf8))
        out.append(Data("\"createdAtEpochSeconds\":\(Int(Date().timeIntervalSince1970)),".utf8))
        out.append(Data("\"checksum\":\"\(digest)\",".utf8))
        out.append(Data("\"metadata\":".utf8))
        out.append(metadataData)
        out.append(Data(",\"payload\":".utf8))
        out.append(payloadData)
        out.append(Data("}".utf8))
        return out
    }

    public struct DecodedSave {
        public let payload: SaveGame
        public let metadata: SaveMetadata?
        public let formatVersion: Int
        public let migrated: Bool
        public let checksumVerified: Bool
    }

    /// Decodes a save, migrating it forward if necessary.
    ///
    /// The checksum is verified by re-encoding the decoded payload canonically and comparing. That
    /// is only meaningful when no migration ran — after a migration the stored checksum describes
    /// the *old* shape — so `checksumVerified` reports honestly rather than pretending.
    public static func decode(_ data: Data) throws -> DecodedSave {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SaveError.corrupted("file is not valid JSON")
        }
        guard let version = root["formatVersion"] as? Int else {
            throw SaveError.corrupted("missing formatVersion")
        }
        guard version <= currentVersion else {
            throw SaveError.unsupportedVersion(found: version, supported: currentVersion)
        }
        guard var payloadObject = root["payload"] as? [String: Any] else {
            throw SaveError.corrupted("missing payload")
        }

        var workingVersion = version
        var migrated = false
        while workingVersion < currentVersion {
            guard let migration = migrations.first(where: { $0.from == workingVersion }) else {
                throw SaveError.migrationFailed(
                    from: workingVersion,
                    to: currentVersion,
                    reason: "no migration registered"
                )
            }
            do {
                try migration.migrate(&payloadObject)
            } catch {
                throw SaveError.migrationFailed(
                    from: migration.from,
                    to: migration.to,
                    reason: String(describing: error)
                )
            }
            workingVersion = migration.to
            migrated = true
        }

        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        } catch {
            throw SaveError.corrupted("payload could not be re-serialised")
        }

        let payload: SaveGame
        do {
            payload = try JSONDecoder().decode(SaveGame.self, from: payloadData)
        } catch {
            throw SaveError.corrupted("payload does not match the expected model: \(error)")
        }

        var verified = false
        if !migrated, let stored = root["checksum"] as? String {
            let recomputed = try checksum(for: payload)
            guard stored == recomputed else {
                throw SaveError.corrupted("checksum mismatch")
            }
            verified = true
        }

        var metadata: SaveMetadata?
        if let metadataObject = root["metadata"] {
            let metadataData = try JSONSerialization.data(withJSONObject: metadataObject)
            metadata = try? JSONDecoder().decode(SaveMetadata.self, from: metadataData)
        }

        return DecodedSave(
            payload: payload,
            metadata: metadata,
            formatVersion: version,
            migrated: migrated,
            checksumVerified: verified
        )
    }
}
