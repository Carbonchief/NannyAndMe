import CloudKit
import Foundation
import os
import SwiftData

@MainActor
final class SyncCoordinator: ObservableObject {
    enum SyncReason: String {
        case appLaunch
        case foregroundRefresh
        case remoteNotification
        case userInitiated
    }

    struct Diagnostics: Equatable {
        enum SubscriptionState: Equatable {
            case unknown
            case pending
            case active
            case failed(String)
        }

        var subscriptionState: SubscriptionState = .unknown
        var lastPushReceivedAt: Date?
        var lastSyncFinishedAt: Date?
        var lastSyncError: String?
        var pendingChangeCount: Int = 0
    }

    @Published private(set) var diagnostics = Diagnostics()

    private let sharedContext: ModelContext
    private let cloudDatabase: CKDatabase
    private let cloudContainerIdentifier: String
    private let subscriptionID = "com.prioritybit.babynanny.databaseSubscription"
    private let syncLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "sync")
    private let cloudLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "cloudkit")
    private var processedNotificationIDs: [String: Date] = [:]
    private var pendingSyncTask: Task<Void, Never>?
    private var isPerformingSync = false

    init(sharedContext: ModelContext,
         cloudContainerIdentifier: String = "iCloud.com.prioritybit.babynanny",
         database: CKDatabase? = nil) {
        self.sharedContext = sharedContext
        self.cloudContainerIdentifier = cloudContainerIdentifier
        let ckContainer = CKContainer(identifier: cloudContainerIdentifier)
        self.cloudDatabase = database ?? ckContainer.privateCloudDatabase
    }

    func prepareSubscriptionsIfNeeded() {
        Task { [weak self] in
            guard let self else { return }
            await self.ensureDatabaseSubscription()
        }
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            cloudLogger.error("Received remote notification that was not a CloudKit notification")
            return
        }

        if let subscriptionID = notification.subscriptionID, subscriptionID != self.subscriptionID {
            cloudLogger.debug("Received CloudKit notification for subscription \(subscriptionID, privacy: .public)")
        }

        if let notificationID = notification.notificationID.map({ String(describing: $0) }) {
            cleanupExpiredNotificationIDs(before: Date().addingTimeInterval(-600))
            if processedNotificationIDs[notificationID] != nil {
                cloudLogger.debug("Ignoring duplicate CloudKit notification \(notificationID, privacy: .public)")
                return
            }
            processedNotificationIDs[notificationID] = Date()
        }

        diagnostics.lastPushReceivedAt = Date()
        requestSyncIfNeeded(reason: .remoteNotification)
    }

    func requestSyncIfNeeded(reason: SyncReason) {
        syncLogger.debug("Sync requested for reason \(reason.rawValue, privacy: .public)")
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self.performSync(reason: reason)
        }
    }

    private func performSync(reason: SyncReason) async {
        guard isPerformingSync == false else {
            syncLogger.debug("Skipping sync because another sync is already running")
            return
        }

        isPerformingSync = true
        defer { isPerformingSync = false }

        do {
            try fetchLatestChangesFromStore()
            diagnostics.lastSyncFinishedAt = Date()
            diagnostics.lastSyncError = nil
            diagnostics.pendingChangeCount = sharedContext.hasChanges ? 1 : 0
            syncLogger.debug("Finished sync for reason \(reason.rawValue, privacy: .public)")
        } catch {
            diagnostics.lastSyncError = error.localizedDescription
            cloudLogger.error("Failed to merge CloudKit changes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureDatabaseSubscription() async {
        if diagnostics.subscriptionState == .active {
            return
        }

        diagnostics.subscriptionState = .pending

        do {
            let existing = try await cloudDatabase.allSubscriptions()
            if existing.contains(where: { $0.subscriptionID == subscriptionID }) {
                diagnostics.subscriptionState = .active
                cloudLogger.debug("Re-using existing CloudKit database subscription")
                return
            }
        } catch {
            cloudLogger.error("Failed to fetch CloudKit subscriptions: \(error.localizedDescription, privacy: .public)")
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await cloudDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            diagnostics.subscriptionState = .active
            cloudLogger.debug("Created CloudKit database subscription")
        } catch {
            diagnostics.subscriptionState = .failed(error.localizedDescription)
            cloudLogger.error("Failed to create CloudKit subscription: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cleanupExpiredNotificationIDs(before date: Date) {
        processedNotificationIDs = processedNotificationIDs.filter { $0.value > date }
    }

    private func fetchLatestChangesFromStore() throws {
        let profileDescriptor = FetchDescriptor<ProfileActionStateModel>()
        _ = try sharedContext.fetch(profileDescriptor)

        let actionsDescriptor = FetchDescriptor<BabyActionModel>()
        _ = try sharedContext.fetch(actionsDescriptor)
    }
}

private extension CKDatabase {
    func allSubscriptions() async throws -> [CKSubscription] {
        try await withCheckedThrowingContinuation { continuation in
            fetchAllSubscriptions { subscriptions, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: subscriptions ?? [])
            }
        }
    }
}
