@preconcurrency import CoreData
import Foundation
import SwiftData
import SwiftUI
import os

@MainActor
final class ActionLogStore: ObservableObject {
    struct LoggedLocation: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var placename: String?
    }

    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "action-log-store")
    private let modelContext: ModelContext
    private let reminderScheduler: ReminderScheduling?
    private weak var profileStore: ProfileStore?
    private let notificationCenter: NotificationCenter
    private let dataStack: AppDataStack
    private weak var authManager: SupabaseAuthManager?
    private let observedContainerIdentifier: ObjectIdentifier
    private let observedManagedObjectContextIdentifier: ObjectIdentifier?
    private let observedPersistentStoreCoordinatorIdentifier: ObjectIdentifier?
    private var contextObservers: [NSObjectProtocol] = []
    private var localMutationDepth = 0
    private let conflictResolver = ActionConflictResolver()
    private var cachedStates: [UUID: ProfileActionState] = [:]
    private var pendingRemoteDeletions: [UUID: Set<UUID>] = [:]
    private var stateReloadTask: Task<Void, Never>?

    private struct PersistentStoreContextIdentifiers {
        var contextIdentifier: ObjectIdentifier?
        var coordinatorIdentifier: ObjectIdentifier?
    }

    struct MergeSummary: Equatable, Sendable {
        var added: Int
        var updated: Int

        static let empty = MergeSummary(added: 0, updated: 0)
    }

    private struct PendingSupabaseSync: Sendable {
        var profileID: UUID
        var upserts: [BabyActionSnapshot]
        var deletedIDs: [UUID]

        var isEmpty: Bool { upserts.isEmpty && deletedIDs.isEmpty }
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
    }

    deinit {
        stateReloadTask?.cancel()
        for token in contextObservers {
            notificationCenter.removeObserver(token)
        }
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

    func registerAuthManager(_ manager: SupabaseAuthManager) {
        authManager = manager
    }

    func performUserInitiatedRefresh(
        using snapshotOverride: SupabaseAuthManager.CaregiverSnapshot? = nil
    ) async {
        logger.log("User-initiated refresh started. Auth available: \(self.authManager != nil, privacy: .public)")
        let isAuthenticated = authManager?.isAuthenticated ?? false
        logger.log("Auth status before refresh: \(isAuthenticated, privacy: .public)")
        await dataStack.flushPendingSaves()

        let snapshot: SupabaseAuthManager.CaregiverSnapshot?
        if let snapshotOverride {
            snapshot = snapshotOverride
            logger.log("Using provided Supabase snapshot override for refresh.")
        } else if let authManager, authManager.isAuthenticated {
            snapshot = await authManager.fetchCaregiverSnapshot()
        } else {
            snapshot = nil
        }

        if let snapshot {
            logger.log("Fetched Supabase snapshot. profiles=\(snapshot.profileCount, privacy: .public) actions=\(snapshot.actionCount, privacy: .public)")
            await reconcileWithSupabase(snapshot: snapshot)
        } else {
            if let authManager {
                logger.warning("Skipping Supabase snapshot fetch. isAuthenticated=\(authManager.isAuthenticated, privacy: .public)")
            } else {
                logger.warning("Skipping Supabase snapshot fetch. authManager missing.")
            }
        }

        let reloadTask = reloadStateFromPersistentStore()
        await reloadTask.value
        logger.log("User-initiated refresh completed.")
    }

    func reconcileWithSupabase(snapshot: SupabaseAuthManager.CaregiverSnapshot) async {
        let localStatesBeforeMerge = await actionStatesSnapshot()
        let remoteIDsByProfile = snapshot.actionIdentifiersByProfile
        logger.log("Reconciling Supabase snapshot. remoteProfiles=\(remoteIDsByProfile.count, privacy: .public) localProfiles=\(localStatesBeforeMerge.count, privacy: .public)")

        let remoteProfileIDs = Set(remoteIDsByProfile.keys)
        let stalePendingProfiles = pendingRemoteDeletions.keys.filter { remoteProfileIDs.contains($0) == false }
        for profileID in stalePendingProfiles {
            pendingRemoteDeletions.removeValue(forKey: profileID)
        }

        var ignoredRemoteActions: [UUID: Set<UUID>] = [:]

        for (profileID, remoteIDs) in remoteIDsByProfile {
            if var pending = pendingRemoteDeletions[profileID] {
                pending.formIntersection(remoteIDs)
                if pending.isEmpty {
                    pendingRemoteDeletions.removeValue(forKey: profileID)
                } else {
                    pendingRemoteDeletions[profileID] = pending
                }
            }

            let localState = localStatesBeforeMerge[profileID]
            let localActive = localState.map { Array($0.activeActions.values) } ?? []
            let localHistory = localState?.history ?? []
            let localIDs = Set((localActive + localHistory).map(\.id))
            let pending = pendingRemoteDeletions[profileID] ?? []
            let deletions = remoteIDs.subtracting(localIDs).intersection(pending)
            if deletions.isEmpty == false {
                ignoredRemoteActions[profileID] = deletions
            }
        }
        let ignoredCount = ignoredRemoteActions.reduce(0) { $0 + $1.value.count }
        if ignoredCount > 0 {
            logger.log("Ignoring \(ignoredCount, privacy: .public) remote actions due to pending deletions.")
        }

        applySupabaseSnapshot(snapshot, ignoringRemoteActions: ignoredRemoteActions)

        let localStatesAfterMerge = await actionStatesSnapshot()
        await pushLocalStateToSupabase(localStates: localStatesAfterMerge,
                                       remoteActionIDsByProfile: remoteIDsByProfile)
        logger.log("Supabase reconciliation finished. postMergeProfiles=\(localStatesAfterMerge.count, privacy: .public)")
    }

    func synchronizeProfileMetadata(_ profiles: [ChildProfile]) {
        let didMutate: Bool = performLocalMutation {
            var hasChanges = false

            for profile in profiles {
                var didMutateCurrent = false
                let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedName.isEmpty == false else { continue }

                let model = profileModel(for: profile.id)
                if model.name != trimmedName {
                    model.name = trimmedName
                    didMutateCurrent = true
                }
                let normalizedBirthDate = profile.birthDate.normalizedToUTC()
                if model.birthDate != normalizedBirthDate {
                    model.setBirthDate(profile.birthDate)
                    didMutateCurrent = true
                }
                if model.imageData != profile.imageData {
                    model.imageData = profile.imageData
                    didMutateCurrent = true
                }
                if didMutateCurrent {
                    model.touch()
                }

                if didMutateCurrent {
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
                     bottleVolume: Int? = nil,
                     location: LoggedLocation? = nil) {
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()
        var loggedCategories = Set<BabyActionCategory>()

        if category.isInstant {
            if var existing = profileState.activeActions.removeValue(forKey: category) {
                existing.endDate = now
                existing.updatedAt = Date()
                profileState.history.insert(existing, at: 0)
                loggedCategories.insert(category)
            }

            var action = BabyActionSnapshot(category: category,
                                            startDate: now,
                                            endDate: now,
                                            diaperType: diaperType,
                                            feedingType: feedingType,
                                            bottleType: bottleType,
                                            bottleVolume: bottleVolume)
            if let location {
                action.latitude = location.latitude
                action.longitude = location.longitude
                action.placename = location.placename
            }
            profileState.history.insert(action, at: 0)
            persist(profileState: profileState, for: profileID)
            refreshDurationActivities()
            loggedCategories.insert(category)
            notifyActionLogged(for: loggedCategories, profileID: profileID)
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
                loggedCategories.insert(conflict)
            }
        }

        if var existing = profileState.activeActions.removeValue(forKey: category) {
            existing.endDate = now
            existing.updatedAt = Date()
            profileState.history.insert(existing, at: 0)
            loggedCategories.insert(category)
        }

        var action = BabyActionSnapshot(category: category,
                                        startDate: now,
                                        endDate: nil,
                                        diaperType: diaperType,
                                        feedingType: feedingType,
                                        bottleType: bottleType,
                                        bottleVolume: bottleVolume)
        if let location {
            action.latitude = location.latitude
            action.longitude = location.longitude
            action.placename = location.placename
        }
        action = Self.clamp(action, avoiding: profileState.history)
        profileState.activeActions[category] = action

        persist(profileState: profileState, for: profileID)
        synchronizeDurationActivityIfNeeded(for: action)
        refreshDurationActivities()
        notifyActionLogged(for: loggedCategories, profileID: profileID)
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
        notifyActionLogged(for: [category], profileID: profileID)
    }

    func stopAction(withID actionID: UUID) {
        guard let actionModel = existingAction(withID: actionID),
              let profileModel = actionModel.profile else { return }

        guard actionModel.endDate == nil else { return }

        let profileID = profileModel.resolvedProfileID
        notifyChange()
        var profileState = state(for: profileID)
        var loggedCategories = Set<BabyActionCategory>()

        let now = Date()
        actionModel.endDate = now
        actionModel.updatedAt = now

        if var running = profileState.activeActions[actionModel.category], running.id == actionID {
            running.endDate = now
            running.updatedAt = now
            profileState.activeActions.removeValue(forKey: actionModel.category)
            profileState.history.insert(running, at: 0)
            loggedCategories.insert(actionModel.category)
        } else {
            var snapshot = actionModel.asSnapshot().withValidatedDates()
            snapshot.endDate = now
            snapshot.updatedAt = now

            if let index = profileState.history.firstIndex(where: { $0.id == actionID }) {
                profileState.history[index] = snapshot
            } else {
                profileState.history.insert(snapshot, at: 0)
            }
            loggedCategories.insert(actionModel.category)
        }

        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
        notifyActionLogged(for: loggedCategories, profileID: profileID)
    }

    func updateAction(for profileID: UUID, action updatedAction: BabyActionSnapshot) {
        var profileState = state(for: profileID)
        let sanitized = updatedAction.withValidatedDates()
        var didChange = false
        var activeActionForDurationSync: BabyActionSnapshot?

        if let active = profileState.activeActions[sanitized.category], active.id == sanitized.id {
            guard active != sanitized else { return }
            var updated = sanitized
            updated.updatedAt = Date()
            profileState.activeActions[sanitized.category] = updated
            activeActionForDurationSync = updated
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
        if let activeActionForDurationSync,
           activeActionForDurationSync.endDate == nil {
            synchronizeDurationActivityIfNeeded(for: activeActionForDurationSync)
        }
        refreshDurationActivities()
    }

    func addManualAction(for profileID: UUID, action manualAction: BabyActionSnapshot) {
        notifyChange()
        var profileState = state(for: profileID)
        var sanitized = manualAction.withValidatedDates()
        sanitized.updatedAt = Date()

        if sanitized.category.isInstant {
            sanitized.endDate = sanitized.startDate
        }

        profileState.history.removeAll { $0.id == sanitized.id }

        if sanitized.endDate == nil && sanitized.category.isInstant == false {
            profileState.activeActions[sanitized.category] = sanitized
            synchronizeDurationActivityIfNeeded(for: sanitized)
        } else {
            profileState.history.append(sanitized)
            profileState.history.sort { $0.startDate > $1.startDate }
        }

        persist(profileState: profileState, for: profileID)
        refreshDurationActivities()
        notifyActionLogged(for: [sanitized.category], profileID: profileID)
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
            synchronizeDurationActivityIfNeeded(for: restarted)
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
            // `ModelContainer` is not `Sendable`, but we only pass the reference
            // to create a short-lived background `ModelContext` before hopping
            // back to the main actor.
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
        let pendingSync: PendingSupabaseSync = performLocalMutation {
            let model = profileModel(for: profileID)
            let existingModels = Dictionary(uniqueKeysWithValues: model.actions.map { ($0.id, $0) })
            let desiredActions = Array(profileState.activeActions.values) + profileState.history
            var seenIDs = Set<UUID>()
            var actionsToUpsert: [BabyActionSnapshot] = []
            var deletedIdentifiers: [UUID] = []

            for action in desiredActions.map({ $0.withValidatedDates() }) {
                if let existing = existingModels[action.id] {
                    let existingSnapshot = existing.asSnapshot().withValidatedDates()
                    let resolved = conflictResolver.resolve(local: existingSnapshot, remote: action)
                    guard resolved != existingSnapshot else {
                        seenIDs.insert(existing.id)
                        continue
                    }
                    guard resolved.updatedAt >= existingSnapshot.updatedAt else {
                        seenIDs.insert(existing.id)
                        continue
                    }
                    let sanitizedResolved = resolved.withValidatedDates()
                    existing.update(from: sanitizedResolved)
                    existing.profile = model
                    seenIDs.insert(existing.id)
                    actionsToUpsert.append(sanitizedResolved)
                } else {
                    let newAction = BabyActionModel(id: action.id,
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
                                                    profile: model)
                    modelContext.insert(newAction)
                    seenIDs.insert(newAction.id)
                    actionsToUpsert.append(action)
                }
            }

            for (identifier, modelAction) in existingModels where seenIDs.contains(identifier) == false {
                modelContext.delete(modelAction)
                deletedIdentifiers.append(identifier)
            }

            cachedStates[profileID] = profileState

            if deletedIdentifiers.isEmpty == false {
                var pending = pendingRemoteDeletions[profileID] ?? []
                pending.formUnion(deletedIdentifiers)
                pendingRemoteDeletions[profileID] = pending
            }

            return PendingSupabaseSync(profileID: profileID,
                                       upserts: actionsToUpsert,
                                       deletedIDs: deletedIdentifiers)
        }

        dataStack.scheduleSaveIfNeeded(on: modelContext, reason: "persist-profile-state")

        scheduleReminders()
        enqueueSupabaseSync(pendingSync)
    }

    private func enqueueSupabaseSync(_ pendingSync: PendingSupabaseSync) {
        guard pendingSync.isEmpty == false else { return }
        guard let authManager else { return }

        let upserts = pendingSync.upserts.map { $0.withValidatedDates() }
        let deletedIDs = pendingSync.deletedIDs
        let profileID = pendingSync.profileID

        Task { @MainActor [weak authManager] in
            guard let manager = authManager else { return }
            await manager.syncBabyActions(upserting: upserts,
                                          deletingIDs: deletedIDs,
                                          profileID: profileID)
        }
    }

    private func applySupabaseSnapshot(_ snapshot: SupabaseAuthManager.CaregiverSnapshot,
                                       ignoringRemoteActions: [UUID: Set<UUID>] = [:]) {
        if snapshot.metadataUpdates.isEmpty == false {
            profileStore?.applyMetadataUpdates(snapshot.metadataUpdates)
            logger.log("Applied \(snapshot.metadataUpdates.count, privacy: .public) metadata updates from Supabase.")
        }

        var actionsByProfile = snapshot.actionsByProfile
        let totalIncomingActions = actionsByProfile.reduce(into: 0) { partialResult, element in
            partialResult += element.value.count
        }
        logger.log("Processing \(totalIncomingActions, privacy: .public) incoming actions across \(actionsByProfile.count, privacy: .public) profiles.")

        for (profileID, ignoredIDs) in ignoringRemoteActions where ignoredIDs.isEmpty == false {
            let filtered = actionsByProfile[profileID]?.filter { ignoredIDs.contains($0.id) == false } ?? []
            actionsByProfile[profileID] = filtered
            logger.log("Filtered \(ignoredIDs.count, privacy: .public) ignored remote actions for profile \(profileID, privacy: .public).")
        }

        applySupabaseActions(actionsByProfile, profileIdentifiers: snapshot.profileIdentifiers)
    }

    private func applySupabaseActions(_ remoteActions: [UUID: [BabyActionSnapshot]],
                                      profileIdentifiers: Set<UUID>) {
        let targetProfileIDs = profileIdentifiers.union(remoteActions.keys)
        guard targetProfileIDs.isEmpty == false else { return }
        logger.log("Applying remote actions for \(targetProfileIDs.count, privacy: .public) profiles.")

        let didMutate: Bool = performLocalMutation {
            var hasChanges = false

            for profileID in targetProfileIDs {
                let desiredActions = remoteActions[profileID]?.map { $0.withValidatedDates() } ?? []
                let model = profileModel(for: profileID)
                let existingModels = Dictionary(uniqueKeysWithValues: model.actions.map { ($0.id, $0) })
                var seenIDs = Set<UUID>()

                for action in desiredActions {
                    if let existing = existingModels[action.id] {
                        let existingSnapshot = existing.asSnapshot().withValidatedDates()
                        let resolved = conflictResolver.resolve(local: existingSnapshot, remote: action)
                        seenIDs.insert(existing.id)
                        guard resolved != existingSnapshot else { continue }
                        let sanitized = resolved.withValidatedDates()
                        existing.update(from: sanitized)
                        existing.profile = model
                        hasChanges = true
                    } else {
                        let sanitized = action.withValidatedDates()
                        let newAction = BabyActionModel(id: sanitized.id,
                                                        category: sanitized.category,
                                                        startDate: sanitized.startDate,
                                                        endDate: sanitized.endDate,
                                                        diaperType: sanitized.diaperType,
                                                        feedingType: sanitized.feedingType,
                                                        bottleType: sanitized.bottleType,
                                                        bottleVolume: sanitized.bottleVolume,
                                                        latitude: sanitized.latitude,
                                                        longitude: sanitized.longitude,
                                                        placename: sanitized.placename,
                                                        updatedAt: sanitized.updatedAt,
                                                        profile: model)
                        modelContext.insert(newAction)
                        seenIDs.insert(newAction.id)
                        hasChanges = true
                    }
                }

                for (identifier, actionModel) in existingModels where seenIDs.contains(identifier) == false {
                    modelContext.delete(actionModel)
                    hasChanges = true
                }

                cachedStates[profileID] = model.makeActionState()
            }

            return hasChanges
        }

        guard didMutate else { return }
        logger.log("Remote actions resulted in local mutations.")

        if modelContext.hasChanges {
            dataStack.saveIfNeeded(on: modelContext, reason: "supabase-actions-merge")
            logger.log("Saved model context after applying remote actions.")
        }

        notifyChange()
        scheduleReminders()
        refreshDurationActivities()
    }

    private func pushLocalStateToSupabase(localStates: [UUID: ProfileActionState],
                                          remoteActionIDsByProfile: [UUID: Set<UUID>]) async {
        guard let authManager, authManager.isAuthenticated else { return }
        logger.log("Pushing local state for \(localStates.count, privacy: .public) profiles back to Supabase.")

        for (profileID, state) in localStates {
            let actions = (state.activeActions.values + state.history).map { $0.withValidatedDates() }
            let localIDs = Set(actions.map(\.id))
            let remoteIDs = remoteActionIDsByProfile[profileID] ?? []
            let deletions = Array(remoteIDs.subtracting(localIDs))

            await authManager.syncBabyActions(upserting: actions,
                                              deletingIDs: deletions,
                                              profileID: profileID)
            logger.log("Queued sync for profile \(profileID, privacy: .public). upserts=\(actions.count, privacy: .public) deletions=\(deletions.count, privacy: .public)")
        }

        let remoteOnlyProfiles = Set(remoteActionIDsByProfile.keys).subtracting(localStates.keys)

        for profileID in remoteOnlyProfiles {
            let deletions = Array(remoteActionIDsByProfile[profileID] ?? [])
            guard deletions.isEmpty == false else { continue }
            await authManager.syncBabyActions(upserting: [],
                                              deletingIDs: deletions,
                                              profileID: profileID)
            logger.log("Queued remote-only deletion sync for profile \(profileID, privacy: .public) with \(deletions.count, privacy: .public) deletions.")
        }
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
        // ---------- ObjectsDidChange (same context) ----------
        let primaryToken = notificationCenter.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: modelContext,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let shouldReloadFromStore = self.isPerformingLocalMutation == false
                self.handleModelContextChange(reloadFromPersistentStore: shouldReloadFromStore)
            }
        }
        contextObservers.append(primaryToken)

        // Pre-extract identifiers so the closure doesn’t touch `self` before the Task hop.
        let observedContainerIdentifier = self.observedContainerIdentifier
        let observedManagedObjectContextIdentifier = self.observedManagedObjectContextIdentifier
        let observedPersistentStoreCoordinatorIdentifier = self.observedPersistentStoreCoordinatorIdentifier
        let observedModelContextIdentifier = ObjectIdentifier(self.modelContext)

        // ---------- DidSave (other contexts in same container) ----------
        let externalToken = notificationCenter.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Compute the flag in a nonisolated way (no `self` used).
            let shouldHandle = Self.shouldHandleExternalContextChange(
                notification: notification,
                observedContainerIdentifier: observedContainerIdentifier,
                observedManagedObjectContextIdentifier: observedManagedObjectContextIdentifier,
                observedPersistentStoreCoordinatorIdentifier: observedPersistentStoreCoordinatorIdentifier,
                observedModelContextIdentifier: observedModelContextIdentifier
            )
            guard shouldHandle else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleModelContextChange(reloadFromPersistentStore: true)
            }
        }
        contextObservers.append(externalToken)

        // ---------- RemoteChange (external persistent changes) ----------
        let remoteToken = notificationCenter.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleModelContextChange(reloadFromPersistentStore: true)
            }
        }
        contextObservers.append(remoteToken)
    }

    private func handleModelContextChange(reloadFromPersistentStore: Bool) {
        if reloadFromPersistentStore {
            _ = reloadStateFromPersistentStore()
        } else {
            applyModelContextChanges(prefetchedStates: nil)
        }
    }

    @discardableResult
    private func reloadStateFromPersistentStore() -> Task<Void, Never> {
        stateReloadTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.stateReloadTask = nil }
            let snapshot = await self.actionStatesSnapshot()
            guard Task.isCancelled == false else { return }
            self.applyModelContextChanges(prefetchedStates: snapshot)
        }
        stateReloadTask = task
        return task
    }

    func applyModelContextChanges(prefetchedStates: [UUID: ProfileActionState]? = nil) {
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
        // Read everything inside the MainActor task; do not capture non-Sendable values.
        guard UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") else { return }
        Task { @MainActor [weak self] in
            guard let self = self,
                  let scheduler = self.reminderScheduler else { return }
            let profiles = self.profileStore?.profiles ?? []
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

    func notifyActionLogged(for categories: Set<BabyActionCategory>, profileID: UUID) {
        guard categories.isEmpty == false else { return }

        Task { @MainActor [weak self] in
            guard let self = self,
                  let store = self.profileStore else { return }
            for category in categories {
                store.actionLogged(for: profileID, category: category)
            }
        }
    }

    func synchronizeDurationActivityIfNeeded(for action: BabyActionSnapshot) {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *), action.category.isInstant == false else { return }
        let actionID = action.id

        Task { @MainActor [weak self] in
            guard let self,
                  let model = self.existingAction(withID: actionID) else { return }
            await DurationActivityController.synchronizeActivity(for: model)
        }
#endif
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

        let mirror = Mirror(reflecting: root)

        if mirror.displayStyle == .class {
            let identifier = ObjectIdentifier(root as AnyObject)
            guard visitedObjects.insert(identifier).inserted else { return nil }
        }

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

        let mirror = Mirror(reflecting: root)

        if mirror.displayStyle == .class {
            let identifier = ObjectIdentifier(root as AnyObject)
            guard visitedObjects.insert(identifier).inserted else { return nil }
        }

        for child in mirror.children {
            if let coordinator = extractPersistentStoreCoordinator(from: child.value, visitedObjects: &visitedObjects) {
                return coordinator
            }
        }

        return nil
    }
}

// Nonisolated helper so we can decide synchronously in a notification closure
// without calling a @MainActor instance method.
private extension ActionLogStore {
    nonisolated static func shouldHandleExternalContextChange(
        notification: Notification,
        observedContainerIdentifier: ObjectIdentifier,
        observedManagedObjectContextIdentifier: ObjectIdentifier?,
        observedPersistentStoreCoordinatorIdentifier: ObjectIdentifier?,
        observedModelContextIdentifier: ObjectIdentifier
    ) -> Bool {
        guard let context = notification.object else { return false }

        if let modelContext = context as? ModelContext {
            // Same container, but not the same ModelContext instance.
            guard ObjectIdentifier(modelContext.container) == observedContainerIdentifier else { return false }
            return ObjectIdentifier(modelContext) != observedModelContextIdentifier
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
