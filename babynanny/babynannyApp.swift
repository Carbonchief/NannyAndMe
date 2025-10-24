//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct babynannyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var cloudStatusController = CloudAccountStatusController()
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()
    @State private var appDataStack: AppDataStack?
    @State private var profileStore: ProfileStore?
    @State private var actionStore: ActionLogStore?
    @State private var syncStatusViewModel: SyncStatusViewModel?
    @State private var isShowingSplashScreen = true
    @State private var isPresentingCloudPrompt = false

    init() {
        Analytics.setup()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let appDataStack,
                   let profileStore,
                   let actionStore,
                   let syncStatusViewModel {
                    ContentView()
                        .environmentObject(cloudStatusController)
                        .environmentObject(appDataStack)
                        .environmentObject(profileStore)
                        .environmentObject(actionStore)
                        .environmentObject(shareDataCoordinator)
                        .environmentObject(appDataStack.syncCoordinator)
                        .environmentObject(syncStatusViewModel)
                        .environmentObject(LocationManager.shared)
                        .onOpenURL { url in
                            if handleDurationActivityURL(url) {
                                return
                            }
                            guard shouldHandle(url: url) else { return }
                            shareDataCoordinator.handleIncomingFile(url: url)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            appDataStack.requestSyncIfNeeded(reason: .foregroundRefresh)
                            cloudStatusController.refreshAccountStatus()
                        }
                        .sheet(isPresented: $isPresentingCloudPrompt) {
                            CloudSyncPromptView()
                                .environmentObject(cloudStatusController)
                                .environmentObject(appDataStack)
                        }
                } else {
                    SplashScreenView()
                }

                if isShowingSplashScreen {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task(id: cloudStatusController.status) {
                await handleCloudStatusChange(cloudStatusController.status)
            }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isShowingSplashScreen = false
                    }
                }
            }
            .modelContainer(appDataStack?.modelContainer ?? AppDataStack.makeModelContainer())
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
            actionStore?.stopAction(withID: actionID)
            return true
        }

        return false
    }

    func updateDependencies(cloudSyncEnabled: Bool) {
        if let appDataStack {
            appDataStack.setCloudSyncEnabled(cloudSyncEnabled)
            profileStore?.updateCloudImporter(cloudSyncEnabled ? CloudKitProfileImporter() : nil)
            actionStore?.refreshSyncObservation()
            if cloudSyncEnabled {
                appDataStack.prepareSubscriptionsIfNeeded()
                appDataStack.requestSyncIfNeeded(reason: .appLaunch)
            }
            configureAppDelegate(with: appDataStack)
            isPresentingCloudPrompt = cloudStatusController.status == .needsAccount
            return
        }

        let stack = AppDataStack(cloudSyncEnabled: cloudSyncEnabled)
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler,
                                        cloudImporter: cloudSyncEnabled ? CloudKitProfileImporter() : nil)
        let actionStore = ActionLogStore(modelContext: stack.mainContext,
                                         reminderScheduler: scheduler,
                                         dataStack: stack)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        stack.prepareSubscriptionsIfNeeded()
        if cloudSyncEnabled {
            stack.requestSyncIfNeeded(reason: .appLaunch)
        }
        self.appDataStack = stack
        self.profileStore = profileStore
        self.actionStore = actionStore
        self.syncStatusViewModel = stack.syncStatusViewModel
        configureAppDelegate(with: stack)
        isPresentingCloudPrompt = cloudStatusController.status == .needsAccount
    }

    func configureAppDelegate(with stack: AppDataStack) {
        appDelegate.configure(with: stack.cloudSyncEnabled ? stack.syncCoordinator : nil,
                              sharedSubscriptionManager: stack.sharedSubscriptionManager,
                              shareAcceptanceHandler: stack.shareAcceptanceHandler)
    }

    func handleCloudStatusChange(_ status: CloudAccountStatusController.Status) async {
        switch status {
        case .loading:
            isPresentingCloudPrompt = false
        case .available:
            await MainActor.run {
                updateDependencies(cloudSyncEnabled: true)
            }
        case .needsAccount:
            await MainActor.run {
                updateDependencies(cloudSyncEnabled: false)
            }
        case .localOnly:
            await MainActor.run {
                updateDependencies(cloudSyncEnabled: false)
            }
        }
    }
}
