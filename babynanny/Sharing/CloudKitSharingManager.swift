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
    }

    private let modelContainer: ModelContainer
    private let metadataStore: ShareMetadataStore
    private let privateDatabase: CKDatabase
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share")

    init(modelContainer: ModelContainer,
         metadataStore: ShareMetadataStore = ShareMetadataStore(),
         containerIdentifier: String = "iCloud.com.prioritybit.babynanny") {
        self.modelContainer = modelContainer
        self.metadataStore = metadataStore
        let container = CKContainer(identifier: containerIdentifier)
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Public API

    func ensureShare(for profileID: UUID) async throws -> CKShare {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let profile = try fetchProfile(in: context, id: profileID) else {
            throw SharingError.profileNotFound
        }

        if let existing = try context.existingShare(for: profile) {
            await persistMetadataIfNeeded(for: existing, profileID: profileID)
            return existing
        }

        let share = try context.share(profile)
        share[CKShare.SystemFieldKey.title] = profile.name as CKRecordValue?
        if let data = profile.imageData {
            share[CKShare.SystemFieldKey.thumbnailImageData] = data as CKRecordValue
        }
        try context.save()
        await persistMetadataIfNeeded(for: share, profileID: profileID)
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
        if let role { existing.role = role }
        if let permission { existing.permission = permission }
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

    // MARK: - Helpers

    private func fetchProfile(in context: ModelContext, id: UUID) throws -> Profile? {
        let predicate = #Predicate<Profile> { model in
            model.profileID == id
        }
        var descriptor = FetchDescriptor<Profile>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func persistMetadataIfNeeded(for share: CKShare, profileID: UUID) async {
        let zoneID = share.recordID.zoneID
        let rootRecordID = share.rootRecordID ?? CKRecord.ID(recordName: "profile-\(profileID.uuidString)", zoneID: zoneID)
        let metadata = ShareMetadataStore.ShareMetadata(
            profileID: profileID,
            zoneID: zoneID,
            rootRecordID: rootRecordID,
            shareRecordID: share.recordID,
            isShared: true
        )
        await metadataStore.upsert(metadata)
    }

    private func save(share: CKShare) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
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
}

// MARK: - Snapshot helpers

extension CloudKitSharingManager {
    enum RecordType: String {
        case profile = "Profile"
        case babyAction = "BabyAction"
    }
}

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

private extension CKDatabase {
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
