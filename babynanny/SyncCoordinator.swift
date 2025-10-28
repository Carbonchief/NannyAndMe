import CloudKit
import Foundation
import os
import SwiftData
import UIKit
@preconcurrency import ObjectiveC

@MainActor
final class SyncCoordinator: ObservableObject {
    enum SyncReason: String, Sendable {
        case launch
        case foreground
        case remoteNotification
    }

    static let mergeDidCompleteNotification = Notification.Name("SyncCoordinatorMergeDidCompleteNotification")

    private let dataStack: AppDataStack
    private let notificationCenter: NotificationCenter
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "sync")
    private var observers: [NSObjectProtocol] = []
    private var syncTask: Task<Void, Never>?
    private let privateSubscriptionIdentifier = "com.prioritybit.babynanny.database-changes"
    private let sharedSubscriptionIdentifier = "com.prioritybit.babynanny.shared-database-changes"
    private let container = CKContainer(identifier: "iCloud.com.prioritybit.babynanny")

    init(dataStack: AppDataStack, notificationCenter: NotificationCenter = .default) {
        self.dataStack = dataStack
        self.notificationCenter = notificationCenter
        observeApplicationLifecycle()
        Task { @MainActor [weak self] in
            await self?.registerCloudKitSubscriptions()
        }
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    func requestSyncIfNeeded(reason: SyncReason) {
        guard syncTask == nil else {
            logger.debug("Ignoring sync request for \(reason.rawValue, privacy: .public); sync already in-flight")
            return
        }

        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.syncTask = nil }

            await self.dataStack.flushPendingSaves()
            // The SwiftData runtime currently performs CloudKit imports automatically when a push arrives,
            // so we limit ourselves to ensuring local saves are committed before notifying the stores.
            self.notificationCenter.post(name: Self.mergeDidCompleteNotification, object: reason)
            self.logger.debug("Completed sync bookkeeping for \(reason.rawValue, privacy: .public)")
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let scopeDescription: String
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if let databaseNotification = notification as? CKDatabaseNotification {
                switch databaseNotification.databaseScope {
                case .private:
                    scopeDescription = "private"
                case .shared:
                    scopeDescription = "shared"
                case .public:
                    scopeDescription = "public"
                @unknown default:
                    scopeDescription = "unknown"
                }
            } else {
                scopeDescription = "unknown"
            }
        } else {
            scopeDescription = "unknown"
        }

        logger.debug("Received CloudKit push for \(scopeDescription, privacy: .public) database")
        requestSyncIfNeeded(reason: .remoteNotification)
    }

    func refreshCloudKitSubscriptions() {
        Task { @MainActor [weak self] in
            await self?.registerCloudKitSubscriptions()
        }
    }

    private func observeApplicationLifecycle() {
        let foregroundToken = notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                             object: nil,
                                                             queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestSyncIfNeeded(reason: .foreground)
            }
        }
        observers.append(foregroundToken)
    }

    private func registerCloudKitSubscriptions() async {
        await registerSubscription(database: container.privateCloudDatabase,
                                   identifier: privateSubscriptionIdentifier,
                                   scopeDescription: "private")

        await registerSubscription(database: container.sharedCloudDatabase,
                                   identifier: sharedSubscriptionIdentifier,
                                   scopeDescription: "shared")
    }

    private func registerSubscription(database: CKDatabase,
                                      identifier: String,
                                      scopeDescription: String) async {
        do {
            let subscription = CKDatabaseSubscription(subscriptionID: identifier)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            _ = try await database.save(subscription)
            logger.debug("Registered CloudKit subscription for \(scopeDescription, privacy: .public) database")
        } catch {
            if let ckError = error as? CKError {
                switch ckError.code {
                case .serverRejectedRequest:
                    logger.debug("CloudKit subscription already exists for \(scopeDescription, privacy: .public) database")
                    return
                case .zoneNotFound where scopeDescription == "shared":
                    logger.debug("Shared database subscription pending share acceptance")
                    return
                default:
                    break
                }
            }
            logger.error("Failed to register CloudKit subscription for \(scopeDescription, privacy: .public) database: \(error.localizedDescription, privacy: .public)")
        }
    }
}
