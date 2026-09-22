import Foundation
import CloudKit
import ParkLifeCore

/// Optional iCloud synchronisation of save slots.
///
/// Strictly a convenience layer: the game always reads and writes local files first, and every
/// failure here is reported as a status, never as an error that blocks play. `ParkLifeCore` knows
/// nothing about CloudKit — this moves opaque bytes (ADR 0003).
actor CloudSaveService {

    enum Status: Equatable {
        case unknown
        case unavailable(String)
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    private(set) var status: Status = .unknown

    private static let recordType = "SaveSlot"

    init(containerIdentifier: String = "iCloud.com.parklife.game") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    /// Checks whether iCloud is usable. A "no" is a normal outcome, not a failure.
    func refreshAvailability() async -> Status {
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = .idle
            case .noAccount:
                status = .unavailable("noAccount")
            case .restricted:
                status = .unavailable("restricted")
            case .couldNotDetermine:
                status = .unavailable("couldNotDetermine")
            case .temporarilyUnavailable:
                status = .unavailable("temporarilyUnavailable")
            @unknown default:
                status = .unavailable("unknown")
            }
        } catch {
            status = .unavailable(String(describing: error))
        }
        return status
    }

    private func recordID(for slot: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "slot-\(slot)")
    }

    /// Uploads a slot's bytes. Never throws into gameplay: the result is a status.
    func upload(data: Data, metadata: SaveMetadata, slot: Int) async -> Status {
        guard case .idle = status else { return status }
        status = .syncing
        do {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("parklife-upload-\(slot).parklife")
            try data.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }

            let record = CKRecord(recordType: CloudSaveService.recordType, recordID: recordID(for: slot))
            record["payload"] = CKAsset(fileURL: temporary)
            record["slot"] = slot as CKRecordValue
            record["formatVersion"] = metadata.formatVersion as CKRecordValue
            record["inGameMinutes"] = metadata.inGameMinutes as CKRecordValue
            record["parkName"] = metadata.parkName as CKRecordValue
            record["deviceID"] = deviceIdentifier as CKRecordValue

            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            status = .synced(Date())
        } catch {
            status = .failed(String(describing: error))
        }
        return status
    }

    /// Fetches a slot's bytes if the cloud copy is further ahead in game time.
    ///
    /// The loser of a conflict is returned to the caller so it can be preserved locally as a
    /// conflicted copy — nothing is ever silently discarded.
    func download(slot: Int, localInGameMinutes: Int?) async -> (data: Data, inGameMinutes: Int)? {
        guard case .idle = status else { return nil }
        do {
            let record = try await database.record(for: recordID(for: slot))
            guard let asset = record["payload"] as? CKAsset,
                  let url = asset.fileURL,
                  let remoteMinutes = record["inGameMinutes"] as? Int else { return nil }
            if let localInGameMinutes, remoteMinutes <= localInGameMinutes { return nil }
            let data = try Data(contentsOf: url)
            status = .synced(Date())
            return (data, remoteMinutes)
        } catch {
            // A missing record is an ordinary outcome the first time a device syncs.
            return nil
        }
    }

    private var deviceIdentifier: String {
        // Stable per install, and never sent anywhere except the user's own private database.
        let key = "com.parklife.deviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
