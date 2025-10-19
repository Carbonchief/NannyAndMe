import CoreData
import Foundation
import SwiftData
import SwiftUI
import os

@MainActor
final class ActionLogStore: ObservableObject {
    private let modelContext: ModelContext
    private let reminderScheduler: ReminderScheduling?
    private weak var profileStore: ProfileStore?
    private let notificationCenter: NotificationCenter
    private let dataStack: AppDataStack
    private let observedContainerIdentifier: ObjectIdentifier
    private let observedManagedObjectContextIdentifier: ObjectIdentifier?
    private let observedPersistentStoreCoordinatorIdentifier: ObjectIdentifier?
    private var contextObservers: [NSObjectProtocol] = []
    private var localMutationDepth = 0
    private let conflictResolver = ActionConflictResolver()
    private var isObservingSyncCoordinator = false
    private var cachedStates: [UUID: ProfileActionState] = [:]
    private var stateReloadTask: Task<Void, Never>?

    private struct PersistentStoreContextIdentifiers {
        var contextIdentifier: ObjectIdentifier?
        var coordinatorIdentifier: ObjectIdentifier?
    }

    struct MergeSummary: Equatable {
        var added: Int
        var updated: Int

        static let empty = MergeSummary(added: 0, updated: 0)
    }

    init(modelContext: ModelContext,
         reminderScheduler: ReminderScheduling? = nil,
         notificationCenter: NotificationCenter = .default,
         dataStack: AppDataStack) {
        self.modelContext = modelContext
        self.reminderScheduler = reminderScheduler
        self.notificationCenter = notificationCenter
        self.dataStack = dataStack
        self.observedContainerIdentifier = ObjectIdentifier(modelContext.container)
        let contextIdentifiers = Self.makePersistentStoreContextIdentifiers(for: modelContext)
        self.observedManagedObjectContextIdentifier = contextIdentifiers.contextIdentifier
        self.observedPersistentStoreCoordinatorIdentifier = contextIdentifiers.coordinatorIdentifier
        scheduleReminders()
        observeModelContextChanges()
        observeSyncCoordinatorIfNeeded()
    }

    deinit {
        stateReloadTask?.cancel()
        contextObservers.removeAll()
    }

    private func notifyChange() {
        objectWillChange.send()
    }

    private var isPerformingLocalMutation: Bool {
        localMutationDepth > 0
    }

    @discardableResult
    private func performLocalMutation<R>(_ work: () throws -> R) rethrows -> R {
        localMutationDepth += 1
        defer { localMutationDepth -= 1 }
        return try work()
    }

    func registerProfileStore(_ store: ProfileStore) {
        profileStore = store
        scheduleReminders()
        refreshDurationActivityOnLaunch()
        synchronizeMetadataFromModelContext()
    }

    func refreshSyncObservation() {
        if dataStack.cloudSyncEnabled {
            if isObservingSyncCoordinator == false {
                observeSyncCoordinatorIfNeeded()
            }
        } else if isObservingSyncCoordinator {
            dataStack.syncCoordinator.removeObserver(self)
            isObservingSyncCoordinator = false
        }
    }

    func synchronizeProfileMetadata(_ profiles: [ChildProfile]) {
        let didMutate: Bool = performLocalMutation {
            var hasChanges = false

            for profile in profiles {
                let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedName.isEmpty == false else { continue }

                let model = profileModel(for: profile.id)
                if model.name != trimmedName {
                    model.name = trimmedName
                    hasChanges = true
                }
                let normalizedBirthDate = profile.birthDate.normalizedToUTC()
                if model.birthDate != normalizedBirthDate {
                    model.birthDate = normalizedBirthDate
                    hasChanges = true
                }
                if model.imageData != profile.imageData {
                    model.imageData = profile.imageData
                    hasChanges = true
                }
            }

            return hasChanges
        }

        guard didMutate else { return }

        if modelContext.hasChanges {
            dataStack.saveIfNeeded(on: modelContext, reason: "profile-metadata-sync")
        }
    }

    func state(for profileID: UUID) -> ProfileActionState {
        if let cached = cachedStates[profileID] {
            return cached
        }

        guard let model = existingProfileModel(for: profileID) else {
            return ProfileActionState()
        }

        let state = model.makeActionState()
        cachedStates[profileID] = state
        return state
    }

    func startAction(for profileID: UUID,
                     category: BabyActionCategory,
                     diaperType: BabyActionSnapshot.DiaperType? = nil,
                     feedingType: BabyActionSnapshot.FeedingType? = nil,
                     bottleType: BabyActionSnapshot.BottleType? = nil,
                     bottleVolume: Int? = nil) {
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()

        if category.isInstant {
            if var existing = profileState.activeActions.removeValue(forKey: category) {
                existing.endDate = now
                existing.updatedAt = Date()
                profileState.history.insert(existing, at: 0)
            }

            let action = BabyActionSnapshot(category: category,
                                            startDate: now,
                                            endDate: now,
                                            diaperType: diaperType,
                                            feedingType: feedingType,
                                            bottleType: bottleType,
                                            bottleVolume: bottleVolume)
            profileState.history.insert(action, at: 0)
            persist(profileState: profileState, for: profileID)
            refreshDurationActivities()
            return
        }

        let conflictingCategories = profileState.activeActions.keys.filter { key in
            key != category && !key.isInstant
        }

        for conflict in conflictingCategories {
            if var running = profileState.activeActions.removeValue(forKey: conflict) {
                running.endDate = now
                running.updatedAt = Date()
                profileState.history.insert(running, at: 0)
            }
        }

        if var existing = profileState.activeActions.removeValue(forKey: category) {
            existing.endDate = now
            existing.updatedAt = Date()
            profileState.history.insert(existing, at: 0)
        }

        var action = BabyActionSnapshot(category: category,
                                        startDate: now,
                                        endDate: nil,
                                        diaperType: diaperType,
                                        feedingType: feedingType,
                                        bottleType: bottleType,
                                        bottleVolume: bottleVolume)
        action = Self.clamp(action, avoiding: profileState.history)
        profileState.activeActions[category] = action

        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
    }

    func stopAction(for profileID: UUID, category: BabyActionCategory) {
        notifyChange()
        var profileState = state(for: profileID)
        guard var running = profileState.activeActions.removeValue(forKey: category) else { return }
        running.endDate = Date()
        running.updatedAt = Date()
        profileState.history.insert(running, at: 0)
        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
    }

    func stopAction(withID actionID: UUID) {
        guard let actionModel = existingAction(withID: actionID),
              let profileModel = actionModel.profile else { return }

        guard actionModel.endDate == nil else { return }

        let profileID = profileModel.resolvedProfileID
        notifyChange()
        var profileState = state(for: profileID)

        let now = Date()
        actionModel.endDate = now
        actionModel.updatedAt = now

        if var running = profileState.activeActions[actionModel.category], running.id == actionID {
            running.endDate = now
            running.updatedAt = now
            profileState.activeActions.removeValue(forKey: actionModel.category)
            profileState.history.insert(running, at: 0)
        } else {
            var snapshot = actionModel.asSnapshot().withValidatedDates()
            snapshot.endDate = now
            snapshot.updatedAt = now

            if let index = profileState.history.firstIndex(where: { $0.id == actionID }) {
                profileState.history[index] = snapshot
            } else {
                profileState.history.insert(snapshot, at: 0)
            }
        }

        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
    }

    func updateAction(for profileID: UUID, action updatedAction: BabyActionSnapshot) {
        var profileState = state(for: profileID)
        let sanitized = updatedAction.withValidatedDates()
        var didChange = false

        if let active = profileState.activeActions[sanitized.category], active.id == sanitized.id {
            guard active != sanitized else { return }
            var updated = sanitized
            updated.updatedAt = Date()
            profileState.activeActions[sanitized.category] = updated
            didChange = true
        } else if let historyIndex = profileState.history.firstIndex(where: { $0.id == sanitized.id }) {
            let existing = profileState.history[historyIndex]
            guard existing != sanitized else { return }
            var updated = sanitized
            updated.updatedAt = Date()
            profileState.history[historyIndex] = updated
            didChange = true
        }

        guard didChange else { return }

        notifyChange()
        profileState.history.sort { $0.startDate > $1.startDate }
        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
    }

    func continueAction(for profileID: UUID, actionID: UUID) {
        guard canContinueAction(for: profileID, actionID: actionID) else { return }
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()

        if let index = profileState.history.firstIndex(where: { $0.id == actionID }) {
            var restarted = profileState.history.remove(at: index)
            restarted.endDate = nil
            restarted.updatedAt = now
            profileState.activeActions[restarted.category] = restarted
            persist(profileState: profileState, for: profileID)
            refreshDurationActivities()
        }
    }

    func canContinueAction(for profileID: UUID, actionID: UUID) -> Bool {
        let profileState = state(for: profileID)
        guard let action = profileState.history.first(where: { $0.id == actionID }) else { return false }
        return !profileState.activeActions.keys.contains(action.category)
    }

    func deleteAction(for profileID: UUID, actionID: UUID) {
        notifyChange()
        var profileState = state(for: profileID)
        if let category = profileState.activeActions.first(where: { $0.value.id == actionID })?.key {
            profileState.activeActions.removeValue(forKey: category)
        }
        profileState.history.removeAll(where: { $0.id == actionID })
        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
    }

    func removeProfileData(for profileID: UUID) {
        notifyChange()
        let didMutate: Bool = performLocalMutation {
            guard let model = existingProfileModel(for: profileID) else { return false }
            modelContext.delete(model)
            cachedStates.removeValue(forKey: profileID)
            return true
        }

        guard didMutate else { return }

        dataStack.saveIfNeeded(on: modelContext, reason: "remove-profile-data")

        refreshDurationActivities()
        scheduleReminders()
    }

    func mergeProfileState(_ importedState: ProfileActionState, for profileID: UUID) -> MergeSummary {
        notifyChange()
        var summary = MergeSummary.empty
        var profileState = state(for: profileID)
        var existingHistory = Dictionary(uniqueKeysWithValues: profileState.history.map { ($0.id, $0) })

        for action in importedState.history {
            let sanitized = action.withValidatedDates()
            if let existing = existingHistory[sanitized.id] {
                let resolved = conflictResolver.resolve(local: existing, remote: sanitized)
                if resolved != existing {
                    existingHistory[sanitized.id] = resolved
                    summary.updated += 1
                }
            } else {
                existingHistory[sanitized.id] = sanitized
                summary.added += 1
            }
        }

        profileState.history = Array(existingHistory.values)

        for (category, action) in importedState.activeActions {
            let sanitized = action.withValidatedDates()
            if let existing = profileState.activeActions[category] {
                let resolved = conflictResolver.resolve(local: existing, remote: sanitized)
                if resolved.id == existing.id {
                    if resolved != existing {
                        profileState.activeActions[category] = resolved
                        summary.updated += 1
                    }
                } else if resolved.updatedAt >= existing.updatedAt {
                    profileState.activeActions[category] = resolved
                    summary.added += 1
                }
            } else {
                profileState.activeActions[category] = sanitized
                summary.added += 1
            }
        }

        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
        return summary
    }

    func actionStatesSnapshot() async -> [UUID: ProfileActionState] {
        let container = dataStack.modelContainer
        struct SendableContainer: @unchecked Sendable {
            let container: ModelContainer
        }
        let sendableContainer = SendableContainer(container: container)

        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(sendableContainer.container)
            context.autosaveEnabled = false
            let descriptor = FetchDescriptor<ProfileActionStateModel>()
            let models = (try? context.fetch(descriptor)) ?? []
            return models.reduce(into: [UUID: ProfileActionState]()) { partialResult, model in
                let identifier = model.resolvedProfileID
                partialResult[identifier] = model.makeActionState()
            }
        }.value
    }

    static func previewStore(profiles: [UUID: ProfileActionState]) -> ActionLogStore {
        let dataStack = AppDataStack.preview()
        let context = dataStack.modelContainer.mainContext

        for (profileID, state) in profiles {
            let model = ProfileActionStateModel(profileID: profileID)
            context.insert(model)
            let actions = state.activeActions.values + state.history
            for action in actions {
                let modelAction = BabyActionModel(id: action.id,
                                                  category: action.category,
                                                  startDate: action.startDate,
                                                  endDate: action.endDate,
                                                  diaperType: action.diaperType,
                                                  feedingType: action.feedingType,
                                                  bottleType: action.bottleType,
                                                  bottleVolume: action.bottleVolume,
                                                  updatedAt: action.updatedAt,
                                                  profile: model)
                context.insert(modelAction)
            }
        }
        return ActionLogStore(modelContext: context, dataStack: dataStack)
    }
}

private extension ActionLogStore {
    func existingProfileModel(for profileID: UUID) -> ProfileActionStateModel? {
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == profileID
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let model = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        if model.resolvedProfileID != profileID {
            model.resolvedProfileID = profileID
            dataStack.scheduleSaveIfNeeded(on: modelContext, reason: "assign-profile-id")
        }

        model.ensureActionOwnership()

        return model
    }

    func profileModel(for profileID: UUID) -> ProfileActionStateModel {
        if let existing = existingProfileModel(for: profileID) {
            return existing
        }
        let model = ProfileActionStateModel(profileID: profileID)
        modelContext.insert(model)
        return model
    }

    func persist(profileState: ProfileActionState, for profileID: UUID) {
        performLocalMutation {
            let model = profileModel(for: profileID)
            let existingModels = Dictionary(uniqueKeysWithValues: model.actions.map { ($0.id, $0) })
            let desiredActions = Array(profileState.activeActions.values) + profileState.history
            var seenIDs = Set<UUID>()

            for action in desiredActions.map({ $0.withValidatedDates() }) {
                if let existing = existingModels[action.id] {
                    let existingAction = existing.asSnapshot()
                    let resolved = conflictResolver.resolve(local: existingAction, remote: action)
                    guard resolved != existingAction else {
                        seenIDs.insert(existing.id)
                        continue
                    }
                    guard resolved.updatedAt >= existingAction.updatedAt else {
                        seenIDs.insert(existing.id)
                        continue
                    }
                    existing.update(from: resolved)
                    existing.profile = model
                    seenIDs.insert(existing.id)
                } else {
                    let newAction = BabyActionModel(id: action.id,
                                                    category: action.category,
                                                    startDate: action.startDate,
                                                    endDate: action.endDate,
                                                    diaperType: action.diaperType,
                                                    feedingType: action.feedingType,
                                                    bottleType: action.bottleType,
                                                    bottleVolume: action.bottleVolume,
                                                    updatedAt: action.updatedAt,
                                                    profile: model)
                    modelContext.insert(newAction)
                    seenIDs.insert(newAction.id)
                }
            }

            for (identifier, modelAction) in existingModels where seenIDs.contains(identifier) == false {
                modelContext.delete(modelAction)
            }

            cachedStates[profileID] = profileState
        }

        dataStack.scheduleSaveIfNeeded(on: modelContext, reason: "persist-profile-state")

        scheduleReminders()

    }

    static func clamp(_ action: BabyActionSnapshot, avoiding conflicts: [BabyActionSnapshot]) -> BabyActionSnapshot {
        var action = action
        let overlapping = conflicts.filter { other in
            guard other.category == action.category else { return false }
            guard let endDate = other.endDate else { return false }
            return endDate > action.startDate && other.startDate <= action.startDate
        }

        if let earliestConflict = overlapping.min(by: { $0.startDate < $1.startDate }) {
            action.startDate = earliestConflict.endDate ?? action.startDate
        }

        return action
    }

    func refreshDurationActivities() {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await DurationActivityController.syncAllActiveActivities(in: self.modelContext)
        }
#endif
    }

    func refreshDurationActivityOnLaunch() {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await DurationActivityController.syncAllActiveActivities(in: self.modelContext)
        }
#endif
    }

    private func observeModelContextChanges() {
        let primaryToken = notificationCenter.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                                                           object: modelContext,
                                                           queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let shouldReloadFromStore = self.isPerformingLocalMutation == false
                self.handleModelContextChange(reloadFromPersistentStore: shouldReloadFromStore)
            }
        }
        contextObservers.append(primaryToken)

        let externalToken = notificationCenter.addObserver(forName: .NSManagedObjectContextDidSave,
                                                            object: nil,
                                                            queue: nil) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.shouldHandleExternalContextChange(from: notification) else { return }
                self.handleModelContextChange(reloadFromPersistentStore: true)
            }
        }
        contextObservers.append(externalToken)

        let remoteToken = notificationCenter.addObserver(forName: .NSPersistentStoreRemoteChange,
                                                          object: nil,
                                                          queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleModelContextChange(reloadFromPersistentStore: true)
            }
        }
        contextObservers.append(remoteToken)
    }

    private func shouldHandleExternalContextChange(from notification: Notification) -> Bool {
        guard let context = notification.object else { return false }

        if let modelContext = context as? ModelContext {
            guard ObjectIdentifier(modelContext.container) == observedContainerIdentifier else { return false }
            return modelContext !== self.modelContext
        }

        if let managedObjectContext = context as? NSManagedObjectContext {
            if let observedManagedObjectContextIdentifier,
               ObjectIdentifier(managedObjectContext) == observedManagedObjectContextIdentifier {
                return false
            }

            guard let observedPersistentStoreCoordinatorIdentifier else { return false }

            if let coordinator = managedObjectContext.persistentStoreCoordinator {
                return ObjectIdentifier(coordinator) == observedPersistentStoreCoordinatorIdentifier
            }

            let objectIDsKey = NSManagedObjectContext.notificationObjectIDsUserInfoKey
            if let payload = notification.userInfo?[objectIDsKey] as? [AnyHashable: Set<NSManagedObjectID>] {
                for objectIDs in payload.values {
                    for objectID in objectIDs {
                        guard let coordinator = objectID.persistentStore?.persistentStoreCoordinator else { continue }
                        if ObjectIdentifier(coordinator) == observedPersistentStoreCoordinatorIdentifier {
                            return true
                        }
                    }
                }
            }

            return false
        }

        return false
    }

    private func handleModelContextChange(reloadFromPersistentStore: Bool) {
        if reloadFromPersistentStore {
            reloadStateFromPersistentStore()
        } else {
            applyModelContextChanges(prefetchedStates: nil)
        }
    }

    private func reloadStateFromPersistentStore() {
        stateReloadTask?.cancel()
        stateReloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.stateReloadTask = nil }
            let snapshot = await self.actionStatesSnapshot()
            guard Task.isCancelled == false else { return }
            self.applyModelContextChanges(prefetchedStates: snapshot)
        }
    }

    fileprivate func applyModelContextChanges(prefetchedStates: [UUID: ProfileActionState]? = nil) {
        if let prefetchedStates {
            cachedStates = prefetchedStates
        }
        objectWillChange.send()
        synchronizeMetadataFromModelContext()
        refreshDurationActivities()
        scheduleReminders()
    }

    private func synchronizeMetadataFromModelContext() {
        guard let profileStore else { return }
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        guard let models = try? modelContext.fetch(descriptor) else { return }
        let updates = models.map { model in
            ProfileStore.ProfileMetadataUpdate(
                id: model.resolvedProfileID,
                name: model.name ?? "",
                birthDate: model.birthDate,
                imageData: model.imageData
            )
        }
        profileStore.applyMetadataUpdates(updates)
    }

    func scheduleReminders() {
        guard let reminderScheduler else { return }
        let profiles = profileStore?.profiles ?? []
        let scheduler = reminderScheduler

        Task { @MainActor [weak self, profiles, scheduler] in
            guard let self else { return }
            let actionStates = await self.actionStatesSnapshot()
            await scheduler.refreshReminders(for: profiles, actionStates: actionStates)
        }
    }

}

private extension ActionLogStore {
    func existingAction(withID id: UUID) -> BabyActionModel? {
        let predicate = #Predicate<BabyActionModel> { model in
            model.id == id
        }
        var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private static func makePersistentStoreContextIdentifiers(for context: ModelContext) -> PersistentStoreContextIdentifiers {
        var visitedObjects: Set<ObjectIdentifier> = []
        var identifiers = PersistentStoreContextIdentifiers()

        if let managedObjectContext = extractManagedObjectContext(from: context, visitedObjects: &visitedObjects) ??
            extractManagedObjectContext(from: context.container, visitedObjects: &visitedObjects) {
            identifiers.contextIdentifier = ObjectIdentifier(managedObjectContext)
            if let coordinator = managedObjectContext.persistentStoreCoordinator {
                identifiers.coordinatorIdentifier = ObjectIdentifier(coordinator)
            }
        }

        if identifiers.coordinatorIdentifier == nil {
            if let coordinator = extractPersistentStoreCoordinator(from: context, visitedObjects: &visitedObjects) ??
                extractPersistentStoreCoordinator(from: context.container, visitedObjects: &visitedObjects) {
                identifiers.coordinatorIdentifier = ObjectIdentifier(coordinator)
            }
        }

        return identifiers
    }

    static func extractManagedObjectContext(from root: Any,
                                            visitedObjects: inout Set<ObjectIdentifier>) -> NSManagedObjectContext? {
        if let context = root as? NSManagedObjectContext {
            return context
        }

        if let object = root as? AnyObject {
            let identifier = ObjectIdentifier(object)
            guard visitedObjects.insert(identifier).inserted else { return nil }
        }

        let mirror = Mirror(reflecting: root)
        for child in mirror.children {
            if let context = extractManagedObjectContext(from: child.value, visitedObjects: &visitedObjects) {
                return context
            }
        }

        return nil
    }

    static func extractPersistentStoreCoordinator(from root: Any,
                                                  visitedObjects: inout Set<ObjectIdentifier>) -> NSPersistentStoreCoordinator? {
        if let coordinator = root as? NSPersistentStoreCoordinator {
            return coordinator
        }

        if let context = root as? NSManagedObjectContext,
           let coordinator = context.persistentStoreCoordinator {
            return coordinator
        }

        if let object = root as? AnyObject {
            let identifier = ObjectIdentifier(object)
            guard visitedObjects.insert(identifier).inserted else { return nil }
        }

        let mirror = Mirror(reflecting: root)
        for child in mirror.children {
            if let coordinator = extractPersistentStoreCoordinator(from: child.value, visitedObjects: &visitedObjects) {
                return coordinator
            }
        }

        return nil
    }
}

private extension NSManagedObjectContext {
    static var notificationObjectIDsUserInfoKey: String {
        // Newer SDKs vend a typed constant for the object ID payload key, but some
        // deployment targets still build against older Core Data headers where the
        // symbol does not exist. Returning the raw string keeps the lookup resilient
        // regardless of SDK availability.
        return "NSManagedObjectContextDidSaveObjectIDsKey"
    }
}

private extension ActionLogStore {
    func observeSyncCoordinatorIfNeeded() {
        let coordinator = dataStack.syncCoordinator
        guard dataStack.cloudSyncEnabled else { return }
        guard coordinator.sharesModelContainer(with: modelContext) else { return }
        coordinator.addObserver(self)
        isObservingSyncCoordinator = true
    }

    func refreshAfterSync(for reason: SyncCoordinator.SyncReason) {
        // Remote pushes and foreground refreshes should hydrate the cache from disk so the
        // UI matches a cold start. Other sync reasons currently share the same path because
        // we do not maintain a separate incremental-update pipeline yet.
        handleModelContextChange(reloadFromPersistentStore: true)
    }
}

extension ActionLogStore: SyncCoordinator.Observer {
    func syncCoordinator(_ coordinator: SyncCoordinator,
                         didMergeChangesFor reason: SyncCoordinator.SyncReason) {
        refreshAfterSync(for: reason)
    }
}
