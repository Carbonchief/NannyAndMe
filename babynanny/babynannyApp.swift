//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct babynannyApp: App {
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()

    init() {
        Analytics.setup()
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler)
        let actionStore = ActionLogStore(reminderScheduler: scheduler)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(actionStore)
                .environmentObject(shareDataCoordinator)
                .onOpenURL { url in
                    guard shouldHandle(url: url) else { return }
                    shareDataCoordinator.handleIncomingFile(url: url)
                }
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
}
