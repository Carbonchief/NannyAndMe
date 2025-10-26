import Foundation
import os
import SwiftData

@MainActor
final class AppDataStack: ObservableObject {
    private(set) var modelContainer: ModelContainer
    private(set) var mainContext: ModelContext

    private let swiftDataLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "swiftdata")
    private var coalescedSaveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    init(modelContainer: ModelContainer? = nil) {
        let container = modelContainer ?? Self.makeModelContainer()
        self.modelContainer = container
        self.mainContext = container.mainContext
        configureContexts()
    }

    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
        } else {
            configuration = ModelConfiguration(
                allowsSave: true,
                cloudKitDatabase: .private("iCloud.com.prioritybit.babynanny")
            )
        }

        do {
            return try ModelContainer(
                for: ProfileActionStateModel.self,
                    BabyActionModel.self,
                    ProfileReminderPreference.self,
                    ProfileStoreSettings.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    func backgroundContext() -> ModelContext {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return context
    }

    func scheduleSaveIfNeeded(on context: ModelContext,
                              reason: String,
                              coalescingDelay: TimeInterval = 0.35) {
        let identifier = ObjectIdentifier(context)
        coalescedSaveTasks[identifier]?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(coalescingDelay * 1_000_000_000))
            await self.performSaveIfNeeded(on: context, reason: reason)
            coalescedSaveTasks[identifier] = nil
        }
        coalescedSaveTasks[identifier] = task
    }

    func saveIfNeeded(on context: ModelContext, reason: String) {
        let identifier = ObjectIdentifier(context)
        coalescedSaveTasks[identifier]?.cancel()
        coalescedSaveTasks[identifier] = nil

        Task { [weak self] in
            guard let self else { return }
            await self.performSaveIfNeeded(on: context, reason: reason)
        }
    }

    func flushPendingSaves() async {
        let tasks = coalescedSaveTasks.values
        coalescedSaveTasks.removeAll()
        for task in tasks {
            await task.value
        }
    }

    private func configureContexts() {
        mainContext.autosaveEnabled = false
    }

    private func performSaveIfNeeded(on context: ModelContext, reason: String) async {
        guard context.hasChanges else {
            swiftDataLogger.debug("Skipping save for \(reason, privacy: .public); no changes present")
            return
        }

        do {
            try context.save()
            swiftDataLogger.debug("Saved context for \(reason, privacy: .public)")
        } catch {
            swiftDataLogger.error("Failed to save context for \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension AppDataStack {
    static func preview() -> AppDataStack {
        AppDataStack(modelContainer: makeModelContainer(inMemory: true))
    }
}
