import CloudKit
import Foundation
import os
import SwiftData

/// Handles the acceptance of incoming `CKShare`s and ingests the shared data into SwiftData.
final class ShareAcceptanceHandler: SharedRecordIngesting {
    private let container: CKContainer
    private let sharedDatabase: CKDatabase
    private let modelContainer: ModelContainer
    private let metadataStore: ShareMetadataStore
    private let tokenStore: SharedZoneChangeTokenStore
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share")

    init(modelContainer: ModelContainer,
         containerIdentifier: String = "iCloud.com.prioritybit.babynanny",
         metadataStore: ShareMetadataStore = ShareMetadataStore(),
         tokenStore: SharedZoneChangeTokenStore = SharedZoneChangeTokenStore()) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.sharedDatabase = container.sharedCloudDatabase
        self.modelContainer = modelContainer
        self.metadataStore = metadataStore
        self.tokenStore = tokenStore
    }

    /// Accepts the provided share metadata and imports the associated records.
    func accept(metadata: CKShare.Metadata) async throws {
        try await accept(metadatas: [metadata])
    }

    /// Accepts multiple share metadata payloads.
    func accept(metadatas: [CKShare.Metadata]) async throws {
        guard metadatas.isEmpty == false else { return }
        try await acceptShares(metadatas)
        for metadata in metadatas {
            let zoneID = metadata.rootRecordID.zoneID
            let result = try await fetchAndIngestInitialContent(for: zoneID)
            let share = metadata.share
            if let profileRecord = result.records.first(where: { $0.recordType == RecordType.profile }),
               let profileIDString = profileRecord["profileID"] as? String,
               let profileID = UUID(uuidString: profileIDString) {
                let stored = ShareMetadataStore.ShareMetadata(
                    profileID: profileID,
                    zoneID: zoneID,
                    rootRecordID: metadata.rootRecordID,
                    shareRecordID: share.recordID,
                    isShared: true
                )
                await metadataStore.upsert(stored)
            }
        }
    }

    // MARK: - SharedRecordIngesting

    func ingest(records: [CKRecord], deletedRecordIDs: [CKRecord.ID], in zoneID: CKRecordZone.ID) async {
        await persist(records: records, deletedRecordIDs: deletedRecordIDs, in: zoneID)
    }

    // MARK: - Acceptance pipeline

    private func acceptShares(_ metadatas: [CKShare.Metadata]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var firstError: Error?
            let operation = CKAcceptSharesOperation(shareMetadatas: metadatas)
            operation.perShareResultBlock = { _, result in
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    if let error = firstError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            self.container.add(operation)
        }
    }

    private func fetchAndIngestInitialContent(for zoneID: CKRecordZone.ID) async throws -> ZoneFetchResult {
        let result = try await fetchZoneChanges(zoneID: zoneID, previousToken: nil)
        await tokenStore.store(token: result.newToken, for: zoneID)
        await persist(records: result.records, deletedRecordIDs: result.deleted, in: zoneID)
        return result
    }

    private func fetchZoneChanges(zoneID: CKRecordZone.ID,
                                  previousToken: CKServerChangeToken?) async throws -> ZoneFetchResult {
        try await withCheckedThrowingContinuation { continuation in
            var changedRecords: [CKRecord] = []
            var deletedRecords: [CKRecord.ID] = []
            var newToken: CKServerChangeToken?
            var hasFinished = false

            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: previousToken)
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.recordChangedBlock = { record in
                changedRecords.append(record)
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                deletedRecords.append(recordID)
            }
            operation.recordZoneFetchResultBlock = { _, result in
                guard hasFinished == false else { return }
                switch result {
                case .success(let info):
                    newToken = info.serverChangeToken
                case .failure(let error):
                    hasFinished = true
                    continuation.resume(throwing: error)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                guard hasFinished == false else { return }
                switch result {
                case .success:
                    hasFinished = true
                    let payload = ZoneFetchResult(records: changedRecords,
                                                  deleted: deletedRecords,
                                                  newToken: newToken)
                    continuation.resume(returning: payload)
                case .failure(let error):
                    hasFinished = true
                    continuation.resume(throwing: error)
                }
            }
            self.sharedDatabase.add(operation)
        }
    }

    private func persist(records: [CKRecord], deletedRecordIDs: [CKRecord.ID], in _: CKRecordZone.ID) async {
        guard records.isEmpty == false || deletedRecordIDs.isEmpty == false else { return }
        let modelContainer = self.modelContainer
        let logger = self.logger
        await Task.detached(priority: .userInitiated) { [modelContainer, logger] in
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false

            do {
                var hasMutations = false
                for record in records {
                    switch record.recordType {
                    case RecordType.profile:
                        if try Self.updateProfile(from: record, in: context) {
                            hasMutations = true
                        }
                    case RecordType.babyAction:
                        if try Self.updateAction(from: record, in: context) {
                            hasMutations = true
                        }
                    default:
                        continue
                    }
                }

                for recordID in deletedRecordIDs {
                    if try Self.deleteRecord(with: recordID, in: context) {
                        hasMutations = true
                    }
                }

                if hasMutations, context.hasChanges {
                    try context.save()
                }
            } catch {
                logger.error("Failed to persist shared changes: \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }

    private static func updateProfile(from record: CKRecord, in context: ModelContext) throws -> Bool {
        guard let profileIDString = record["profileID"] as? String,
              let profileID = UUID(uuidString: profileIDString) else {
            return false
        }
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == profileID
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        let model = existing ?? ProfileActionStateModel(profileID: profileID)
        if existing == nil {
            context.insert(model)
        }

        var mutated = false
        if let name = record["name"] as? String, model.name != name {
            model.name = name
            mutated = true
        }

        if let birthDate = record["birthDate"] as? Date {
            if model.birthDate != birthDate {
                model.birthDate = birthDate
                mutated = true
            }
        } else if model.birthDate != nil {
            model.birthDate = nil
            mutated = true
        }

        if let asset = record["image"] as? CKAsset,
           let url = asset.fileURL,
           let data = try? Data(contentsOf: url),
           model.imageData != data {
            model.imageData = data
            mutated = true
        }

        return mutated
    }

    private static func updateAction(from record: CKRecord, in context: ModelContext) throws -> Bool {
        guard let idString = record["id"] as? String,
              let actionID = UUID(uuidString: idString) else {
            return false
        }

        let predicate = #Predicate<BabyActionModel> { model in
            model.id == actionID
        }
        var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        let model = existing ?? BabyActionModel(id: actionID)
        if existing == nil {
            context.insert(model)
        }

        var mutated = false
        if let categoryRaw = record["category"] as? String,
           let category = BabyActionCategory(rawValue: categoryRaw),
           model.category != category {
            model.category = category
            mutated = true
        }
        if let startDate = record["startDate"] as? Date, model.startDate != startDate {
            model.startDate = startDate
            mutated = true
        }
        let endDate = record["endDate"] as? Date
        if model.endDate != endDate {
            model.endDate = endDate
            mutated = true
        }
        if let diaper = record["diaperType"] as? String {
            let diaperType = BabyAction.DiaperType(rawValue: diaper)
            if model.diaperType != diaperType {
                model.diaperType = diaperType
                mutated = true
            }
        } else if model.diaperType != nil {
            model.diaperType = nil
            mutated = true
        }
        if let feeding = record["feedingType"] as? String {
            let feedingType = BabyAction.FeedingType(rawValue: feeding)
            if model.feedingType != feedingType {
                model.feedingType = feedingType
                mutated = true
            }
        } else if model.feedingType != nil {
            model.feedingType = nil
            mutated = true
        }
        if let bottleTypeRaw = record["bottleType"] as? String {
            let bottleType = BabyAction.BottleType(rawValue: bottleTypeRaw)
            if model.bottleType != bottleType {
                model.bottleType = bottleType
                mutated = true
            }
        } else if model.bottleType != nil {
            model.bottleType = nil
            mutated = true
        }
        if let bottleVolumeNumber = record["bottleVolume"] as? NSNumber {
            let volume = bottleVolumeNumber.intValue
            if model.bottleVolume != volume {
                model.bottleVolume = volume
                mutated = true
            }
        } else if model.bottleVolume != nil {
            model.bottleVolume = nil
            mutated = true
        }
        if let updatedAt = record["updatedAt"] as? Date, model.updatedAt != updatedAt {
            model.updatedAt = updatedAt
            mutated = true
        }

        if let profileRef = record["profile"] as? CKRecord.Reference {
            let profileIDString = profileRef.recordID.recordName.replacingOccurrences(of: "profile-", with: "")
            if let profileID = UUID(uuidString: profileIDString) {
                let predicate = #Predicate<ProfileActionStateModel> { model in
                    model.profileID == profileID
                }
                var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
                descriptor.fetchLimit = 1
                if let profileModel = try context.fetch(descriptor).first {
                    if model.profile !== profileModel {
                        model.profile = profileModel
                        mutated = true
                    }
                }
            }
        } else if model.profile != nil {
            model.profile = nil
            mutated = true
        }

        return mutated
    }

    private static func deleteRecord(with recordID: CKRecord.ID, in context: ModelContext) throws -> Bool {
        if recordID.recordName.hasPrefix("action-"),
           let uuid = UUID(uuidString: recordID.recordName.replacingOccurrences(of: "action-", with: "")) {
            let predicate = #Predicate<BabyActionModel> { model in
                model.id == uuid
            }
            var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let model = try context.fetch(descriptor).first {
                context.delete(model)
                return true
            }
        } else if recordID.recordName.hasPrefix("profile-"),
                  let uuid = UUID(uuidString: recordID.recordName.replacingOccurrences(of: "profile-", with: "")) {
            let predicate = #Predicate<ProfileActionStateModel> { model in
                model.profileID == uuid
            }
            var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let model = try context.fetch(descriptor).first {
                context.delete(model)
                return true
            }
        }
        return false
    }
}

extension ShareAcceptanceHandler {
    struct ZoneFetchResult {
        let records: [CKRecord]
        let deleted: [CKRecord.ID]
        let newToken: CKServerChangeToken?
    }

    enum RecordType {
        static let profile = "Profile"
        static let babyAction = "BabyAction"
    }
}
