import CloudKit
import Foundation
import os

/// Ingestor responsible for applying shared record changes into the local store.
protocol SharedRecordIngesting: AnyObject {
    func ingest(records: [CKRecord], deletedRecordIDs: [CKRecord.ID], in zoneID: CKRecordZone.ID) async
}

/// Coordinates subscriptions and push handling for the shared CloudKit scope.
final class SharedScopeSubscriptionManager {
    enum SubscriptionError: Error {
        case missingSubscriptionID
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let subscriptionStore: SharedSubscriptionStateStore
    private let tokenStore: SharedZoneChangeTokenStore
    private let shareMetadataStore: ShareMetadataStore
    private weak var ingestor: (any SharedRecordIngesting)?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share")
    private var pendingTask: Task<Void, Never>?

    init(containerIdentifier: String = "iCloud.com.prioritybit.babynanny",
         subscriptionStore: SharedSubscriptionStateStore = SharedSubscriptionStateStore(),
         tokenStore: SharedZoneChangeTokenStore = SharedZoneChangeTokenStore(),
         shareMetadataStore: ShareMetadataStore = ShareMetadataStore(),
         ingestor: (any SharedRecordIngesting)?) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.sharedCloudDatabase
        self.subscriptionStore = subscriptionStore
        self.tokenStore = tokenStore
        self.shareMetadataStore = shareMetadataStore
        self.ingestor = ingestor
    }

    func ensureSubscriptions() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.createSubscriptionsIfNeeded()
        }
    }

    @discardableResult
    func handleRemoteNotification(_ notification: CKNotification) async -> Bool {
        guard let subscriptionID = notification.subscriptionID else { return false }
        let profileID = await subscriptionStore.profileSubscriptionID
        let actionID = await subscriptionStore.actionSubscriptionID
        guard subscriptionID == profileID || subscriptionID == actionID else { return false }

        pendingTask?.cancel()
        pendingTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.processNotification(notification)
            } catch {
                self.logger.error("Failed to process shared notification: \(error.localizedDescription, privacy: .public)")
            }
        }

        return true
    }

    private func createSubscriptionsIfNeeded() async {
        let desiredProfileID = await subscriptionStore.profileSubscriptionID
        let desiredActionID = await subscriptionStore.actionSubscriptionID

        do {
            let existing = try await fetchAllSubscriptions()
            let existingIDs = Set(existing.map { $0.subscriptionID })
            var subscriptionsToSave: [CKSubscription] = []

            if let desiredProfileID {
                if !existingIDs.contains(desiredProfileID) {
                    subscriptionsToSave.append(Self.makeQuerySubscription(recordType: RecordType.profile.rawValue,
                                                                           subscriptionID: desiredProfileID))
                }
            } else {
                let newID = UUID().uuidString
                subscriptionsToSave.append(Self.makeQuerySubscription(recordType: RecordType.profile.rawValue,
                                                                       subscriptionID: newID))
                await subscriptionStore.updateProfileSubscriptionID(newID)
            }

            if let desiredActionID {
                if !existingIDs.contains(desiredActionID) {
                    subscriptionsToSave.append(Self.makeQuerySubscription(recordType: RecordType.babyAction.rawValue,
                                                                           subscriptionID: desiredActionID))
                }
            } else {
                let newID = UUID().uuidString
                subscriptionsToSave.append(Self.makeQuerySubscription(recordType: RecordType.babyAction.rawValue,
                                                                       subscriptionID: newID))
                await subscriptionStore.updateActionSubscriptionID(newID)
            }

            guard !subscriptionsToSave.isEmpty else { return }

            try await modifySubscriptions(saving: subscriptionsToSave, deleting: [])
            logger.log("Ensured shared scope subscriptions")
        } catch {
            logger.error("Failed to ensure shared subscriptions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processNotification(_ notification: CKNotification) async throws {
        guard let subscriptionID = notification.subscriptionID else { return }
        let profileID = await subscriptionStore.profileSubscriptionID
        let actionID = await subscriptionStore.actionSubscriptionID
        guard subscriptionID == profileID || subscriptionID == actionID else { return }

        let metadata = await shareMetadataStore.allMetadata()
        let zones = Array(Set(metadata.values.map { $0.zoneID }))
        guard zones.isEmpty == false else { return }

        try Task.checkCancellation()
        try await fetchChanges(for: zones)
    }

    private func fetchChanges(for zoneIDs: [CKRecordZone.ID]) async throws {
        let ingestor = self.ingestor
        guard let ingestor else { return }

        for zoneID in zoneIDs {
            try Task.checkCancellation()
            let previousToken = await tokenStore.token(for: zoneID)
            let result = try await fetchZoneChanges(zoneID: zoneID, previousToken: previousToken)
            await tokenStore.store(token: result.newToken, for: zoneID)
            guard !result.records.isEmpty || !result.deleted.isEmpty else { continue }
            await ingestor.ingest(records: result.records, deletedRecordIDs: result.deleted, in: zoneID)
        }
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
                    logger.error("Failed to fetch shared-zone record \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
                    continuation.resume(returning: ZoneFetchResult(records: changedRecords,
                                                                  deleted: deletedRecords,
                                                                  newToken: newToken))
                case .failure(let error):
                    hasFinished = true
                    continuation.resume(throwing: error)
                }
            }
            self.database.add(operation)
        }
    }
}

private extension SharedScopeSubscriptionManager {
    enum RecordType: String {
        case profile = "Profile"
        case babyAction = "BabyAction"
    }

    struct ZoneFetchResult {
        let records: [CKRecord]
        let deleted: [CKRecord.ID]
        let newToken: CKServerChangeToken?
    }

    static func makeQuerySubscription(recordType: String, subscriptionID: String) -> CKSubscription {
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(recordType: recordType,
                                               predicate: predicate,
                                               subscriptionID: subscriptionID,
                                               options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion])
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        return subscription
    }

    func fetchAllSubscriptions() async throws -> [CKSubscription] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKSubscription], Error>) in
            database.fetchAllSubscriptions { subscriptions, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: subscriptions ?? [])
                }
            }
        }
    }

    func modifySubscriptions(saving: [CKSubscription], deleting: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: saving, subscriptionIDsToDelete: deleting)
            operation.modifySubscriptionsResultBlock = { result in
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

// MARK: - Subscription state persistence

actor SharedSubscriptionStateStore {
    private struct State: Codable {
        var profileSubscriptionID: String?
        var actionSubscriptionID: String?
    }

    private let defaults: UserDefaults
    private let key = "com.prioritybit.babynanny.shared.subscriptionState"
    private var state: State

    init(suiteName: String? = nil) {
        let resolvedDefaults: UserDefaults
        if let suiteName,
           let suiteDefaults = UserDefaults(suiteName: suiteName) {
            resolvedDefaults = suiteDefaults
        } else {
            resolvedDefaults = .standard
        }

        self.defaults = resolvedDefaults
        if let data = resolvedDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    var profileSubscriptionID: String? { state.profileSubscriptionID }
    var actionSubscriptionID: String? { state.actionSubscriptionID }

    func updateProfileSubscriptionID(_ identifier: String) {
        state.profileSubscriptionID = identifier
        persist()
    }

    func updateActionSubscriptionID(_ identifier: String) {
        state.actionSubscriptionID = identifier
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

actor SharedZoneChangeTokenStore {
    private struct PersistedToken: Codable {
        var zoneName: String
        var ownerName: String
        var tokenData: Data
    }

    private let defaults: UserDefaults
    private let key = "com.prioritybit.babynanny.shared.zoneTokens"
    private var tokens: [CKRecordZone.ID: CKServerChangeToken]

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PersistedToken].self, from: data) {
            tokens = decoded.reduce(into: [:]) { partialResult, item in
                if let token = SharedZoneChangeTokenStore.decodeToken(from: item.tokenData) {
                    let zoneID = CKRecordZone.ID(zoneName: item.zoneName, ownerName: item.ownerName)
                    partialResult[zoneID] = token
                }
            }
        } else {
            tokens = [:]
        }
    }

    func token(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        tokens[zoneID]
    }

    func store(token: CKServerChangeToken?, for zoneID: CKRecordZone.ID) {
        guard let token else {
            tokens.removeValue(forKey: zoneID)
            persist()
            return
        }
        tokens[zoneID] = token
        persist()
    }

    private func persist() {
        let payload = tokens.map { zoneID, token in
            PersistedToken(zoneName: zoneID.zoneName,
                           ownerName: zoneID.ownerName,
                           tokenData: SharedZoneChangeTokenStore.encodeToken(token) ?? Data())
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
    }

    private static func encodeToken(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeToken(from data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}

