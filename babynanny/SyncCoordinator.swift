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
    private let subscriptionIdentifier = "com.prioritybit.babynanny.database-changes"
    private let container = CKContainer(identifier: "iCloud.com.prioritybit.babynanny")

    init(dataStack: AppDataStack, notificationCenter: NotificationCenter = .default) {
        self.dataStack = dataStack
        self.notificationCenter = notificationCenter
        observeApplicationLifecycle()
        Task { @MainActor [weak self] in
            await self?.registerCloudKitSubscription()
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

    func handleRemoteNotification() {
        requestSyncIfNeeded(reason: .remoteNotification)
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

    private func registerCloudKitSubscription() async {
        do {
            let database = container.privateCloudDatabase
            let subscription = CKDatabaseSubscription(subscriptionID: subscriptionIdentifier)
            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            _ = try await database.save(subscription)
            logger.debug("Registered CloudKit database subscription")
        } catch {
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                logger.debug("CloudKit subscription already exists")
            } else {
                logger.error("Failed to register CloudKit subscription: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
