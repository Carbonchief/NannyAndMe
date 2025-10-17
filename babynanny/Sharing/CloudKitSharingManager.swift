import CloudKit
import Foundation
import os
import SwiftData

/// Manages CloudKit sharing for a `ProfileActionStateModel` and its related `BabyActionModel`s.
/// The manager encapsulates zone creation, share lifecycle, participant management and
/// metadata persistence so that shares can be reused idempotently.
final class CloudKitSharingManager {
    enum SharingError: Error {
        case profileNotFound
        case shareSaveFailed
        case missingShareMetadata
        case participantNotFound
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let modelContainer: ModelContainer
    private let metadataStore: ShareMetadataStore
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share")

    init(containerIdentifier: String = "iCloud.com.prioritybit.babynanny",
         modelContainer: ModelContainer,
         metadataStore: ShareMetadataStore = ShareMetadataStore()) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
        self.modelContainer = modelContainer
        self.metadataStore = metadataStore
    }

    // MARK: - Public API

    /// Ensures a `CKShare` exists for the provided profile.
    /// - Returns: The existing or newly created share.
    func ensureShare(for profileID: UUID) async throws -> CKShare {
        if let existing = try await reuseExistingShareIfPossible(for: profileID) {
            return existing
        }

        var zoneID = try await ensureZone(for: profileID)
        let snapshot = try await loadSnapshot(for: profileID)
        guard let snapshot else { throw SharingError.profileNotFound }

        do {
            return try await createShare(for: profileID, snapshot: snapshot, zoneID: zoneID)
        } catch {
            guard shouldResetZone(after: error) else { throw error }
            logger.warning(
                "Share creation failed due to stale zone for profile \(profileID.uuidString, privacy: .public); resetting zone"
            )
            await resetZone(for: profileID, zoneID: zoneID)
            zoneID = try await ensureZone(for: profileID)
            return try await createShare(for: profileID, snapshot: snapshot, zoneID: zoneID)
        }
    }

    /// Fetches participants for the current share associated with the profile.
    func fetchParticipants(for profileID: UUID) async throws -> [CKShare.Participant] {
        let share = try await ensureShare(for: profileID)
        return share.participants
    }

    /// Updates a participant's role or permission within the share.
    func updateParticipant(_ participant: CKShare.Participant,
                           role: CKShare.ParticipantRole?,
                           permission: CKShare.ParticipantPermission?) async throws {
        let profileID = try await resolveProfileID(for: participant)
        let share = try await ensureShare(for: profileID)
        guard let target = share.participants.first(where: { $0.userIdentity.userRecordID == participant.userIdentity.userRecordID }) else {
            throw SharingError.participantNotFound
        }
        if let role { target.role = role }
        if let permission { target.permission = permission }
        _ = try await saveShareTree(records: [], share: share)
        logger.log("Updated participant \(participant.userIdentity.lookupInfo?.emailAddress ?? "unknown", privacy: .public) for profile \(profileID.uuidString, privacy: .public)")
    }

    /// Removes the participant from the share.
    func removeParticipant(_ participant: CKShare.Participant) async throws {
        let profileID = try await resolveProfileID(for: participant)
        let share = try await ensureShare(for: profileID)
        guard let target = share.participants.first(where: { $0.userIdentity.userRecordID == participant.userIdentity.userRecordID }) else {
            throw SharingError.participantNotFound
        }
        share.removeParticipant(target)
        _ = try await saveShareTree(records: [], share: share)
        logger.log("Removed participant for profile \(profileID.uuidString, privacy: .public)")
    }

    /// Stops sharing and tears down the associated zone metadata.
    func stopSharing(profileID: UUID) async throws {
        guard let metadata = await metadataStore.metadata(for: profileID) else { return }
        let shareID = metadata.shareRecordID
        do {
            try await privateDatabase.deleteRecordAsync(withID: shareID)
        } catch {
            logger.error("Failed deleting share record: \(error.localizedDescription, privacy: .public)")
        }
        do {
            try await privateDatabase.deleteZoneAsync(withID: metadata.zoneID)
        } catch {
            logger.error("Failed deleting zone: \(error.localizedDescription, privacy: .public)")
        }
        await metadataStore.remove(profileID: profileID)
        logger.log("Stopped sharing for profile \(profileID.uuidString, privacy: .public)")
    }

    // MARK: - Internal helpers

    private func reuseExistingShareIfPossible(for profileID: UUID) async throws -> CKShare? {
        guard let metadata = await metadataStore.metadata(for: profileID) else { return nil }
        do {
            let share = try await privateDatabase.record(withID: metadata.shareRecordID)
            guard let share = share as? CKShare else {
                logger.error("Fetched record for share was not a CKShare")
                return nil
            }
            return share
        } catch {
            logger.error("Failed to fetch existing share: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func createShare(for profileID: UUID,
                             snapshot: ProfileSnapshot,
                             zoneID: CKRecordZone.ID) async throws -> CKShare {
        defer { TemporaryFileManager.shared.cleanup() }

        let (records, share) = try buildRecordsForSharing(snapshot: snapshot, zoneID: zoneID)
        let savedShare = try await saveShareTree(records: records, share: share)

        let metadata = ShareMetadataStore.ShareMetadata(
            profileID: profileID,
            zoneID: zoneID,
            rootRecordID: snapshot.profileRecordID(in: zoneID),
            shareRecordID: savedShare.recordID,
            isShared: true
        )
        await metadataStore.upsert(metadata)
        logger.log("Created CloudKit share for profile \(profileID.uuidString, privacy: .public)")
        return savedShare
    }

    private func resolveProfileID(for participant: CKShare.Participant) async throws -> UUID {
        let metadata = await metadataStore.allMetadata()
        for (profileID, _) in metadata {
            guard let share = try await reuseExistingShareIfPossible(for: profileID) else { continue }
            if share.participants.contains(where: { $0.userIdentity.userRecordID == participant.userIdentity.userRecordID }) {
                return profileID
            }
        }
        throw SharingError.missingShareMetadata
    }

    private func ensureZone(for profileID: UUID) async throws -> CKRecordZone.ID {
        if let metadata = await metadataStore.metadata(for: profileID) {
            return metadata.zoneID
        }
        let zoneID = CKRecordZone.ID(zoneName: zoneName(for: profileID))
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            try await privateDatabase.saveZoneAsync(zone)
        } catch {
            if let ckError = error as? CKError,
               ckError.code.rawValue == CKError.Code.zoneAlreadyExistsRawValue {
                // The zone already exists, which is acceptable for idempotent sharing.
            } else {
                throw error
            }
        }
        return zoneID
    }

    private func resetZone(for profileID: UUID, zoneID: CKRecordZone.ID) async {
        let existingMetadata = await metadataStore.metadata(for: profileID)
        await metadataStore.remove(profileID: profileID)
        if let shareID = existingMetadata?.shareRecordID {
            do {
                try await privateDatabase.deleteRecordAsync(withID: shareID)
            } catch {
                logger.error(
                    "Failed to delete stale share for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        do {
            try await privateDatabase.deleteZoneAsync(withID: zoneID)
        } catch {
            logger.error(
                "Failed to delete stale zone for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func shouldResetZone(after error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID {
            return partialErrors.values.contains(where: { element in
                guard let partialError = element as? CKError else { return false }
                return shouldResetZone(after: partialError)
            })
        }
        switch ckError.code {
        case .serverRecordChanged, .batchRequestFailed, .zoneBusy:
            return true
        default:
            return false
        }
    }

    private func loadSnapshot(for profileID: UUID) async throws -> ProfileSnapshot? {
        try await Task.detached(priority: .userInitiated) { [modelContainer] in
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            let predicate = #Predicate<ProfileActionStateModel> { model in
                model.profileID == profileID
            }
            var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let profile = try context.fetch(descriptor).first else {
                return nil
            }
            profile.ensureActionOwnership()
            let actions = profile.actions
            return ProfileSnapshot(profile: profile, actions: actions)
        }.value
    }

    private func buildRecordsForSharing(snapshot: ProfileSnapshot,
                                        zoneID: CKRecordZone.ID) throws -> ([CKRecord], CKShare) {
        let profileRecordID = snapshot.profileRecordID(in: zoneID)
        let profileRecord = CKRecord(recordType: RecordType.profile.rawValue, recordID: profileRecordID)
        profileRecord["profileID"] = snapshot.profileID.uuidString as CKRecordValue
        if let name = snapshot.profile.name {
            profileRecord["name"] = name as CKRecordValue
        }
        if let birthDate = snapshot.profile.birthDate {
            profileRecord["birthDate"] = birthDate as CKRecordValue
        }
        let profileImageData = snapshot.profile.imageData
        if let imageData = profileImageData {
            let file = try TemporaryFileManager.shared.write(data: imageData)
            profileRecord["image"] = CKAsset(fileURL: file)
        }

        let share = CKShare(rootRecord: profileRecord)
        share.publicPermission = .readOnly
        if let name = snapshot.profile.name {
            share[CKShare.SystemFieldKey.title] = name as CKRecordValue
        }
        if let imageData = profileImageData {
            share[CKShare.SystemFieldKey.thumbnailImageData] = imageData as CKRecordValue
        }

        let actionRecords: [CKRecord] = snapshot.actions.map { action in
            let recordID = CKRecord.ID(recordName: "action-\(action.id.uuidString)", zoneID: zoneID)
            let record = CKRecord(recordType: RecordType.babyAction.rawValue, recordID: recordID)
            record["id"] = action.id.uuidString as CKRecordValue
            record["category"] = action.category.rawValue as CKRecordValue
            record["startDate"] = action.startDate as CKRecordValue
            if let endDate = action.endDate {
                record["endDate"] = endDate as CKRecordValue
            }
            if let diaper = action.diaperType?.rawValue {
                record["diaperType"] = diaper as CKRecordValue
            }
            if let feeding = action.feedingType?.rawValue {
                record["feedingType"] = feeding as CKRecordValue
            }
            if let bottleType = action.bottleType?.rawValue {
                record["bottleType"] = bottleType as CKRecordValue
            }
            if let bottleVolume = action.bottleVolume {
                record["bottleVolume"] = bottleVolume as CKRecordValue
            }
            record["updatedAt"] = action.updatedAt as CKRecordValue
            record["profile"] = CKRecord.Reference(recordID: profileRecordID, action: .deleteSelf)
            return record
        }

        return (actionRecords + [profileRecord], share)
    }

    @discardableResult
    private func saveShareTree(records: [CKRecord], share: CKShare) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            var savedShare: CKShare?
            var firstError: Error?

            let operation = CKModifyRecordsOperation(recordsToSave: records + [share], recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged
            operation.isAtomic = true
            operation.perRecordSaveBlock = { _, result in
                switch result {
                case .success(let record):
                    if let fetchedShare = record as? CKShare {
                        savedShare = fetchedShare
                    }
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let error = firstError {
                        continuation.resume(throwing: error)
                    } else if let savedShare {
                        continuation.resume(returning: savedShare)
                    } else {
                        continuation.resume(throwing: SharingError.shareSaveFailed)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }
    }

    private func zoneName(for profileID: UUID) -> String {
        "shared-profile-\(profileID.uuidString)"
    }
}

// MARK: - Snapshot helpers

private extension CloudKitSharingManager {
    enum RecordType: String {
        case profile = "Profile"
        case babyAction = "BabyAction"
    }

    struct ProfileSnapshot {
        let profile: ProfileActionStateModel
        let actions: [BabyActionModel]

        var profileID: UUID { profile.resolvedProfileID }

        func profileRecordID(in zoneID: CKRecordZone.ID) -> CKRecord.ID {
            CKRecord.ID(recordName: "profile-\(profileID.uuidString)", zoneID: zoneID)
        }
    }
}

// MARK: - Metadata persistence

actor ShareMetadataStore {
    struct ShareMetadata: Codable {
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
    }

    private let defaults: UserDefaults
    private let storageKey = "com.prioritybit.babynanny.share.metadata"
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

// MARK: - Temporary files

private final class TemporaryFileManager {
    static let shared = TemporaryFileManager()

    private init() {}

    private var files: Set<URL> = []

    func write(data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fileURL = directory.appendingPathComponent(UUID().uuidString)
        try data.write(to: fileURL)
        files.insert(fileURL)
        return fileURL
    }

    func cleanup() {
        let currentFiles = files
        files.removeAll()
        for file in currentFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private extension CKDatabase {
    func record(withID recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let record else {
                    continuation.resume(throwing: CKError(.unknownItem))
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    func saveZoneAsync(_ zone: CKRecordZone) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            save(zone) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func deleteRecordAsync(withID recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete(withRecordID: recordID) { _, error in
                if let error {
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
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

extension ShareMetadataStore.ShareMetadata {
    init(profileID: UUID,
         zoneID: CKRecordZone.ID,
         rootRecordID: CKRecord.ID,
         shareRecordID: CKRecord.ID,
         isShared: Bool) {
        self.profileID = profileID
        self.zoneName = zoneID.zoneName
        self.ownerName = zoneID.ownerName
        self.rootRecordName = rootRecordID.recordName
        self.shareRecordName = shareRecordID.recordName
        self.isShared = isShared
    }
}

private extension CKError.Code {
    /// Raw value for `zoneAlreadyExists`, exposed directly to remain compatible with SDK surfaces lacking the symbol.
    static let zoneAlreadyExistsRawValue: Int = 26
}
