//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import RevenueCat
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
    @StateObject private var authManager: SupabaseAuthManager
    @StateObject private var pushNotificationRegistrar: PushNotificationRegistrar
    @StateObject private var subscriptionService: RevenueCatSubscriptionService
    @State private var isShowingSplashScreen = true

    init() {
        let configuration = Configuration.Builder(withAPIKey: "test_ZOvBHiTttFESXkDpIwmtIaZZQSC")
            .with(storeKitVersion: .storeKit2)
            .build()
        Purchases.logLevel = .warn
        Purchases.configure(with: configuration)

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
        let authManager = SupabaseAuthManager()
        let subscriptionService = RevenueCatSubscriptionService()
        profileStore.registerAuthManager(authManager)
        actionStore.registerAuthManager(authManager)
        authManager.registerSubscriptionService(subscriptionService)

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
        _authManager = StateObject(wrappedValue: authManager)
        _pushNotificationRegistrar = StateObject(
            wrappedValue: PushNotificationRegistrar(reminderScheduler: scheduler)
        )
        _subscriptionService = StateObject(wrappedValue: subscriptionService)

        appDelegate.authManager = authManager
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appDataStack)
                    .environmentObject(profileStore)
                    .environmentObject(actionStore)
                    .environmentObject(shareDataCoordinator)
                    .environmentObject(authManager)
                    .environmentObject(LocationManager.shared)
                    .environmentObject(subscriptionService)
                    .onOpenURL { url in
                        if handleDurationActivityURL(url) {
                            return
                        }
                        if handleSupabaseURL(url) {
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
            .task {
                await pushNotificationRegistrar.registerForRemoteNotifications()
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

    func handleSupabaseURL(_ url: URL) -> Bool {
        guard url.scheme == "nannyme", url.host == "auth" else { return false }

        Task {
            await authManager.handleAuthenticationURL(url)
        }

        return true
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "appdelegate")
    weak var authManager: SupabaseAuthManager?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: AppStorageKey.pushNotificationDeviceToken)
        logger.info("Successfully registered for APNs with token: \(token, privacy: .private)")

        Task { [weak authManager] in
            await authManager?.upsertCurrentCaregiverAPNSToken()
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.removeObject(forKey: AppStorageKey.pushNotificationDeviceToken)
        logger.error("Failed to register for APNs: \(error.localizedDescription, privacy: .public)")
    }
}

enum AppStorageKey {
    static let pushNotificationDeviceToken = "pushNotificationDeviceToken"
}
