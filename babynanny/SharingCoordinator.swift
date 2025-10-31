import CloudKit
import SwiftData
import SwiftUI
import UIKit
import os

/// Coordinates user-facing sharing flows and caches active share metadata.
@MainActor
final class SharingCoordinator: NSObject, ObservableObject {
    struct ShareContext: Identifiable, Equatable {
        let id: UUID
        var zoneID: CKRecordZone.ID
        var rootRecordID: CKRecord.ID
        var shareRecordID: CKRecord.ID
        var share: CKShare?
        var isOwner: Bool
        var lastKnownTitle: String?
        var lastSyncedActions: [UUID: Date]

        var participants: [CKShare.Participant] {
            share?.participants ?? []
        }

        static func makeActionMetadata(from actions: [BabyAction]) -> [UUID: Date] {
            Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.updatedAt) })
        }

        static func == (lhs: ShareContext, rhs: ShareContext) -> Bool {
            lhs.id == rhs.id &&
                lhs.zoneID == rhs.zoneID &&
                lhs.rootRecordID == rhs.rootRecordID &&
                lhs.shareRecordID == rhs.shareRecordID &&
                lhs.isOwner == rhs.isOwner &&
                lhs.lastSyncedActions == rhs.lastSyncedActions
        }
    }

    struct SharingError: Identifiable, Equatable {
        let id = UUID()
        let message: String

        static func == (lhs: SharingError, rhs: SharingError) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published private(set) var shareContexts: [UUID: ShareContext] = [:]
    @Published var activeShareController: UICloudSharingController?
    @Published var isPresentingShareSheet = false
    @Published var sharingError: SharingError?

    private let cloudKitManager: CloudKitManager
    private let dataStack: AppDataStack
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "sharing")

    private var presentationProfileID: UUID?

    init(cloudKitManager: CloudKitManager, dataStack: AppDataStack, autoLoad: Bool = true) {
        self.cloudKitManager = cloudKitManager
        self.dataStack = dataStack
        super.init()
        if autoLoad {
            loadExistingOwnedShares()
            loadExistingSharedShares()
        }
    }

    func shareContext(for profileID: UUID) -> ShareContext? {
        shareContexts[profileID]
    }

#if DEBUG
    func debugSetShareContext(_ context: ShareContext) {
        shareContexts[context.id] = context
    }

    func synchronizeActionsForTesting(profileID: UUID) async {
        await synchronizeActions(profileID: profileID)
    }
#endif

    func zoneID(for profileID: UUID) -> CKRecordZone.ID? {
        if let context = shareContexts[profileID] {
            return context.zoneID
        }
        return nil
    }

    func scheduleProfileSync(profileID: UUID) {
        guard shareContexts[profileID] != nil else { return }
        Task { await synchronizeProfile(profileID: profileID) }
    }

    func scheduleActionSync(profileID: UUID) {
        guard shareContexts[profileID] != nil else { return }
        Task { await synchronizeActions(profileID: profileID) }
    }

    func startSharing(profileID: UUID) async {
        guard let profileModel = fetchProfileModel(id: profileID) else {
            logger.error("Unable to locate profile model for sharing")
            sharingError = SharingError(message: L10n.ShareUI.errorProfileMissing)
            return
        }

        do {
            let result = try await cloudKitManager.createShare(for: profileModel)
            let share = result.share
            let controller = UICloudSharingController(share: share, container: cloudKitManager.container)
            controller.delegate = self
            presentationProfileID = profileID

            let context = ShareContext(id: profileID,
                                       zoneID: result.root.recordID.zoneID,
                                       rootRecordID: result.root.recordID,
                                       shareRecordID: share.recordID,
                                       share: share,
                                       isOwner: true,
                                       lastKnownTitle: profileModel.name,
                                       lastSyncedActions: ShareContext.makeActionMetadata(from: profileModel.actions))
            shareContexts[profileID] = context

            activeShareController = controller
            isPresentingShareSheet = true
        } catch {
            logger.error("Failed to initiate sharing: \(error.localizedDescription, privacy: .public)")
            sharingError = SharingError(message: L10n.ShareUI.errorStartSharing)
        }
    }

    func stopSharing(profileID: UUID) async {
        do {
            try await cloudKitManager.deleteZone(for: profileID)
            shareContexts.removeValue(forKey: profileID)
        } catch {
            logger.error("Failed to stop sharing: \(error.localizedDescription, privacy: .public)")
            sharingError = SharingError(message: L10n.ShareUI.errorStopSharing)
        }
    }

    func removeParticipant(_ participant: CKShare.Participant, from profileID: UUID) async {
        guard var context = shareContexts[profileID], let share = context.share else { return }
        let retained = share.participants.filter { existing in
            if existing == share.owner { return true }
            return existing != participant
        }
        do {
            let updatedShare = try await cloudKitManager.updateShare(share, participants: retained)
            context.share = updatedShare
            shareContexts[profileID] = context
        } catch {
            logger.error("Failed to remove participant: \(error.localizedDescription, privacy: .public)")
            sharingError = SharingError(message: L10n.ShareUI.errorRemoveParticipant)
        }
    }

    func leaveShare(for profileID: UUID) async {
        guard let context = shareContexts[profileID] else { return }
        do {
            _ = try await cloudKitManager.sharedCloudDatabase.deleteRecord(withID: context.shareRecordID)
            shareContexts.removeValue(forKey: profileID)
            await cloudKitManager.purgeLocalProfileData(profileID: profileID)
        } catch {
            logger.error("Failed to leave share: \(error.localizedDescription, privacy: .public)")
            sharingError = SharingError(message: L10n.ShareUI.errorLeaveShare)
        }
    }

    func registerAcceptedShare(metadata: CKShare.Metadata) {
        let shareRecord = metadata.share
        let resolvedRootRecordID: CKRecord.ID?
        if let rootRecord = metadata.rootRecord {
            resolvedRootRecordID = rootRecord.recordID
        } else if #available(iOS 16.0, *) {
            resolvedRootRecordID = nil
        } else {
            resolvedRootRecordID = metadata.rootRecordID
        }

        let zoneID: CKRecordZone.ID
        if let rootRecordID = resolvedRootRecordID {
            zoneID = rootRecordID.zoneID
        } else {
            zoneID = shareRecord.recordID.zoneID
        }

        let profileIDFromRoot = resolvedRootRecordID.flatMap { recordID in
            CloudKitSchema.profileID(from: recordID)
        }

        guard let profileID = profileIDFromRoot ?? CloudKitSchema.profileID(from: zoneID) else {
            logger.error("Received share metadata without resolvable profile ID")
            return
        }

        let rootRecordID = resolvedRootRecordID ?? CloudKitSchema.profileRecordID(for: profileID, zoneID: zoneID)
        let existingActions = fetchProfileModel(id: profileID)?.actions ?? []
        let context = ShareContext(id: profileID,
                                   zoneID: zoneID,
                                   rootRecordID: rootRecordID,
                                   shareRecordID: shareRecord.recordID,
                                   share: shareRecord,
                                   isOwner: metadata.participantRole == .owner,
                                   lastKnownTitle: shareRecord[CKShare.SystemFieldKey.title] as? String,
                                   lastSyncedActions: ShareContext.makeActionMetadata(from: existingActions))
        shareContexts[profileID] = context
    }

    private func fetchProfileModel(id: UUID) -> Profile? {
        let context = dataStack.mainContext
        let predicate = #Predicate<Profile> { $0.profileID == id }
        var descriptor = FetchDescriptor<Profile>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func synchronizeProfile(profileID: UUID) async {
        guard var context = shareContexts[profileID], let profile = fetchProfileModel(id: profileID) else { return }
        let scope: CKDatabase.Scope = context.isOwner ? .private : .shared
        do {
            try await cloudKitManager.saveProfile(profile, scope: scope, zoneID: context.zoneID)
            context.lastKnownTitle = profile.name
            shareContexts[profileID] = context
        } catch {
            logger.error("Failed to sync profile to CloudKit: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func synchronizeActions(profileID: UUID) async {
        guard var context = shareContexts[profileID], let profile = fetchProfileModel(id: profileID) else { return }
        let scope: CKDatabase.Scope = context.isOwner ? .private : .shared
        let actions = profile.actions
        let existingMetadata = context.lastSyncedActions
        let currentIDs = Set(actions.map { $0.id })
        let previouslySyncedIDs = Set(existingMetadata.keys)
        let deletedIDs = previouslySyncedIDs.subtracting(currentIDs)
        let pendingActions = actions.filter { action in
            guard let lastUploaded = existingMetadata[action.id] else { return true }
            return action.updatedAt > lastUploaded
        }

        if deletedIDs.isEmpty && pendingActions.isEmpty {
            return
        }

        do {
            if deletedIDs.isEmpty == false {
                let recordIDs = deletedIDs.map { CloudKitSchema.actionRecordID(for: $0, zoneID: context.zoneID) }
                try await cloudKitManager.deleteRecords(recordIDs, scope: scope)
            }

            if pendingActions.isEmpty == false {
                let chunkSize = 200
                var startIndex = 0
                while startIndex < pendingActions.count {
                    let endIndex = min(startIndex + chunkSize, pendingActions.count)
                    let chunk = Array(pendingActions[startIndex..<endIndex])
                    try await cloudKitManager.saveActions(chunk,
                                                          for: profile,
                                                          scope: scope,
                                                          zoneID: context.zoneID)
                    startIndex = endIndex
                }
            }

            let updatedMetadata = ShareContext.makeActionMetadata(from: actions)
            context.lastSyncedActions = updatedMetadata
            shareContexts[profileID] = context
        } catch {
            logger.error("Failed to sync actions to CloudKit: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadExistingOwnedShares() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let zones = try await cloudKitManager.fetchAllZones(scope: .private)
                for zone in zones where CloudKitSchema.isProfileZone(zone.zoneID) {
                    guard let profileID = CloudKitSchema.profileID(from: zone.zoneID) else { continue }
                    await self.loadShare(for: profileID, zoneID: zone.zoneID, scope: .private)
                }
            } catch {
                logger.error("Failed to load owned shares: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func loadExistingSharedShares() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let zones = try await cloudKitManager.fetchAllZones(scope: .shared)
                for zone in zones where CloudKitSchema.isProfileZone(zone.zoneID) {
                    guard let profileID = CloudKitSchema.profileID(from: zone.zoneID) else { continue }
                    await self.loadShare(for: profileID, zoneID: zone.zoneID, scope: .shared)
                }
            } catch {
                logger.error("Failed to load shared zones: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func loadShare(for profileID: UUID, zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) async {
        if shareContexts[profileID] != nil { return }
        do {
            let database = scope == .private ? cloudKitManager.privateCloudDatabase : cloudKitManager.sharedCloudDatabase
            let rootRecord = try await cloudKitManager.fetchProfileRecord(profileID: profileID,
                                                                          zoneID: zoneID,
                                                                          scope: scope)
            guard let shareReference = rootRecord.share else { return }
            let shareRecord = try await database.record(for: shareReference.recordID)
            guard let share = shareRecord as? CKShare else { return }
            let remoteProfileID = (rootRecord[CloudKitSchema.ProfileField.uuid] as? String).flatMap(UUID.init) ?? profileID
            let actions = fetchProfileModel(id: remoteProfileID)?.actions ?? []
            let context = ShareContext(id: remoteProfileID,
                                       zoneID: zoneID,
                                       rootRecordID: rootRecord.recordID,
                                       shareRecordID: share.recordID,
                                       share: share,
                                       isOwner: scope == .private,
                                       lastKnownTitle: share[CKShare.SystemFieldKey.title] as? String,
                                       lastSyncedActions: ShareContext.makeActionMetadata(from: actions))
            shareContexts[remoteProfileID] = context
            if remoteProfileID != profileID {
                shareContexts.removeValue(forKey: profileID)
            }
        } catch {
            logger.error("Failed to load share context for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension SharingCoordinator: UICloudSharingControllerDelegate {
    func itemTitle(for csc: UICloudSharingController) -> String? {
        guard let profileID = presentationProfileID,
              let profile = fetchProfileModel(id: profileID) else { return nil }
        return profile.name ?? L10n.ShareUI.defaultProfileName
    }

    func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
        logger.error("Share controller failed: \(error.localizedDescription, privacy: .public)")
        sharingError = SharingError(message: L10n.ShareUI.errorStartSharing)
    }

    func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
        guard let profileID = presentationProfileID else { return }
        shareContexts.removeValue(forKey: profileID)
    }

    func cloudSharingController(_ controller: UICloudSharingController, didSave share: CKShare) {
        guard let profileID = presentationProfileID else { return }
        if var context = shareContexts[profileID] {
            context.share = share
            context.lastKnownTitle = share[CKShare.SystemFieldKey.title] as? String
            shareContexts[profileID] = context
        }
    }
}
