import CloudKit
import Foundation
import os
import SwiftData
import SwiftUI

@MainActor
final class SharingCoordinator: ObservableObject {
    struct ParticipantSummary: Identifiable, Equatable {
        let id: String
        let displayName: String
        let role: CKShare.ParticipantRole
        let permission: CKShare.ParticipantPermission
        let participant: CKShare.Participant

        init(participant: CKShare.Participant) {
            self.participant = participant
            self.role = participant.role
            self.permission = participant.permission
            if let recordID = participant.userIdentity.userRecordID {
                self.id = recordID.recordName
            } else if let email = participant.userIdentity.lookupInfo?.emailAddress {
                self.id = email
            } else if let phone = participant.userIdentity.lookupInfo?.phoneNumber {
                self.id = phone
            } else {
                self.id = UUID().uuidString
            }
            if let name = participant.userIdentity.nameComponents?.formatted() {
                self.displayName = name
            } else if let email = participant.userIdentity.lookupInfo?.emailAddress {
                self.displayName = email
            } else if let phone = participant.userIdentity.lookupInfo?.phoneNumber {
                self.displayName = phone
            } else if participant.role == .owner {
                self.displayName = L10n.ShareData.CloudKit.ownerPlaceholder
            } else {
                self.displayName = L10n.ShareData.CloudKit.unknownParticipant
            }
        }
    }

    enum Status: Equatable {
        case idle
        case loading
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var activeShare: CKShare?
    @Published private(set) var participants: [ParticipantSummary] = []

    private weak var dataStack: AppDataStack?
    private var modelContext: ModelContext? {
        dataStack?.mainContext
    }
    private var container: CKContainer?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "sharing")

    func configureIfNeeded(with dataStack: AppDataStack) {
        guard self.dataStack !== dataStack else { return }
        self.dataStack = dataStack
        self.container = CKContainer(identifier: AppDataStack.cloudKitContainerIdentifier)
    }

    func createShare(for profile: Profile) async throws -> (CKShare, CKContainer) {
        try ensureDependencies()
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        status = .loading

        do {
            let (context, container) = try dependencies()
            logger.log("Creating share for profile \(profile.id.uuidString, privacy: .public)")
            let share = try context.share(profile, to: nil)
            configureShareMetadata(share, for: profile)
            profile.shareRecordName = share.recordID.recordName
            profile.shareZoneName = share.recordID.zoneID.zoneName
            profile.shareOwnerName = share.recordID.zoneID.ownerName

            try context.save()

            try await refreshParticipants(for: profile)
            status = .idle
            return (share, container)
        } catch {
            logger.error("Share creation failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func refreshParticipants(for profile: Profile) async throws {
        try ensureDependencies()
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        status = .loading

        do {
            let (context, container) = try dependencies()
            guard let shareID = try await resolveShareID(for: profile, context: context) else {
                logger.log("No existing share found for profile \(profile.id.uuidString, privacy: .public)")
                activeShare = nil
                participants = []
                status = .idle
                return
            }

            logger.log("Fetching share metadata for profile \(profile.id.uuidString, privacy: .public)")
            let fetchedShare = try await fetchShare(with: shareID, container: container)
            profile.shareRecordName = fetchedShare.recordID.recordName
            profile.shareZoneName = fetchedShare.recordID.zoneID.zoneName
            profile.shareOwnerName = fetchedShare.recordID.zoneID.ownerName
            try context.save()
            activeShare = fetchedShare
            participants = fetchedShare.participants.map(ParticipantSummary.init)
            status = .idle
        } catch {
            logger.error("Refreshing participants failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func stopSharing(profile: Profile) async throws {
        try ensureDependencies()
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        status = .loading

        do {
            let (context, container) = try dependencies()
            guard let shareID = try await resolveShareID(for: profile, context: context) else {
                status = .idle
                return
            }

            logger.log("Stopping share for profile \(profile.id.uuidString, privacy: .public)")
            try await deleteShare(with: shareID, container: container)
            profile.shareRecordName = nil
            profile.shareZoneName = nil
            profile.shareOwnerName = nil
            activeShare = nil
            participants = []
            try context.save()
            status = .idle
        } catch {
            logger.error("Stopping share failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func remove(participant: CKShare.Participant, from profile: Profile) async throws {
        try ensureDependencies()
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        status = .loading

        do {
            let (context, container) = try dependencies()
            guard let shareID = try await resolveShareID(for: profile, context: context) else {
                status = .idle
                return
            }

            let share = try await fetchShare(with: shareID, container: container)
            if let target = share.participants.first(where: { existing in
                guard let existingID = existing.userIdentity.userRecordID else { return existing === participant }
                guard let targetID = participant.userIdentity.userRecordID else { return false }
                return existingID == targetID
            }) {
                share.removeParticipant(target)
            }

            try await saveShare(share, container: container)
            let refreshed = try await fetchShare(with: shareID, container: container)
            activeShare = refreshed
            participants = refreshed.participants.map(ParticipantSummary.init)
            status = .idle
        } catch {
            logger.error("Removing participant failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            throw error
        }
    }

    func containerIdentifier() -> CKContainer? {
        container
    }
}

private extension SharingCoordinator {
    func ensureDependencies() throws {
        guard dataStack != nil, container != nil else {
            throw ShareError.missingDependencies
        }
    }

    func dependencies() throws -> (ModelContext, CKContainer) {
        guard let context = modelContext, let container else {
            throw ShareError.missingDependencies
        }
        return (context, container)
    }

    func configureShareMetadata(_ share: CKShare, for profile: Profile) {
        let trimmed = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmed?.isEmpty == false ? trimmed : nil)
            ?? L10n.Profile.newProfile
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
    }

    func resolveShareID(for profile: Profile, context: ModelContext) async throws -> CKShare.ID? {
        if let shareID = profile.shareRecordID {
            return shareID
        }
        return nil
    }

    func fetchShare(with id: CKShare.ID, container: CKContainer) async throws -> CKShare {
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [id])
            operation.desiredKeys = nil
            var fetchedShare: CKShare?
            operation.perRecordResultBlock = { _, result in
                switch result {
                case let .success(record):
                    fetchedShare = record as? CKShare
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let share = fetchedShare {
                        continuation.resume(returning: share)
                    } else {
                        continuation.resume(throwing: ShareError.missingShare)
                    }
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    func saveShare(_ share: CKShare, container: CKContainer) async throws {
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [share])
            operation.savePolicy = .changedKeys
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    func deleteShare(with id: CKShare.ID, container: CKContainer) async throws {
        guard #available(iOS 17.4, *) else {
            throw ShareError.unsupportedOS
        }
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordIDsToDelete: [id])
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }
}

private enum ShareError: LocalizedError {
    case missingDependencies
    case missingShare
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .missingDependencies:
            return "Missing share dependencies."
        case .missingShare:
            return L10n.ShareData.Error.missingShareableProfile
        case .unsupportedOS:
            return L10n.ShareData.CloudKit.unsupportedVersion
        }
    }
}
