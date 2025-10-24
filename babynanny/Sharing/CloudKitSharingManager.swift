import CloudKit
import Foundation
import os
import SwiftData

/// Provides a thin wrapper around SwiftData's sharing APIs so callers don't have
/// to interact with CloudKit operations directly.
@MainActor
final class CloudKitSharingManager {
    enum SharingError: Error {
        case profileNotFound
        case participantNotFound
        case shareUnavailable
    }

    private static let minimumCompatibleShareVersion = 0

    private let modelContainer: ModelContainer
    private let metadataStore: ShareMetadataStore
    private let privateDatabase: CKDatabase
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "share")

    init(modelContainer: ModelContainer,
         metadataStore: ShareMetadataStore = ShareMetadataStore(),
         containerIdentifier: String = CKConfig.containerID) {
        self.modelContainer = modelContainer
        self.metadataStore = metadataStore
        let container = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Public API

    func ensureShare(for profileID: UUID) async throws -> CKShare {
        if let cached = await metadataStore.metadata(for: profileID) {
            do {
                let share = try await fetchShare(with: cached.shareRecordID)
                await ensureCompatibility(for: share)
                await persistMetadataIfNeeded(for: share,
                                             profileID: profileID,
                                             rootRecordID: cached.rootRecordID)
                return share
            } catch {
                logger.error("Failed to load cached share metadata: \(error.localizedDescription, privacy: .public)")
                await metadataStore.remove(profileID: profileID)
            }
        }

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let profile = try fetchProfile(in: context, id: profileID) else {
            throw SharingError.profileNotFound
        }

        let rootRecord = try await ensureRootRecord(for: profile)
        if let shareReference = rootRecord.share {
            let share = try await fetchShare(with: shareReference.recordID)
            await ensureCompatibility(for: share)
            await persistMetadataIfNeeded(for: share,
                                         profileID: profileID,
                                         rootRecordID: rootRecord.recordID)
            return share
        }

        let share = try await createShare(rootRecord: rootRecord,
                                          title: profile.name,
                                          thumbnailData: profile.imageData)
        await ensureCompatibility(for: share, rootRecord: rootRecord)
        await persistMetadataIfNeeded(for: share,
                                     profileID: profileID,
                                     rootRecordID: rootRecord.recordID)
        logger.log("Created share for profile \(profileID.uuidString, privacy: .public)")
        return share
    }

    func fetchParticipants(for profileID: UUID) async throws -> [CKShare.Participant] {
        let share = try await ensureShare(for: profileID)
        return share.participants
    }

    func updateParticipant(for profileID: UUID,
                           participant target: CKShare.Participant,
                           role: CKShare.ParticipantRole?,
                           permission: CKShare.ParticipantPermission?) async throws {
        let share = try await ensureShare(for: profileID)
        guard let existing = share.participants.first(where: { $0.userIdentity.userRecordID == target.userIdentity.userRecordID }) else {
            throw SharingError.participantNotFound
        }
        if let role = role { existing.role = role }
        if let permission = permission { existing.permission = permission }
        try await save(share: share)
        logger.log("Updated participant for profile \(profileID.uuidString, privacy: .public)")
    }

    func removeParticipant(for profileID: UUID, participant target: CKShare.Participant) async throws {
        let share = try await ensureShare(for: profileID)
        guard let existing = share.participants.first(where: { $0.userIdentity.userRecordID == target.userIdentity.userRecordID }) else {
            throw SharingError.participantNotFound
        }
        share.removeParticipant(existing)
        try await save(share: share)
        logger.log("Removed participant for profile \(profileID.uuidString, privacy: .public)")
    }

    func stopSharing(profileID: UUID) async throws {
        if let metadata = await metadataStore.metadata(for: profileID) {
            do {
                try await privateDatabase.deleteRecordAsync(withID: metadata.shareRecordID)
            } catch {
                logger.error("Failed to delete share record: \(error.localizedDescription, privacy: .public)")
            }
            do {
                try await privateDatabase.deleteZoneAsync(withID: metadata.zoneID)
            } catch {
                logger.error("Failed to delete zone: \(error.localizedDescription, privacy: .public)")
            }
            await metadataStore.remove(profileID: profileID)
        }
        logger.log("Stopped sharing for profile \(profileID.uuidString, privacy: .public)")
    }

    func resolveShare(for profileID: UUID) async throws -> CKShare {
        try await ensureShare(for: profileID)
    }

    func synchronizeSharedContent(for profileID: UUID) async {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        do {
            guard let profile = try fetchProfile(in: context, id: profileID) else { return }
            _ = try await ensureRootRecord(for: profile)
        } catch {
            logger.error("Failed to synchronize shared content for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func fetchProfile(in context: ModelContext, id: UUID) throws -> Profile? {
        let predicate = #Predicate<Profile> { model in
            model.profileID == id
        }
        var descriptor = FetchDescriptor<Profile>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func persistMetadataIfNeeded(for share: CKShare,
                                         profileID: UUID,
                                         rootRecordID: CKRecord.ID?) async {
        let zoneID = share.recordID.zoneID
        let resolvedRootRecordID = await resolveRootRecordID(for: share,
                                                             profileID: profileID,
                                                             fallbackZoneID: zoneID,
                                                             providedRootRecordID: rootRecordID)
        let metadata = ShareMetadataStore.ShareMetadata(
            profileID: profileID,
            zoneID: zoneID,
            rootRecordID: resolvedRootRecordID,
            shareRecordID: share.recordID,
            isShared: true
        )
        await metadataStore.upsert(metadata)
    }

    private func save(share: CKShare, rootRecord: CKRecord? = nil) async throws {
        var records: [CKRecord] = [share]
        if let rootRecord = rootRecord {
            records.append(rootRecord)
        }
        try await save(records: records)
    }

    private func save(records: [CKRecord], deleting recordIDs: [CKRecord.ID] = []) async throws {
        guard records.isEmpty == false || recordIDs.isEmpty == false else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records.isEmpty ? nil : records,
                                                     recordIDsToDelete: recordIDs.isEmpty ? nil : recordIDs)
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }
    }

    private func fetchShare(with recordID: CKRecord.ID) async throws -> CKShare {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
            privateDatabase.fetch(withRecordID: recordID) { record, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let share = record as? CKShare else {
                    continuation.resume(throwing: SharingError.shareUnavailable)
                    return
                }
                continuation.resume(returning: share)
            }
        }
    }

    private func ensureRootRecord(for profile: ProfileActionStateModel) async throws -> CKRecord {
        let zoneID = CloudKitProfileZone.zoneID(for: profile.profileID)
        try await ensureZoneExists(zoneID: zoneID)
        if let existing = try await fetchRecord(withID: CloudKitProfileZone.profileRecordID(for: profile.profileID)) {
            let updated = CloudKitRecordMapper.makeProfileRecord(from: profile,
                                                                 zoneID: zoneID,
                                                                 existing: existing)
            try await save(records: [updated])
            try await synchronizeActions(for: profile, zoneID: zoneID)
            return updated
        }
        return try await uploadSnapshot(for: profile, zoneID: zoneID)
    }

    private func ensureZoneExists(zoneID: CKRecordZone.ID) async throws {
        if try await zoneExists(withID: zoneID) {
            return
        }
        try await createZoneIfNeeded(withID: zoneID)
    }

    private func zoneExists(withID zoneID: CKRecordZone.ID) async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            privateDatabase.fetch(withRecordZoneID: zoneID) { zone, error in
                if zone != nil {
                    continuation.resume(returning: true)
                    return
                }
                if let ckError = error as? CKError {
                    if ckError.code == .zoneNotFound {
                        continuation.resume(returning: false)
                        return
                    }
                    continuation.resume(throwing: ckError)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: false)
            }
        }
    }

    private func createZoneIfNeeded(withID zoneID: CKRecordZone.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let zone = CKRecordZone(zoneID: zoneID)
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    Task { @MainActor in
                        if let exists = try? await self.zoneExists(withID: zoneID), exists {
                            continuation.resume(returning: ())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
            privateDatabase.add(operation)
        }
    }

    private func uploadSnapshot(for profile: ProfileActionStateModel,
                                zoneID: CKRecordZone.ID) async throws -> CKRecord {
        var records: [CKRecord] = []
        let profileRecord = CloudKitRecordMapper.makeProfileRecord(from: profile, zoneID: zoneID)
        records.append(profileRecord)
        for action in profile.actions {
            let actionRecord = CloudKitRecordMapper.makeBabyActionRecord(from: action,
                                                                        profileID: profile.profileID,
                                                                        zoneID: zoneID)
            records.append(actionRecord)
        }
        try await save(records: records)
        return profileRecord
    }

    private func synchronizeActions(for profile: ProfileActionStateModel,
                                    zoneID: CKRecordZone.ID) async throws {
        let existingRecords = try await fetchExistingActionRecords(in: zoneID)
        var remainingExisting = Set(existingRecords.keys)
        var recordsToSave: [CKRecord] = []

        for action in profile.actions {
            let recordName = CloudKitProfileZone.babyActionRecordName(for: action.id)
            let existing = existingRecords[recordName]
            let record = CloudKitRecordMapper.makeBabyActionRecord(from: action,
                                                                  profileID: profile.profileID,
                                                                  zoneID: zoneID,
                                                                  existing: existing)
            recordsToSave.append(record)
            remainingExisting.remove(recordName)
        }

        let idsToDelete = remainingExisting.compactMap { existingRecords[$0]?.recordID }
        try await save(records: recordsToSave, deleting: idsToDelete)
    }

    private func fetchExistingActionRecords(in zoneID: CKRecordZone.ID) async throws -> [String: CKRecord] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: CKRecord], Error>) in
            let query = CKQuery(recordType: CloudKitRecordMapper.babyActionRecordType,
                                predicate: NSPredicate(value: true))
            let operation = CKQueryOperation(query: query)
            operation.zoneID = zoneID
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.desiredKeys = []
            var records: [String: CKRecord] = [:]
            let logger = self.logger
            operation.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    records[recordID.recordName.lowercased()] = record
                case .failure(let error):
                    logger.error("Failed to enumerate action record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    if error.isMissingRecordTypeError {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.privateDatabase.add(operation)
        }
    }

    private func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord?, Error>) in
            privateDatabase.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError {
                    if ckError.code == .unknownItem {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: ckError)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    private func createShare(rootRecord: CKRecord,
                             title: String?,
                             thumbnailData: Data?) async throws -> CKShare {
        let share = CKShare(rootRecord: rootRecord)
        setMinimumCompatibleVersion(Self.minimumCompatibleShareVersion, for: share)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue?
        if let thumbnailData = thumbnailData {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailData as CKRecordValue
        }
        do {
            try await save(share: share, rootRecord: rootRecord)
        } catch {
            throw error
        }
        return share
    }

    private func resolveRootRecordID(for share: CKShare,
                                     profileID: UUID,
                                     fallbackZoneID: CKRecordZone.ID,
                                     providedRootRecordID: CKRecord.ID?) async -> CKRecord.ID {
        if let providedRootRecordID = providedRootRecordID {
            return providedRootRecordID
        }
        if let cached = await metadataStore.metadata(for: profileID) {
            return cached.rootRecordID
        }
        if let extracted = fallbackRootRecordID(from: share) {
            return extracted
        }
        return CloudKitProfileZone.profileRecordID(for: profileID, ownerName: fallbackZoneID.ownerName)
    }

    private func fallbackRootRecordID(from share: CKShare) -> CKRecord.ID? {
        (share as NSObject).value(forKey: "rootRecordID") as? CKRecord.ID
    }

    private func ensureCompatibility(for share: CKShare, rootRecord: CKRecord? = nil) async {
        let target = Self.minimumCompatibleShareVersion
        guard needsCompatibilityUpdate(for: share, target: target) else { return }
        setMinimumCompatibleVersion(target, for: share)
        do {
            try await save(share: share, rootRecord: rootRecord)
        } catch {
            logger.error("Failed to update share compatibility: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func needsCompatibilityUpdate(for share: CKShare, target: Int) -> Bool {
        guard let current = minimumCompatibleVersion(for: share) else {
            return true
        }
        return current > target
    }

    private func minimumCompatibleVersion(for share: CKShare) -> Int? {
        let object = share as NSObject
        if let number = object.value(forKey: "minimumCompatibleVersion") as? NSNumber {
            return number.intValue
        }
        if let stringValue = object.value(forKey: "minimumCompatibleVersion") as? NSString {
            return Int(stringValue as String)
        }
        if let intValue = object.value(forKey: "minimumCompatibleVersion") as? Int {
            return intValue
        }
        return nil
    }

    private func setMinimumCompatibleVersion(_ value: Int, for share: CKShare) {
        let object = share as NSObject
        object.setValue(value, forKey: "minimumCompatibleVersion")
    }
}

// MARK: - Snapshot helpers

// MARK: - Metadata persistence

actor ShareMetadataStore {
    struct ShareMetadata: Codable {
        private enum CodingKeys: String, CodingKey {
            case profileID
            case zoneName
            case ownerName
            case rootRecordName
            case shareRecordName
            case isShared
        }

        var profileID: UUID
        var zoneName: String
        var ownerName: String
        var rootRecordName: String
        var shareRecordName: String
        var isShared: Bool

        var zoneID: CKRecordZone.ID {
            CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }

        var rootRecordID: CKRecord.ID {
            CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
        }

        var shareRecordID: CKRecord.ID {
            CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)
        }

        init(profileID: UUID,
             zoneID: CKRecordZone.ID,
             rootRecordID: CKRecord.ID,
             shareRecordID: CKRecord.ID,
             isShared: Bool) {
            self.profileID = profileID
            self.zoneName = zoneID.zoneName
            self.ownerName = zoneID.ownerName ?? CKCurrentUserDefaultName
            self.rootRecordName = rootRecordID.recordName
            self.shareRecordName = shareRecordID.recordName
            self.isShared = isShared
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileID = try container.decode(UUID.self, forKey: .profileID)
            zoneName = try container.decode(String.self, forKey: .zoneName)
            ownerName = try container.decode(String.self, forKey: .ownerName)
            rootRecordName = try container.decode(String.self, forKey: .rootRecordName)
            shareRecordName = try container.decode(String.self, forKey: .shareRecordName)
            isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(profileID, forKey: .profileID)
            try container.encode(zoneName, forKey: .zoneName)
            try container.encode(ownerName, forKey: .ownerName)
            try container.encode(rootRecordName, forKey: .rootRecordName)
            try container.encode(shareRecordName, forKey: .shareRecordName)
            try container.encode(isShared, forKey: .isShared)
        }
    }

    private let defaults: UserDefaults
    private let storageKey = "com.prioritybit.nannyandme.share.metadata"
    private var cache: [UUID: ShareMetadata]

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PersistedEntry].self, from: data) {
            cache = decoded.reduce(into: [:]) { partialResult, element in
                partialResult[element.profileID] = element.metadata
            }
        } else {
            cache = [:]
        }
    }

    func metadata(for profileID: UUID) -> ShareMetadata? {
        cache[profileID]
    }

    func upsert(_ metadata: ShareMetadata) {
        cache[metadata.profileID] = metadata
        persist()
    }

    func remove(profileID: UUID) {
        cache.removeValue(forKey: profileID)
        persist()
    }

    func allMetadata() -> [UUID: ShareMetadata] {
        cache
    }

    private func persist() {
        let payload = cache.map { PersistedEntry(profileID: $0.key, metadata: $0.value) }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private struct PersistedEntry: Codable {
        let profileID: UUID
        let metadata: ShareMetadata
    }
}

private extension CKDatabase {
    func deleteRecordAsync(withID recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete(withRecordID: recordID) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func deleteZoneAsync(withID zoneID: CKRecordZone.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete(withRecordZoneID: zoneID) { _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
