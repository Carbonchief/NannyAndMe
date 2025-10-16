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
    @StateObject private var appDataStack = AppDataStack.shared
    @StateObject private var profileStore: ProfileStore
    private let actionStore: ActionLogStore
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()

    init() {
        Analytics.setup()
        let stack = AppDataStack.shared
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler)
        let actionStore = ActionLogStore(modelContext: stack.mainContext,
                                         reminderScheduler: scheduler,
                                         dataStack: stack)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        _profileStore = StateObject(wrappedValue: profileStore)
        self.actionStore = actionStore
        appDelegate.configure(with: stack.syncCoordinator)
        stack.prepareSubscriptionsIfNeeded()
        stack.requestSyncIfNeeded(reason: .appLaunch)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(actionStore)
                .environmentObject(shareDataCoordinator)
                .environmentObject(appDataStack.syncCoordinator)
                .onOpenURL { url in
                    guard shouldHandle(url: url) else { return }
                    shareDataCoordinator.handleIncomingFile(url: url)
                }
                .task {
                    appDataStack.prepareSubscriptionsIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    appDataStack.requestSyncIfNeeded(reason: .foregroundRefresh)
                }
        }
        .modelContainer(appDataStack.modelContainer)
    }
}

private extension babynannyApp {
    func shouldHandle(url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .json)
        }
        return url.pathExtension.lowercased() == "json"
    }
}
