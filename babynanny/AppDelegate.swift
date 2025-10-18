import CloudKit
import SwiftUI
import UIKit
import os

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "sync")
    private weak var syncCoordinator: SyncCoordinator?
    private var sharedSubscriptionManager: SharedScopeSubscriptionManager?

    func configure(with coordinator: SyncCoordinator?,
                   sharedSubscriptionManager: SharedScopeSubscriptionManager?) {
        syncCoordinator = coordinator
        self.sharedSubscriptionManager = sharedSubscriptionManager
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.debug("Registered for remote notifications with token size \(deviceToken.count, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let coordinator = syncCoordinator else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            var handledSharedScope = false
            if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
                if let sharedManager = self.sharedSubscriptionManager {
                    handledSharedScope = await sharedManager.handleRemoteNotification(notification)
                    if handledSharedScope {
                        NotificationCenter.default.post(name: .sharedScopeNotification, object: notification)
                    }
                }

                if handledSharedScope == false {
                    coordinator.handleRemoteNotification(userInfo)
                }
            } else {
                logger.error("Received remote notification without CloudKit payload")
                coordinator.handleRemoteNotification(userInfo)
            }

            completionHandler(.newData)
        }
    }
}
