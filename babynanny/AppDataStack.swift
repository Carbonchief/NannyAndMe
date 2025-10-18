import CloudKit
import Foundation
import os
import SwiftData

@MainActor
final class AppDataStack: ObservableObject {
    @Published private(set) var cloudSyncEnabled: Bool

    private(set) var modelContainer: ModelContainer
    private(set) var mainContext: ModelContext
    private(set) var syncCoordinator: SyncCoordinator
    private(set) var syncStatusViewModel: SyncStatusViewModel
    private(set) var shareMetadataStore: ShareMetadataStore?
    private(set) var shareAcceptanceHandler: ShareAcceptanceHandler?
    private(set) var sharedSubscriptionManager: SharedScopeSubscriptionManager?

    private let swiftDataLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "swiftdata")
    private var coalescedSaveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var sharedZoneChangeTokenStore: SharedZoneChangeTokenStore?
    private let containerIdentifier = "iCloud.com.prioritybit.babynanny"

    init(cloudSyncEnabled: Bool = false,
         modelContainer: ModelContainer? = nil,
         syncCoordinatorFactory: ((ModelContainer, ModelContext, Bool) -> SyncCoordinator)? = nil) {
        self.cloudSyncEnabled = cloudSyncEnabled
        let container = modelContainer ?? Self.makeModelContainer()
        self.modelContainer = container
        self.mainContext = container.mainContext
        if let factory = syncCoordinatorFactory {
            self.syncCoordinator = factory(container, container.mainContext, cloudSyncEnabled)
        } else {
            self.syncCoordinator = SyncCoordinator(sharedContext: container.mainContext,
                                                   cloudContainerIdentifier: containerIdentifier,
                                                   cloudSyncEnabled: cloudSyncEnabled)
        }
        self.syncStatusViewModel = SyncStatusViewModel(modelContainer: container)
        configureContexts()
        configureCloudResources(enabled: cloudSyncEnabled)
    }

    static func makeModelContainer(cloudSyncEnabled _: Bool = true,
                                   inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .private("iCloud.com.prioritybit.babynanny")
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
        guard cloudSyncEnabled else { return }
        sharedSubscriptionManager?.ensureSubscriptions()
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

    func setCloudSyncEnabled(_ isEnabled: Bool) {
        guard isEnabled != cloudSyncEnabled else { return }
        cloudSyncEnabled = isEnabled
        configureCloudResources(enabled: isEnabled)
    }

    private func configureContexts() {
        mainContext.autosaveEnabled = false
    }

    private func configureCloudResources(enabled: Bool) {
        syncCoordinator.setCloudSyncEnabled(enabled)
        guard enabled else {
            sharedSubscriptionManager = nil
            shareAcceptanceHandler = nil
            shareMetadataStore = nil
            sharedZoneChangeTokenStore = nil
            return
        }

        let metadataStore = shareMetadataStore ?? ShareMetadataStore()
        let zoneTokenStore = sharedZoneChangeTokenStore ?? SharedZoneChangeTokenStore()
        let acceptanceHandler = ShareAcceptanceHandler(modelContainer: modelContainer,
                                                       metadataStore: metadataStore,
                                                       tokenStore: zoneTokenStore)
        shareMetadataStore = metadataStore
        shareAcceptanceHandler = acceptanceHandler
        sharedZoneChangeTokenStore = zoneTokenStore
        let subscriptionManager = SharedScopeSubscriptionManager(tokenStore: zoneTokenStore,
                                                                 shareMetadataStore: metadataStore,
                                                                 ingestor: acceptanceHandler)
        sharedSubscriptionManager = subscriptionManager
        subscriptionManager.ensureSubscriptions()
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
        AppDataStack(cloudSyncEnabled: true,
                     modelContainer: makeModelContainer(inMemory: true))
    }
}
