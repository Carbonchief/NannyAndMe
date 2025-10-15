import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ActionLogStore: ObservableObject {
    private let modelContext: ModelContext
    private let reminderScheduler: ReminderScheduling?
    private weak var profileStore: ProfileStore?

    struct MergeSummary: Equatable {
        var added: Int
        var updated: Int

        static let empty = MergeSummary(added: 0, updated: 0)
    }

    init(modelContext: ModelContext, reminderScheduler: ReminderScheduling? = nil) {
        self.modelContext = modelContext
        self.reminderScheduler = reminderScheduler
        scheduleReminders()
    }

    private func notifyChange() {
        objectWillChange.send()
    }

    func registerProfileStore(_ store: ProfileStore) {
        profileStore = store
        scheduleReminders()
        refreshDurationActivityOnLaunch()
    }

    func synchronizeProfileMetadata(_ profiles: [ChildProfile]) {
        for profile in profiles {
            let model = profileModel(for: profile.id)
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if model.name != trimmedName {
                model.name = trimmedName
            }
            if model.imageData != profile.imageData {
                model.imageData = profile.imageData
            }
        }

        if modelContext.hasChanges {
            do {
                try modelContext.save()
            } catch {
                #if DEBUG
                print("Failed to synchronize profile metadata: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func state(for profileID: UUID) -> ProfileActionState {
        guard let model = existingProfileModel(for: profileID) else {
            return ProfileActionState()
        }

        var activeActions: [BabyActionCategory: BabyAction] = [:]
        var history: [BabyAction] = []

        var seenIDs = Set<UUID>()

        for actionModel in model.actions {
            let action = actionModel.asBabyAction().withValidatedDates()
            guard seenIDs.contains(action.id) == false else { continue }
            seenIDs.insert(action.id)
            if action.endDate == nil {
                if action.category.isInstant {
                    var instant = action
                    instant.endDate = instant.startDate
                    history.append(instant)
                } else {
                    if let existing = activeActions[action.category], existing.startDate > action.startDate {
                        continue
                    }
                    activeActions[action.category] = action
                }
            } else {
                history.append(action)
            }
        }

        history.sort { $0.startDate > $1.startDate }
        return ProfileActionState(activeActions: activeActions, history: history)
    }

    func startAction(for profileID: UUID,
                     category: BabyActionCategory,
                     diaperType: BabyAction.DiaperType? = nil,
                     feedingType: BabyAction.FeedingType? = nil,
                     bottleType: BabyAction.BottleType? = nil,
                     bottleVolume: Int? = nil) {
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()

        if category.isInstant {
            if var existing = profileState.activeActions.removeValue(forKey: category) {
                existing.endDate = now
                profileState.history.insert(existing, at: 0)
            }

            let action = BabyAction(category: category,
                                    startDate: now,
                                    endDate: now,
                                    diaperType: diaperType,
                                    feedingType: feedingType,
                                    bottleType: bottleType,
                                    bottleVolume: bottleVolume)
            profileState.history.insert(action, at: 0)
            persist(profileState: profileState, for: profileID)
            refreshDurationActivity(for: profileID)
            return
        }

        let conflictingCategories = profileState.activeActions.keys.filter { key in
            key != category && !key.isInstant
        }

        for conflict in conflictingCategories {
            if var running = profileState.activeActions.removeValue(forKey: conflict) {
                running.endDate = now
                profileState.history.insert(running, at: 0)
            }
        }

        if var existing = profileState.activeActions.removeValue(forKey: category) {
            existing.endDate = now
            profileState.history.insert(existing, at: 0)
        }

        var action = BabyAction(category: category,
                                startDate: now,
                                endDate: nil,
                                diaperType: diaperType,
                                feedingType: feedingType,
                                bottleType: bottleType,
                                bottleVolume: bottleVolume)
        action = Self.clamp(action, avoiding: profileState.history)
        profileState.activeActions[category] = action

        persist(profileState: profileState, for: profileID)
        refreshDurationActivity(for: profileID)
    }

    func stopAction(for profileID: UUID, category: BabyActionCategory) {
        notifyChange()
        var profileState = state(for: profileID)
        guard var running = profileState.activeActions.removeValue(forKey: category) else { return }
        running.endDate = Date()
        profileState.history.insert(running, at: 0)
        persist(profileState: profileState, for: profileID)
        refreshDurationActivity(for: profileID)
    }

    func updateAction(for profileID: UUID, action updatedAction: BabyAction) {
        notifyChange()
        var profileState = state(for: profileID)
        let sanitized = updatedAction.withValidatedDates()

        if let active = profileState.activeActions[sanitized.category], active.id == sanitized.id {
            profileState.activeActions[sanitized.category] = sanitized
        } else if let historyIndex = profileState.history.firstIndex(where: { $0.id == sanitized.id }) {
            profileState.history[historyIndex] = sanitized
        }

        profileState.history.sort { $0.startDate > $1.startDate }
        persist(profileState: profileState, for: profileID)
        refreshDurationActivity(for: profileID)
    }

    func continueAction(for profileID: UUID, actionID: UUID) {
        guard canContinueAction(for: profileID, actionID: actionID) else { return }
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()

        if let index = profileState.history.firstIndex(where: { $0.id == actionID }) {
            let action = profileState.history.remove(at: index)
            var restarted = BabyAction(category: action.category,
                                       startDate: now,
                                       endDate: nil,
                                       diaperType: action.diaperType,
                                       feedingType: action.feedingType,
                                       bottleType: action.bottleType,
                                       bottleVolume: action.bottleVolume)
            restarted = Self.clamp(restarted, avoiding: profileState.history)
            profileState.activeActions[restarted.category] = restarted
            persist(profileState: profileState, for: profileID)
            refreshDurationActivity(for: profileID)
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
        refreshDurationActivity(for: profileID)
    }

    func removeProfileData(for profileID: UUID) {
        notifyChange()
        guard let model = existingProfileModel(for: profileID) else { return }
        modelContext.delete(model)

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Failed to delete action log: \(error.localizedDescription)")
            #endif
        }

        refreshDurationActivity(for: profileID)
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
                if existing != sanitized {
                    existingHistory[sanitized.id] = sanitized
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
                if existing.id == sanitized.id {
                    if existing != sanitized {
                        profileState.activeActions[category] = sanitized
                        summary.updated += 1
                    }
                } else if sanitized.startDate >= existing.startDate {
                    profileState.activeActions[category] = sanitized
                    summary.added += 1
                }
            } else {
                profileState.activeActions[category] = sanitized
                summary.added += 1
            }
        }

        persist(profileState: profileState, for: profileID)
        refreshDurationActivity(for: profileID)
        return summary
    }

    var actionStatesSnapshot: [UUID: ProfileActionState] {
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = (try? modelContext.fetch(descriptor)) ?? []
        return models.reduce(into: [UUID: ProfileActionState]()) { partialResult, model in
            let identifier = model.resolvedProfileID
            partialResult[identifier] = state(for: identifier)
        }
    }

    static func previewStore(profiles: [UUID: ProfileActionState]) -> ActionLogStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ProfileActionStateModel.self, BabyActionModel.self, configurations: configuration)
        let context = container.mainContext

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
                                                  profile: model)
                context.insert(modelAction)
            }
        }

        return ActionLogStore(modelContext: context)
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

        if model.profileID == nil {
            model.profileID = profileID
            try? modelContext.save()
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
        let model = profileModel(for: profileID)
        let existingModels = Dictionary(uniqueKeysWithValues: model.actions.map { ($0.id, $0) })
        let desiredActions = Array(profileState.activeActions.values) + profileState.history
        var seenIDs = Set<UUID>()

        for action in desiredActions.map({ $0.withValidatedDates() }) {
            let modelAction: BabyActionModel
            if let existing = existingModels[action.id] {
                modelAction = existing
            } else {
                modelAction = BabyActionModel(id: action.id,
                                              category: action.category,
                                              startDate: action.startDate,
                                              endDate: action.endDate,
                                              diaperType: action.diaperType,
                                              feedingType: action.feedingType,
                                              bottleType: action.bottleType,
                                              bottleVolume: action.bottleVolume,
                                              profile: model)
                modelContext.insert(modelAction)
            }

            modelAction.update(from: action)
            modelAction.profile = model
            seenIDs.insert(modelAction.id)
        }

        for (identifier, modelAction) in existingModels where seenIDs.contains(identifier) == false {
            modelContext.delete(modelAction)
        }

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("Failed to save action log: \(error.localizedDescription)")
            #endif
        }

        scheduleReminders()
    }

    static func clamp(_ action: BabyAction, avoiding conflicts: [BabyAction]) -> BabyAction {
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

    func refreshDurationActivity(for profileID: UUID) {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }

        let profile = profileStore?.profiles.first(where: { $0.id == profileID })
        let profileName = profile?.displayName
        let activeActions = state(for: profileID).activeActions.values.map { $0 }
        DurationActivityController.shared.update(
            for: profileName,
            actions: activeActions
        )
#endif
    }

    func refreshDurationActivityOnLaunch() {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }

        let snapshot = actionStatesSnapshot
        if let runningProfileID = snapshot.first(where: { _, state in
            state.activeActions.values.contains(where: { $0.endDate == nil && $0.category.isInstant == false })
        })?.key {
            refreshDurationActivity(for: runningProfileID)
            return
        }

        if let fallbackProfileID = profileStore?.activeProfileID ?? snapshot.keys.first {
            refreshDurationActivity(for: fallbackProfileID)
        }
#endif
    }

    func scheduleReminders() {
        guard let reminderScheduler else { return }
        let profiles = profileStore?.profiles ?? []
        let actionStates = actionStatesSnapshot

        Task { [profiles, actionStates] in
            await reminderScheduler.refreshReminders(for: profiles, actionStates: actionStates)
        }
    }
}
