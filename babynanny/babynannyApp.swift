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

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
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
        .commands {
            ContentViewCommands()
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
    let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "appdelegate")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}

private struct ContentViewCommands: Commands {
    @FocusedValue(\.contentShortcutHandler) private var handleShortcut
    @AppStorage("trackActionLocations") private var trackActionLocations = false

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(L10n.Tab.home) {
                handleShortcut?(.selectTab(.home))
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(handleShortcut == nil)

            Button(L10n.Tab.reports) {
                handleShortcut?(.selectTab(.reports))
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(handleShortcut == nil)

            if trackActionLocations {
                Button(L10n.Tab.map) {
                    handleShortcut?(.selectTab(.map))
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(handleShortcut == nil)
            }
        }

        CommandGroup(after: .newItem) {
            if handleShortcut != nil {
                Divider()
            }

            Button(L10n.ManualEntry.title) {
                handleShortcut?(.presentManualEntry)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(handleShortcut == nil)
        }
    }
}
