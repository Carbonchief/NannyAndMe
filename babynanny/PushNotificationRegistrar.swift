import Foundation
import os
import UIKit
import UserNotifications

@MainActor
final class PushNotificationRegistrar: NSObject, ObservableObject {
    private let reminderScheduler: ReminderScheduling
    private let application: UIApplication
    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "push-registrar")

    init(reminderScheduler: ReminderScheduling,
         application: UIApplication = .shared,
         center: UNUserNotificationCenter = .current()) {
        self.reminderScheduler = reminderScheduler
        self.application = application
        self.center = center
        super.init()
        center.delegate = self
    }

    func registerForRemoteNotifications() async {
        let isAuthorized = await reminderScheduler.ensureAuthorization()
        guard isAuthorized else {
            logger.info("Skipping APNs registration because notification authorization is unavailable")
            return
        }

        logger.info("Registering for remote notifications with APNs")
        application.registerForRemoteNotifications()
    }
}

extension PushNotificationRegistrar: UNUserNotificationCenterDelegate {
    nonisolated
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
