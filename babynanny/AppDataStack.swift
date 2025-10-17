import CloudKit
import Foundation
import os
import SwiftData

@MainActor
final class AppDataStack: ObservableObject {
    static let shared = AppDataStack()

    let modelContainer: ModelContainer
    let mainContext: ModelContext
    let syncCoordinator: SyncCoordinator
    let syncStatusViewModel: SyncStatusViewModel
    let shareMetadataStore: ShareMetadataStore
    let shareAcceptanceHandler: ShareAcceptanceHandler
    let sharedSubscriptionManager: SharedScopeSubscriptionManager

    private let swiftDataLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "swiftdata")
    private var coalescedSaveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let sharedZoneChangeTokenStore: SharedZoneChangeTokenStore

    init(modelContainer: ModelContainer? = nil,
         syncCoordinatorFactory: ((ModelContainer, ModelContext) -> SyncCoordinator)? = nil) {
        let container = modelContainer ?? Self.makeModelContainer()
        self.modelContainer = container
        self.mainContext = container.mainContext
        if let factory = syncCoordinatorFactory {
            self.syncCoordinator = factory(container, container.mainContext)
        } else {
            self.syncCoordinator = SyncCoordinator(sharedContext: container.mainContext)
        }
        self.syncStatusViewModel = SyncStatusViewModel(modelContainer: container)
        let metadataStore = ShareMetadataStore()
        self.shareMetadataStore = metadataStore
        let zoneTokenStore = SharedZoneChangeTokenStore()
        self.sharedZoneChangeTokenStore = zoneTokenStore
        let acceptanceHandler = ShareAcceptanceHandler(modelContainer: container,
                                                       metadataStore: metadataStore,
                                                       tokenStore: zoneTokenStore)
        self.shareAcceptanceHandler = acceptanceHandler
        let subscriptionManager = SharedScopeSubscriptionManager(tokenStore: zoneTokenStore,
                                                                 shareMetadataStore: metadataStore,
                                                                 ingestor: acceptanceHandler)
        self.sharedSubscriptionManager = subscriptionManager
        configureContexts()
        subscriptionManager.ensureSubscriptions()
    }

    static func makeModelContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .both("iCloud.com.prioritybit.babynanny")
        )

        do {
            return try ModelContainer(
                for: ProfileActionStateModel.self, BabyActionModel.self,
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

    func requestSyncIfNeeded(reason: SyncCoordinator.SyncReason) {
        syncCoordinator.requestSyncIfNeeded(reason: reason)
    }

    func prepareSubscriptionsIfNeeded() {
        syncCoordinator.prepareSubscriptionsIfNeeded()
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
        let stack = AppDataStack(modelContainer: makeModelContainer(inMemory: true))
        return stack
    }
}
