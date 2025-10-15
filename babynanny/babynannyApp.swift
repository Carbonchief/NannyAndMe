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
    @StateObject private var profileStore: ProfileStore
    private let actionStore: ActionLogStore
    private let modelContainer: ModelContainer
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()

    init() {
        Analytics.setup()
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler)
        let configuration = Self.makeModelConfiguration()
        do {
            self.modelContainer = try ModelContainer(
                for: ProfileActionStateModel.self, BabyActionModel.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
        let actionStore = ActionLogStore(modelContext: modelContainer.mainContext,
                                         reminderScheduler: scheduler)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        _profileStore = StateObject(wrappedValue: profileStore)
        self.actionStore = actionStore
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
        .modelContainer(modelContainer)
    }
}

private extension babynannyApp {
    static func makeModelConfiguration() -> ModelConfiguration {
        if let configuration = ModelConfiguration(
            groupContainer: .identifier("group.com.prioritybit.babynanny"),
            cloudKitDatabase: .none
        ) {
            return configuration
        }

        return ModelConfiguration()
    }

    func shouldHandle(url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .json)
        }
        return url.pathExtension.lowercased() == "json"
    }
}
