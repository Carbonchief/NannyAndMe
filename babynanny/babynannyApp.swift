//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct babynannyApp: App {
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
