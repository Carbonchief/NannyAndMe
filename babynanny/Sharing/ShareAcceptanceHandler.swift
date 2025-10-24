import CloudKit
import Foundation
import os
import SwiftData

/// Describes a type that can accept CloudKit share metadata and ingest the associated records.
protocol CloudKitShareAccepting: AnyObject, Sendable {
    func accept(metadata: CKShare.Metadata) async throws
}

/// Handles the acceptance of incoming `CKShare`s and ingests the shared data into SwiftData.
final class ShareAcceptanceHandler: SharedRecordIngesting {
    private let container: CKContainer
    private let sharedDatabase: CKDatabase
    private let modelContainer: ModelContainer
    private let metadataStore: ShareMetadataStore
    private let tokenStore: SharedZoneChangeTokenStore
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "share")

    init(modelContainer: ModelContainer,
         containerIdentifier: String = CKConfig.containerID,
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
            guard let rootRecordID = metadata.resolveRootRecordID() else {
                logger.error("Unable to resolve root record ID for accepted share")
                continue
            }
            let zoneID = rootRecordID.zoneID
            let result = try await fetchAndIngestInitialContent(for: zoneID)
            let share = metadata.share
            if let profileRecord = result.records.first(where: { CloudKitRecordTypeCatalog.matchesProfile($0.recordType) }),
               let profileID = CloudKitRecordTypeCatalog.profileIdentifier(from: profileRecord) {
                let stored = ShareMetadataStore.ShareMetadata(
                    profileID: profileID,
                    zoneID: zoneID,
                    rootRecordID: rootRecordID,
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ZoneFetchResult, Error>) in
            var changedRecords: [CKRecord] = []
            var deletedRecords: [CKRecord.ID] = []
            var newToken: CKServerChangeToken?
            var hasFinished = false

            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: previousToken)
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            let logger = self.logger
            operation.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    changedRecords.append(record)
                case .failure(let error):
                    logger.error("Failed to fetch changed record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
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
                    case let type where CloudKitRecordTypeCatalog.matchesProfile(type):
                        if try Self.updateProfile(from: record, in: context) {
                            hasMutations = true
                        }
                    case let type where CloudKitRecordTypeCatalog.matchesBabyAction(type):
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
        guard let profileID = CloudKitRecordTypeCatalog.profileIdentifier(from: record) else {
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
        if let name = record["displayName"] as? String, model.name != name {
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

        if let createdAt = record["createdAt"] as? Date, model.createdAt != createdAt {
            model.createdAt = createdAt
            mutated = true
        }

        if let modifiedAt = record["modifiedAt"] as? Date, model.updatedAt != modifiedAt {
            model.updatedAt = modifiedAt
            mutated = true
        }

        if let data = record["imageData"] as? Data, model.imageData != data {
            model.imageData = data
            mutated = true
        } else if record["imageData"] == nil, model.imageData != nil {
            model.imageData = nil
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
        if let categoryRaw = record["type"] as? String,
           let category = BabyActionCategory(rawValue: categoryRaw),
           model.category != category {
            model.category = category
            mutated = true
        }
        if let startDate = record["timestamp"] as? Date, model.startDate != startDate {
            model.startDate = startDate
            mutated = true
        }
        let endDate = record["endDate"] as? Date
        if model.endDate != endDate {
            model.endDate = endDate
            mutated = true
        }
        if let diaper = record["diaperType"] as? String {
            let diaperType = BabyActionSnapshot.DiaperType(rawValue: diaper)
            if model.diaperType != diaperType {
                model.diaperType = diaperType
                mutated = true
            }
        } else if model.diaperType != nil {
            model.diaperType = nil
            mutated = true
        }
        if let feeding = record["feedingType"] as? String {
            let feedingType = BabyActionSnapshot.FeedingType(rawValue: feeding)
            if model.feedingType != feedingType {
                model.feedingType = feedingType
                mutated = true
            }
        } else if model.feedingType != nil {
            model.feedingType = nil
            mutated = true
        }
        if let bottleTypeRaw = record["bottleType"] as? String {
            let bottleType = BabyActionSnapshot.BottleType(rawValue: bottleTypeRaw)
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
        if let latitudeNumber = record["latitude"] as? NSNumber {
            let latitude = latitudeNumber.doubleValue
            if model.latitude != latitude {
                model.latitude = latitude
                mutated = true
            }
        } else if model.latitude != nil {
            model.latitude = nil
            mutated = true
        }
        if let longitudeNumber = record["longitude"] as? NSNumber {
            let longitude = longitudeNumber.doubleValue
            if model.longitude != longitude {
                model.longitude = longitude
                mutated = true
            }
        } else if model.longitude != nil {
            model.longitude = nil
            mutated = true
        }
        if let placename = record["notes"] as? String {
            if model.placename != placename {
                model.placename = placename
                mutated = true
            }
        } else if model.placename != nil {
            model.placename = nil
            mutated = true
        }
        if let updatedAt = record["modifiedAt"] as? Date, model.updatedAt != updatedAt {
            model.updatedAt = updatedAt
            mutated = true
        }

        if let profileRef = record["profileRef"] as? CKRecord.Reference {
            if let profileID = CloudKitProfileZone.profileID(from: profileRef.recordID.zoneID) ?? UUID(uuidString: profileRef.recordID.recordName) {
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
        } else if let profileIDString = record["profileID"] as? String,
                  let profileID = UUID(uuidString: profileIDString) {
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
        } else if model.profile != nil {
            model.profile = nil
            mutated = true
        }

        return mutated
    }

    private static func deleteRecord(with recordID: CKRecord.ID, in context: ModelContext) throws -> Bool {
        if let profileID = CloudKitProfileZone.profileID(from: recordID.zoneID) {
            let profileRecordName = CloudKitProfileZone.profileRecordName(for: profileID)
            if recordID.recordName.caseInsensitiveCompare(profileRecordName) == .orderedSame {
                let predicate = #Predicate<ProfileActionStateModel> { model in
                    model.profileID == profileID
                }
                var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
                descriptor.fetchLimit = 1
                if let model = try context.fetch(descriptor).first {
                    context.delete(model)
                    return true
                }
            }

            if let actionID = UUID(uuidString: recordID.recordName) ?? UUID(uuidString: recordID.recordName.replacingOccurrences(of: "action-", with: "")) {
                let predicate = #Predicate<BabyActionModel> { model in
                    model.id == actionID
                }
                var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
                descriptor.fetchLimit = 1
                if let model = try context.fetch(descriptor).first {
                    context.delete(model)
                    return true
                }
            }
        }

        return false
    }
}

private extension CKShare.Metadata {
    func resolveRootRecordID() -> CKRecord.ID? {
        if #available(iOS 17.0, macOS 14.0, *) {
            if let record = rootRecord {
                return record.recordID
            }
        }
        return value(forKey: "rootRecordID") as? CKRecord.ID
    }
}

extension ShareAcceptanceHandler {
    struct ZoneFetchResult {
        let records: [CKRecord]
        let deleted: [CKRecord.ID]
        let newToken: CKServerChangeToken?
    }
}

extension ShareAcceptanceHandler: CloudKitShareAccepting {}

extension ShareAcceptanceHandler: @unchecked Sendable {}
