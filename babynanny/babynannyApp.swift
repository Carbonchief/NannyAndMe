//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import os

@MainActor
@main
struct babynannyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()
    @StateObject private var appDataStack: AppDataStack
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore
    @StateObject private var syncCoordinator: SyncCoordinator
    @StateObject private var sharingCoordinator: SharingCoordinator
    @State private var isShowingSplashScreen = true

    init() {

        let stack = AppDataStack()
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(modelContext: stack.mainContext,
                                        dataStack: stack,
                                        reminderScheduler: scheduler)
        let actionStore = ActionLogStore(modelContext: stack.mainContext,
                                         reminderScheduler: scheduler,
                                         dataStack: stack)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        let syncCoordinator = SyncCoordinator(dataStack: stack)
        let bridge = SwiftDataBridge(dataStack: stack)
        let cloudKitManager = CloudKitManager(bridge: bridge)
        let sharingCoordinator = SharingCoordinator(cloudKitManager: cloudKitManager, dataStack: stack)
        let pushHandling = PushHandling(syncCoordinator: syncCoordinator, cloudKitManager: cloudKitManager)
        profileStore.registerSharingCoordinator(sharingCoordinator)
        actionStore.registerSharingCoordinator(sharingCoordinator)

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
        _syncCoordinator = StateObject(wrappedValue: syncCoordinator)
        _sharingCoordinator = StateObject(wrappedValue: sharingCoordinator)
        appDelegate.syncCoordinator = syncCoordinator
        appDelegate.cloudKitManager = cloudKitManager
        appDelegate.sharingCoordinator = sharingCoordinator
        appDelegate.pushHandling = pushHandling
        syncCoordinator.requestSyncIfNeeded(reason: .launch)
        Task { await cloudKitManager.ensureSubscriptions() }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appDataStack)
                    .environmentObject(profileStore)
                    .environmentObject(actionStore)
                    .environmentObject(sharingCoordinator)
                    .environmentObject(shareDataCoordinator)
                    .environmentObject(LocationManager.shared)
                    .environmentObject(syncCoordinator)
                    .onOpenURL { url in
                        if handleDurationActivityURL(url) {
                            return
                        }
                        guard shouldHandle(url: url) else { return }
                        shareDataCoordinator.handleIncomingFile(url: url)
                    }

                if isShowingSplashScreen {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isShowingSplashScreen = false
                    }
                }
            }
            .modelContainer(appDataStack.modelContainer)
        }
    }
}

private extension babynannyApp {
    func shouldHandle(url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .json)
        }
        return url.pathExtension.lowercased() == "json"
    }

    func handleDurationActivityURL(_ url: URL) -> Bool {
        guard url.scheme == "nannyme", url.host == "activity" else { return false }

        let pathComponents = url.pathComponents.dropFirst()
        guard let identifierComponent = pathComponents.first,
              let actionID = UUID(uuidString: identifierComponent) else { return false }

        if pathComponents.dropFirst().first == "stop" {
            actionStore.stopAction(withID: actionID)
            return true
        }

        return false
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    var syncCoordinator: SyncCoordinator?
    var cloudKitManager: CloudKitManager?
    var sharingCoordinator: SharingCoordinator?
    var pushHandling: PushHandling?
    let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "appdelegate")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        pushHandling?.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.debug("Remote notification registration succeeded")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("Remote notification registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor [weak self] in
            await self?.pushHandling?.handleRemoteNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }
}
