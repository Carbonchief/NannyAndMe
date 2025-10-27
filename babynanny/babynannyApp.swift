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

@main
struct babynannyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var shareDataCoordinator: ShareDataCoordinator
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
        let shareCoordinator = ShareDataCoordinator(modelContext: stack.mainContext)

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
        _syncCoordinator = StateObject(wrappedValue: syncCoordinator)
        _shareDataCoordinator = StateObject(wrappedValue: shareCoordinator)
        appDelegate.configure(
            dataStack: stack,
            profileStore: profileStore,
            actionStore: actionStore,
            shareDataCoordinator: shareCoordinator,
            syncCoordinator: syncCoordinator
        )
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    var syncCoordinator: SyncCoordinator?
    private var dataStack: AppDataStack?
    private weak var profileStore: ProfileStore?
    private weak var actionStore: ActionLogStore?
    private weak var shareDataCoordinator: ShareDataCoordinator?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "appdelegate")

    func configure(dataStack: AppDataStack,
                   profileStore: ProfileStore,
                   actionStore: ActionLogStore,
                   shareDataCoordinator: ShareDataCoordinator,
                   syncCoordinator: SyncCoordinator) {
        self.dataStack = dataStack
        self.profileStore = profileStore
        self.actionStore = actionStore
        self.shareDataCoordinator = shareDataCoordinator
        self.syncCoordinator = syncCoordinator
    }

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
            self?.syncCoordinator?.handleRemoteNotification()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await self.acceptShare(metadata)
                await self.actionStore?.performUserInitiatedRefresh()
                self.profileStore?.reloadFromPersistentStore()
                self.shareDataCoordinator?.refreshActiveShareState()
            } catch {
                self.logger.error("Failed to accept share: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension AppDelegate {
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        let _: Void = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            var perShareError: Error?

            operation.perShareResultBlock = { _, result in
                if case let .failure(error) = result {
                    perShareError = error
                }
            }

            operation.acceptSharesResultBlock = { error in
                if let error = error ?? perShareError {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }

            let container = CKContainer(identifier: metadata.containerIdentifier)
            container.add(operation)
        }
    }
}
