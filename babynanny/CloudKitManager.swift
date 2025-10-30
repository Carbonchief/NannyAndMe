import CloudKit
import Foundation
import os

private struct SendableUserDefaultsBox: @unchecked Sendable {
    let value: UserDefaults
}

/// Centralizes CloudKit zone management, sharing, and incremental syncing.
@MainActor
final class CloudKitManager {
    let container: CKContainer
    let privateCloudDatabase: CKDatabase
    let sharedCloudDatabase: CKDatabase

    private let bridge: SwiftDataBridge
    private let tokenStore: CloudKitTokenStore
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "cloudkit")

    init(containerIdentifier: String = "iCloud.com.prioritybit.nannyandme",
         bridge: SwiftDataBridge,
         userDefaults: UserDefaults = .standard) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.privateCloudDatabase = container.privateCloudDatabase
        self.sharedCloudDatabase = container.sharedCloudDatabase
        self.bridge = bridge
        let userDefaultsBox = SendableUserDefaultsBox(value: userDefaults)
        self.tokenStore = CloudKitTokenStore(userDefaultsBox: userDefaultsBox)
    }

    // MARK: - Zones

    func ensureZone(for profile: Profile) async throws -> CKRecordZone.ID {
        let zoneID = CloudKitSchema.zoneID(for: profile.resolvedProfileID)
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
        } catch {
            logger.error("Failed to ensure zone for profile \(profile.resolvedProfileID.uuidString): \(error.localizedDescription)")
            throw error
        }
        return zoneID
    }

    func deleteZone(for profileID: UUID) async throws {
        let zoneID = CloudKitSchema.zoneID(for: profileID)
        do {
            try await privateCloudDatabase.deleteRecordZone(withID: zoneID)
            await tokenStore.removeZoneToken(for: zoneID)
        } catch {
            if let ckError = error as? CKError, ckError.code == .zoneNotFound {
                logger.debug("Zone already removed for profile \(profileID.uuidString, privacy: .public)")
            } else {
                throw error
            }
        }
    }

    // MARK: - CRUD

    func saveProfile(_ profile: Profile,
                     scope: CKDatabase.Scope = .private,
                     zoneID providedZoneID: CKRecordZone.ID? = nil) async throws {
        let zoneID: CKRecordZone.ID
        if let providedZoneID {
            zoneID = providedZoneID
        } else {
            zoneID = CloudKitSchema.zoneID(for: profile.resolvedProfileID)
        }
        let database = database(for: scope)
        if scope == .private {
            _ = try await ensureZone(for: profile)
        }

        let record = await MainActor.run { bridge.makeProfileRecord(from: profile, in: zoneID) }
        _ = try await database.modifyRecords(saving: [record], deleting: [])
    }

    func saveActions(_ actions: [BabyAction],
                     for profile: Profile,
                     scope: CKDatabase.Scope = .private,
                     zoneID providedZoneID: CKRecordZone.ID? = nil) async throws {
        guard actions.isEmpty == false else { return }
        let zoneID: CKRecordZone.ID
        if let providedZoneID {
            zoneID = providedZoneID
        } else {
            zoneID = CloudKitSchema.zoneID(for: profile.resolvedProfileID)
        }
        let profileRecordID = CloudKitSchema.profileRecordID(for: profile.resolvedProfileID, zoneID: zoneID)
        let records = await MainActor.run {
            actions.map { action in
                bridge.makeActionRecord(from: action, zoneID: zoneID, profileRecordID: profileRecordID)
            }
        }
        let database = database(for: scope)
        _ = try await database.modifyRecords(saving: records, deleting: [])
    }

    func deleteRecords(_ recordIDs: [CKRecord.ID], scope: CKDatabase.Scope = .private) async throws {
        guard recordIDs.isEmpty == false else { return }
        let database = database(for: scope)
        _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
    }

    // MARK: - Subscriptions

    func ensureSubscriptions() async {
        await ensureSubscription(scope: .private, identifier: "com.prioritybit.nannyandme.private-changes")
        await ensureSubscription(scope: .shared, identifier: "com.prioritybit.nannyandme.shared-changes")
    }

    private func ensureSubscription(scope: CKDatabase.Scope, identifier: String) async {
        let database = database(for: scope)
        do {
            let subscription = CKDatabaseSubscription(subscriptionID: identifier)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            _ = try await database.save(subscription)
            logger.debug("Registered subscription for scope \(scope.rawValue, privacy: .public)")
        } catch {
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                logger.debug("Subscription already exists for \(identifier, privacy: .public)")
            } else {
                logger.error("Failed to register subscription for \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Notifications

    func handleNotification(_ notification: CKNotification) async {
        guard let databaseNotification = notification as? CKDatabaseNotification else { return }
        await fetchChanges(database: databaseNotification.databaseScope)
    }

    // MARK: - Fetching

    func fetchChanges(database scope: CKDatabase.Scope, since token: CKServerChangeToken? = nil) async {
        let database = database(for: scope)
        var changedZoneIDs: Set<CKRecordZone.ID> = []
        var deletedZoneIDs: [CKRecordZone.ID] = []

        var previousToken: CKServerChangeToken?
        if let token {
            previousToken = token
        } else {
            previousToken = await tokenStore.databaseToken(for: scope)
        }
        var moreComing = true

        while moreComing {
            do {
                let result = try await fetchDatabaseChanges(database: database,
                                                             scope: scope,
                                                             previousToken: previousToken)
                changedZoneIDs.formUnion(result.changedZoneIDs)
                deletedZoneIDs.append(contentsOf: result.deletedZoneIDs)
                previousToken = result.newToken
                moreComing = result.moreComing
            } catch {
                logger.error("Database changes fetch failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        for zoneID in deletedZoneIDs {
            await tokenStore.removeZoneToken(for: zoneID)
            if let profileID = CloudKitSchema.profileID(from: zoneID) {
                await MainActor.run { bridge.deleteProfile(withID: profileID) }
            }
        }

        for zoneID in changedZoneIDs {
            await fetchZoneChanges(zoneID: zoneID, scope: scope)
        }
    }

    private func fetchZoneChanges(zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) async {
        let database = database(for: scope)
        var moreComing = true
        var accumulatedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var previousToken: CKServerChangeToken? = await tokenStore.zoneToken(for: zoneID)

        while moreComing {
            do {
                let result = try await fetchZoneChanges(database: database,
                                                        zoneID: zoneID,
                                                        previousToken: previousToken)
                accumulatedRecords.append(contentsOf: result.records)
                deletedRecordIDs.append(contentsOf: result.deletedRecordIDs)
                previousToken = result.newToken
                moreComing = result.moreComing
                if let token = result.newToken {
                    await tokenStore.setZoneToken(token, for: zoneID)
                }
            } catch {
                logger.error("Zone changes fetch failed for \(zoneID.zoneName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        if accumulatedRecords.isEmpty == false {
            await MainActor.run {
                bridge.apply(records: accumulatedRecords, scope: scope)
            }
        }

        if deletedRecordIDs.isEmpty == false {
            await MainActor.run {
                bridge.delete(recordIDs: deletedRecordIDs)
            }
        }
    }

    private func fetchDatabaseChanges(database: CKDatabase,
                                      scope: CKDatabase.Scope,
                                      previousToken: CKServerChangeToken?) async throws -> DatabaseChangeResult {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DatabaseChangeResult, Error>) in
            let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: previousToken)
            var changedZoneIDs: [CKRecordZone.ID] = []
            var deletedZoneIDs: [CKRecordZone.ID] = []

            operation.recordZoneWithIDChangedBlock = { [weak self] zoneID in
                Task { @MainActor in
                    guard self != nil else { return }
                    changedZoneIDs.append(zoneID)
                }
            }

            operation.recordZoneWithIDWasDeletedBlock = { [weak self] zoneID in
                Task { @MainActor in
                    guard self != nil else { return }
                    deletedZoneIDs.append(zoneID)
                }
            }

            operation.changeTokenUpdatedBlock = { [weak self] token in
                Task { @MainActor in
                    guard let self else { return }
                    await self.tokenStore.setDatabaseToken(token, scope: scope)
                }
            }

            operation.fetchDatabaseChangesResultBlock = { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    switch result {
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .success(let context):
                        await self.tokenStore.setDatabaseToken(context.serverChangeToken, scope: scope)
                        let databaseResult = DatabaseChangeResult(changedZoneIDs: changedZoneIDs,
                                                                  deletedZoneIDs: deletedZoneIDs,
                                                                  newToken: context.serverChangeToken,
                                                                  moreComing: context.moreComing)
                        continuation.resume(returning: databaseResult)
                    }
                }
            }

            operation.qualityOfService = .userInitiated
            database.add(operation)
        }
    }

    private func fetchZoneChanges(database: CKDatabase,
                                  zoneID: CKRecordZone.ID,
                                  previousToken: CKServerChangeToken?) async throws -> ZoneChangeResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ZoneChangeResult, Error>) in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: previousToken)
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
            var changedRecords: [CKRecord] = []
            var deletedRecordIDs: [CKRecord.ID] = []
            var capturedToken: CKServerChangeToken?
            var capturedMoreComing = false
            var capturedError: Error?

            operation.recordWasChangedBlock = { [weak self, logger] recordID, result in
                Task { @MainActor in
                    guard self != nil else { return }
                    switch result {
                    case .success(let record):
                        changedRecords.append(record)
                    case .failure(let error):
                        logger.error("Failed to fetch changed record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            operation.recordWithIDWasDeletedBlock = { [weak self] recordID, _ in
                Task { @MainActor in
                    guard self != nil else { return }
                    deletedRecordIDs.append(recordID)
                }
            }

            operation.recordZoneFetchResultBlock = { [weak self] _, result in
                Task { @MainActor in
                    guard self != nil else { return }
                    switch result {
                    case .failure(let error):
                        capturedError = error
                    case .success(let context):
                        capturedToken = context.serverChangeToken
                        capturedMoreComing = context.moreComing
                    }
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { [weak self] result in
                Task { @MainActor in
                    guard self != nil else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    switch result {
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .success:
                        if let capturedError {
                            continuation.resume(throwing: capturedError)
                            return
                        }

                        let zoneResult = ZoneChangeResult(records: changedRecords,
                                                           deletedRecordIDs: deletedRecordIDs,
                                                           newToken: capturedToken,
                                                           moreComing: capturedMoreComing)
                        continuation.resume(returning: zoneResult)
                    }
                }
            }

            operation.qualityOfService = .userInitiated
            database.add(operation)
        }
    }

    // MARK: - Sharing

    func createShare(for profile: Profile) async throws -> (root: CKRecord, share: CKShare) {
        let zoneID = try await ensureZone(for: profile)
        let profileRecordID = CloudKitSchema.profileRecordID(for: profile.resolvedProfileID, zoneID: zoneID)

        var rootRecord: CKRecord
        do {
            rootRecord = try await privateCloudDatabase.record(for: profileRecordID)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                rootRecord = await MainActor.run {
                    bridge.makeProfileRecord(from: profile, in: zoneID)
                }
            } else {
                throw error
            }
        }

        if let existingShareReference = rootRecord.share {
            do {
                let shareRecord = try await privateCloudDatabase.record(for: existingShareReference.recordID)
                if let share = shareRecord as? CKShare {
                    return (rootRecord, share)
                }
            } catch {
                logger.error("Failed to fetch existing share: \(error.localizedDescription, privacy: .public)")
            }
        }

        let share = CKShare(rootRecord: rootRecord)
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = profile.name as CKRecordValue?
        share[CKShare.SystemFieldKey.shareType] = "com.prioritybit.nannyandme.profile" as CKRecordValue

        let actions = profile.actions
        let actionRecords = await MainActor.run {
            actions.map { action in
                bridge.makeActionRecord(from: action, zoneID: zoneID, profileRecordID: profileRecordID)
            }
        }

        let modificationResult = try await privateCloudDatabase.modifyRecords(saving: [rootRecord, share] + actionRecords,
                                                                              deleting: [])
        let savedRoot: CKRecord
        if case let .success(record)? = modificationResult.saveResults[rootRecord.recordID] {
            savedRoot = record
        } else {
            savedRoot = rootRecord
        }

        guard case let .success(shareRecord)? = modificationResult.saveResults[share.recordID],
              let savedShare = shareRecord as? CKShare else {
            throw CKError(.internalError, userInfo: [NSLocalizedDescriptionKey: "Share did not persist"])
        }
        return (savedRoot, savedShare)
    }

    func updateShare(_ share: CKShare, participants: [CKShare.Participant]) async throws -> CKShare {
        for existing in share.participants where existing != share.owner {
            share.removeParticipant(existing)
        }
        for participant in participants {
            share.addParticipant(participant)
        }
        share.publicPermission = .none
        let modificationResult = try await privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard case let .success(shareRecord)? = modificationResult.saveResults[share.recordID],
              let updatedShare = shareRecord as? CKShare else {
            throw CKError(.internalError, userInfo: [NSLocalizedDescriptionKey: "Failed to update share participants"])
        }
        return updatedShare
    }

    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            let gate = ContinuationGate()

            operation.perShareResultBlock = { _, result in
                guard case let .failure(error) = result else { return }
                Task { await gate.resume(.failure(error), continuation: continuation) }
            }

            operation.acceptSharesResultBlock = { result in
                Task {
                    switch result {
                    case .failure(let error):
                        await gate.resume(.failure(error), continuation: continuation)
                    case .success:
                        await gate.resume(.success(()), continuation: continuation)
                    }
                }
            }

            operation.qualityOfService = .userInitiated
            container.add(operation)
        }

        let zoneID: CKRecordZone.ID
        if let rootRecord = metadata.rootRecord {
            zoneID = rootRecord.recordID.zoneID
        } else {
            zoneID = metadata.share.recordID.zoneID
        }
        await fetchZoneChanges(zoneID: zoneID, scope: .shared)
    }

    func purgeLocalProfileData(profileID: UUID) async {
        bridge.deleteProfile(withID: profileID)
    }

    func fetchAllZones(scope: CKDatabase.Scope) async throws -> [CKRecordZone] {
        let database = database(for: scope)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecordZone], Error>) in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let zones {
                    continuation.resume(returning: zones)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Helpers

    private func database(for scope: CKDatabase.Scope) -> CKDatabase {
        switch scope {
        case .private:
            return privateCloudDatabase
        case .shared:
            return sharedCloudDatabase
        case .public:
            return container.publicCloudDatabase
        @unknown default:
            return privateCloudDatabase
        }
    }
}

private actor ContinuationGate {
    private var hasResumed = false

    func resume(_ result: Result<Void, Error>, continuation: CheckedContinuation<Void, Error>) {
        guard !hasResumed else { return }
        hasResumed = true
        switch result {
        case .success:
            continuation.resume(returning: ())
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct DatabaseChangeResult {
    var changedZoneIDs: [CKRecordZone.ID]
    var deletedZoneIDs: [CKRecordZone.ID]
    var newToken: CKServerChangeToken?
    var moreComing: Bool
}

private struct ZoneChangeResult {
    var records: [CKRecord]
    var deletedRecordIDs: [CKRecord.ID]
    var newToken: CKServerChangeToken?
    var moreComing: Bool
}

private actor CloudKitTokenStore {
    private let userDefaultsBox: SendableUserDefaultsBox
    private let databaseKeyPrefix = "com.prioritybit.nannyandme.token.database."
    private let zoneKeyPrefix = "com.prioritybit.nannyandme.token.zone."

    init(userDefaultsBox: SendableUserDefaultsBox) {
        self.userDefaultsBox = userDefaultsBox
    }

    private var userDefaults: UserDefaults { userDefaultsBox.value }

    func databaseToken(for scope: CKDatabase.Scope) async -> CKServerChangeToken? {
        guard let data = userDefaults.data(forKey: databaseKey(for: scope)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func setDatabaseToken(_ token: CKServerChangeToken?, scope: CKDatabase.Scope) async {
        let key = databaseKey(for: scope)
        if let token {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                userDefaults.set(data, forKey: key)
            }
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    func zoneToken(for zoneID: CKRecordZone.ID) async -> CKServerChangeToken? {
        guard let data = userDefaults.data(forKey: zoneKey(for: zoneID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    func setZoneToken(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) async {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            userDefaults.set(data, forKey: zoneKey(for: zoneID))
        }
    }

    func removeZoneToken(for zoneID: CKRecordZone.ID) async {
        userDefaults.removeObject(forKey: zoneKey(for: zoneID))
    }

    private func databaseKey(for scope: CKDatabase.Scope) -> String {
        databaseKeyPrefix + String(scope.rawValue)
    }

    private func zoneKey(for zoneID: CKRecordZone.ID) -> String {
        zoneKeyPrefix + zoneID.zoneName
    }
}
