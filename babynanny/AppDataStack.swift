import CloudKit
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
        do {
            if inMemory {
                let configuration = ModelConfiguration(
                    isStoredInMemoryOnly: true,
                    allowsSave: true
                )

                return try ModelContainer(
                    for: ProfileActionStateModel.self, BabyActionModel.self,
                    configurations: configuration
                )
            }

            let groupContainer: ModelConfiguration.GroupContainer = .appGroup(identifier: appGroupIdentifier)
            var privateConfiguration = ModelConfiguration(
                allowsSave: true,
                groupContainer: groupContainer,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )

            var sharedConfiguration = ModelConfiguration(
                allowsSave: true,
                groupContainer: groupContainer,
                cloudKitDatabase: .shared(cloudKitContainerIdentifier)
            )

            if #available(iOS 17.4, *) {
                privateConfiguration.allowsCloudSharing = true
                sharedConfiguration.allowsCloudSharing = true
            }

            let container = try ModelContainer(
                for: ProfileActionStateModel.self, BabyActionModel.self,
                configurations: privateConfiguration, sharedConfiguration
            )

            migrateLegacyStoreIfNeeded(to: container)

            return container
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

private extension AppDataStack {
    static let appGroupIdentifier = "group.com.prioritybit.babynanny"
    static let cloudKitContainerIdentifier = "iCloud.com.prioritybit.babynanny"
    static let legacyMigrationFlag = "com.prioritybit.babynanny.swiftdata.legacyMigrationComplete"
    static let migrationLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "migration")

    static func migrateLegacyStoreIfNeeded(to container: ModelContainer) {
        guard UserDefaults.standard.bool(forKey: legacyMigrationFlag) == false else { return }

        let context = container.mainContext
        var descriptor = FetchDescriptor<ProfileActionStateModel>()
        descriptor.fetchLimit = 1
        if let existingProfiles = try? context.fetch(descriptor), existingProfiles.isEmpty == false {
            UserDefaults.standard.set(true, forKey: legacyMigrationFlag)
            return
        }

        guard let legacyStoreURL = legacyStoreURL() else {
            UserDefaults.standard.set(true, forKey: legacyMigrationFlag)
            return
        }

        do {
            migrationLogger.debug("Attempting SwiftData migration from legacy store at \(legacyStoreURL.path, privacy: .public)")
            let legacyConfiguration = ModelConfiguration(url: legacyStoreURL, allowsSave: true)
            let legacyContainer = try ModelContainer(
                for: ProfileActionStateModel.self, BabyActionModel.self,
                configurations: legacyConfiguration
            )

            let legacyProfiles = try legacyContainer.mainContext.fetch(FetchDescriptor<ProfileActionStateModel>())

            guard legacyProfiles.isEmpty == false else {
                cleanupLegacyStore(at: legacyStoreURL)
                UserDefaults.standard.set(true, forKey: legacyMigrationFlag)
                return
            }

            let migrationContext = ModelContext(container)
            migrationContext.autosaveEnabled = false

            for legacyProfile in legacyProfiles {
                let migratedProfile = ProfileActionStateModel(
                    profileID: legacyProfile.resolvedProfileID,
                    name: legacyProfile.name,
                    birthDate: legacyProfile.birthDate,
                    imageData: legacyProfile.imageData
                )

                migrationContext.insert(migratedProfile)

                for action in legacyProfile.actions {
                    let clonedAction = BabyActionModel(
                        id: action.id,
                        category: action.category,
                        startDate: action.startDate,
                        endDate: action.endDate,
                        diaperType: action.diaperType,
                        feedingType: action.feedingType,
                        bottleType: action.bottleType,
                        bottleVolume: action.bottleVolume,
                        latitude: action.latitude,
                        longitude: action.longitude,
                        placename: action.placename,
                        updatedAt: action.updatedAt,
                        profile: migratedProfile
                    )

                    migrationContext.insert(clonedAction)
                }
            }

            if migrationContext.hasChanges {
                try migrationContext.save()
            }

            cleanupLegacyStore(at: legacyStoreURL)
            UserDefaults.standard.set(true, forKey: legacyMigrationFlag)
            migrationLogger.notice("Successfully migrated legacy SwiftData store to CloudKit-backed container")
        } catch {
            migrationLogger.error("Failed migrating legacy SwiftData store: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func legacyStoreURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        do {
            let storeURLs = try fileManager.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil)
            return storeURLs.first(where: { $0.pathExtension == "store" })
        } catch {
            migrationLogger.error("Unable to enumerate legacy store directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func cleanupLegacyStore(at url: URL) {
        let fileManager = FileManager.default
        let auxiliarySuffixes = ["", "-wal", "-shm"]

        for suffix in auxiliarySuffixes {
            let candidateURL = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: candidateURL.path) {
                do {
                    try fileManager.removeItem(at: candidateURL)
                } catch {
                    migrationLogger.error("Failed to remove legacy store file: \(candidateURL.path, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

extension AppDataStack {
    static func preview() -> AppDataStack {
        AppDataStack(modelContainer: makeModelContainer(inMemory: true))
    }
}
