//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import CloudKit
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

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
        _syncCoordinator = StateObject(wrappedValue: syncCoordinator)
        appDelegate.syncCoordinator = syncCoordinator
        appDelegate.dataStack = stack
        syncCoordinator.requestSyncIfNeeded(reason: .launch)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appDataStack)
                    .environmentObject(profileStore)
                    .environmentObject(actionStore)
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
    var dataStack: AppDataStack?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "appdelegate")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
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
            self?.syncCoordinator?.handleRemoteNotification(userInfo: userInfo)
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let context = self.dataStack?.mainContext else {
                self.logger.error("Unable to accept CloudKit share; data stack is unavailable")
                return
            }

            do {
                try await context.acceptShare(metadata)
                self.logger.debug("Accepted CloudKit share: \(metadata.shareRecordID.recordName, privacy: .public)")
                self.syncCoordinator?.requestSyncIfNeeded(reason: .remoteNotification)
                self.syncCoordinator?.refreshCloudKitSubscriptions()
            } catch {
                self.logger.error("Failed to accept CloudKit share: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
