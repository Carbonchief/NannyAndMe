import CloudKit
import UIKit
import os

@MainActor
final class PushHandling {
    private weak var syncCoordinator: SyncCoordinator?
    private let cloudKitManager: CloudKitManager
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "push")

    init(syncCoordinator: SyncCoordinator?, cloudKitManager: CloudKitManager) {
        self.syncCoordinator = syncCoordinator
        self.cloudKitManager = cloudKitManager
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            await cloudKitManager.handleNotification(ckNotification)
        }
        syncCoordinator?.handleRemoteNotification()
        logger.debug("Handled remote notification")
    }
}
