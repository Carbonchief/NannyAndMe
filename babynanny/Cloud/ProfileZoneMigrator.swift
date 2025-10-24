import CloudKit
import Foundation
import os
import SwiftData

@MainActor
final class ProfileZoneMigrator {
    private let modelContainer: ModelContainer
    private let database: CKDatabase
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "cloud.migration")
    private let migrationKey = "com.prioritybit.nannyandme.profileZoneMigration"

    init(modelContainer: ModelContainer,
         database: CKDatabase = CKConfig.privateDatabase(),
         userDefaults: UserDefaults = .standard) {
        self.modelContainer = modelContainer
        self.database = database
        self.userDefaults = userDefaults
    }

    func migrateIfNeeded() async {
        guard userDefaults.bool(forKey: migrationKey) == false else { return }
        logger.log("Starting profile zone migration")
        do {
            try await performMigration()
            userDefaults.set(true, forKey: migrationKey)
            logger.log("Finished profile zone migration")
        } catch {
            logger.error("Failed to migrate profile zones: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performMigration() async throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let profiles = try context.fetch(descriptor)
        guard profiles.isEmpty == false else { return }

        for profile in profiles {
            try Task.checkCancellation()
            let zoneID = CloudKitProfileZone.zoneID(for: profile.profileID)
            try await ensureZoneExists(zoneID: zoneID)
            let records = makeRecords(for: profile, zoneID: zoneID)
            try await save(records: records)
        }
    }

    private func ensureZoneExists(zoneID: CKRecordZone.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let zone = CKRecordZone(zoneID: zoneID)
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func makeRecords(for profile: ProfileActionStateModel,
                             zoneID: CKRecordZone.ID) -> [CKRecord] {
        var records: [CKRecord] = []
        let profileRecord = CloudKitRecordMapper.makeProfileRecord(from: profile, zoneID: zoneID)
        records.append(profileRecord)
        for action in profile.actions {
            let record = CloudKitRecordMapper.makeBabyActionRecord(from: action,
                                                                   profileID: profile.profileID,
                                                                   zoneID: zoneID)
            records.append(record)
        }
        return records
    }

    private func save(records: [CKRecord]) async throws {
        guard records.isEmpty == false else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}
