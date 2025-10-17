import CloudKit
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
    private var contextObservers: [NSObjectProtocol] = []
    private let conflictResolver = ActionConflictResolver()
    private let shareMetadataStore: ShareMetadataStore
    private let sharedDatabase: CKDatabase
    private let shareLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "share-sync")
    private let privateDatabase: CKDatabase

    struct MergeSummary: Equatable {
        var added: Int
        var updated: Int

        static let empty = MergeSummary(added: 0, updated: 0)
    }

    init(modelContext: ModelContext,
         reminderScheduler: ReminderScheduling? = nil,
         notificationCenter: NotificationCenter = .default,
         dataStack: AppDataStack? = nil,
         shareMetadataStore: ShareMetadataStore = ShareMetadataStore(),
         sharedDatabase: CKDatabase? = nil,
         privateDatabase: CKDatabase? = nil) {
        self.modelContext = modelContext
        self.reminderScheduler = reminderScheduler
        self.notificationCenter = notificationCenter
        self.dataStack = dataStack ?? AppDataStack.shared
        self.observedContainerIdentifier = ObjectIdentifier(modelContext.container)
        self.shareMetadataStore = shareMetadataStore
        let container = CKContainer(identifier: "iCloud.com.prioritybit.babynanny")
        self.sharedDatabase = sharedDatabase ?? container.sharedCloudDatabase
        self.privateDatabase = privateDatabase ?? container.privateCloudDatabase
        scheduleReminders()
        observeModelContextChanges()
    }

    deinit {
        let observers = contextObservers
        let center = notificationCenter
        guard observers.isEmpty == false else { return }
        Task { @MainActor in
            for token in observers {
                center.removeObserver(token)
            }
        }
    }

    private func notifyChange() {
        objectWillChange.send()
    }

    func registerProfileStore(_ store: ProfileStore) {
        profileStore = store
        scheduleReminders()
        refreshDurationActivityOnLaunch()
        synchronizeMetadataFromModelContext()
    }

    func synchronizeProfileMetadata(_ profiles: [ChildProfile]) {
        for profile in profiles {
            let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedName.isEmpty == false else { continue }

            let model = profileModel(for: profile.id)
            if model.name != trimmedName {
                model.name = trimmedName
            }
            let normalizedBirthDate = profile.birthDate.normalizedToUTC()
            if model.birthDate != normalizedBirthDate {
                model.birthDate = normalizedBirthDate
            }
            if model.imageData != profile.imageData {
                model.imageData = profile.imageData
            }
        }

        if modelContext.hasChanges {
            dataStack.saveIfNeeded(on: modelContext, reason: "profile-metadata-sync")
        }
    }

    func state(for profileID: UUID) -> ProfileActionState {
        guard let model = existingProfileModel(for: profileID) else {
            return ProfileActionState()
        }

        var activeActions: [BabyActionCategory: BabyActionSnapshot] = [:]
        var history: [BabyActionSnapshot] = []

        var seenIDs = Set<UUID>()

        for actionModel in model.actions {
            let action = actionModel.asSnapshot().withValidatedDates()
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
            refreshDurationActivity(for: profileID)
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
        refreshDurationActivity(for: profileID)
    }

    func stopAction(for profileID: UUID, category: BabyActionCategory) {
        notifyChange()
        var profileState = state(for: profileID)
        guard var running = profileState.activeActions.removeValue(forKey: category) else { return }
        running.endDate = Date()
        running.updatedAt = Date()
        profileState.history.insert(running, at: 0)
        persist(profileState: profileState, for: profileID)
        refreshDurationActivity(for: profileID)
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
        refreshDurationActivity(for: profileID)
    }

    func continueAction(for profileID: UUID, actionID: UUID) {
        guard canContinueAction(for: profileID, actionID: actionID) else { return }
        notifyChange()
        var profileState = state(for: profileID)
        let now = Date()

        if let index = profileState.history.firstIndex(where: { $0.id == actionID }) {
            let action = profileState.history.remove(at: index)
            var restarted = BabyActionSnapshot(category: action.category,
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
        dataStack.saveIfNeeded(on: modelContext, reason: "remove-profile-data")

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
                                                  updatedAt: action.updatedAt,
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
        let model = profileModel(for: profileID)
        let existingModels = Dictionary(uniqueKeysWithValues: model.actions.map { ($0.id, $0) })
        let existingActionIDs = Set(existingModels.keys)
        let desiredActions = Array(profileState.activeActions.values) + profileState.history
        var seenIDs = Set<UUID>()
        var changedActionIDs = Set<UUID>()

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
                changedActionIDs.insert(existing.id)
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
                changedActionIDs.insert(newAction.id)
            }
        }

        var deletedActionIDs: [UUID] = []
        for (identifier, modelAction) in existingModels where seenIDs.contains(identifier) == false {
            modelContext.delete(modelAction)
            deletedActionIDs.append(identifier)
        }

        dataStack.scheduleSaveIfNeeded(on: modelContext, reason: "persist-profile-state")

        scheduleReminders()

        let actionsForShare = model.actions
            .filter { changedActionIDs.contains($0.id) }
            .map { $0.asSnapshot().withValidatedDates() }

        if actionsForShare.isEmpty == false || deletedActionIDs.isEmpty == false {
            Task { [weak self] in
                await self?.synchronizeSharedActionsIfNeeded(for: profileID,
                                                             actions: actionsForShare,
                                                             deletedActionIDs: deletedActionIDs,
                                                             existingActionIDs: existingActionIDs)
            }
        }
    }

    private func synchronizeSharedActionsIfNeeded(for profileID: UUID,
                                                  actions: [BabyActionSnapshot],
                                                  deletedActionIDs: [UUID],
                                                  existingActionIDs: Set<UUID>) async {
        guard actions.isEmpty == false || deletedActionIDs.isEmpty == false else { return }

        let metadata = await shareMetadataStore.metadata(for: profileID)
        guard let metadata, metadata.isShared else { return }

        let zoneID = metadata.zoneID
        let profileRecordID = metadata.rootRecordID
        let database = database(for: metadata)

        do {
            let recordsToSave = try await buildSharedActionRecords(for: actions,
                                                                   zoneID: zoneID,
                                                                   profileRecordID: profileRecordID,
                                                                   existingActionIDs: existingActionIDs,
                                                                   database: database)
            let recordIDsToDelete = Array(Set(deletedActionIDs.map { identifier in
                CKRecord.ID(recordName: "action-\(identifier.uuidString)", zoneID: zoneID)
            }))

            guard recordsToSave.isEmpty == false || recordIDsToDelete.isEmpty == false else { return }

            let savedRecords = try await modifySharedRecords(recordsToSave: recordsToSave,
                                                              recordIDsToDelete: recordIDsToDelete,
                                                              database: database)
            mergeSharedRecords(savedRecords, deletedRecordIDs: recordIDsToDelete, profileID: profileID)
        } catch {
            if Task.isCancelled { return }
            shareLogger.error("Failed to synchronize shared actions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func buildSharedActionRecords(for actions: [BabyActionSnapshot],
                                          zoneID: CKRecordZone.ID,
                                          profileRecordID: CKRecord.ID,
                                          existingActionIDs: Set<UUID>,
                                          database: CKDatabase) async throws -> [CKRecord] {
        guard actions.isEmpty == false else { return [] }

        let recordIDsToFetch = actions
            .filter { existingActionIDs.contains($0.id) }
            .map { CKRecord.ID(recordName: "action-\($0.id.uuidString)", zoneID: zoneID) }
        let existingRecords = try await fetchExistingRecords(withIDs: recordIDsToFetch, database: database)
        let profileReference = CKRecord.Reference(recordID: profileRecordID, action: .deleteSelf)

        return actions.map { action in
            let recordID = CKRecord.ID(recordName: "action-\(action.id.uuidString)", zoneID: zoneID)
            let record = existingRecords[recordID] ?? CKRecord(recordType: CloudKitSharingManager.RecordType.babyAction.rawValue,
                                                               recordID: recordID)
            record["id"] = action.id.uuidString as CKRecordValue
            record["category"] = action.category.rawValue as CKRecordValue
            record["startDate"] = action.startDate as CKRecordValue
            if let endDate = action.endDate {
                record["endDate"] = endDate as CKRecordValue
            } else {
                record["endDate"] = nil
            }
            if let diaper = action.diaperType?.rawValue {
                record["diaperType"] = diaper as CKRecordValue
            } else {
                record["diaperType"] = nil
            }
            if let feeding = action.feedingType?.rawValue {
                record["feedingType"] = feeding as CKRecordValue
            } else {
                record["feedingType"] = nil
            }
            if let bottleType = action.bottleType?.rawValue {
                record["bottleType"] = bottleType as CKRecordValue
            } else {
                record["bottleType"] = nil
            }
            if let bottleVolume = action.bottleVolume {
                record["bottleVolume"] = NSNumber(value: bottleVolume)
            } else {
                record["bottleVolume"] = nil
            }
            record["updatedAt"] = action.updatedAt as CKRecordValue
            record["profile"] = profileReference
            return record
        }
    }

    private func fetchExistingRecords(withIDs recordIDs: [CKRecord.ID],
                                      database: CKDatabase) async throws -> [CKRecord.ID: CKRecord] {
        guard recordIDs.isEmpty == false else { return [:] }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord.ID: CKRecord], Error>) in
            var fetched: [CKRecord.ID: CKRecord] = [:]
            var firstError: Error?

            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.perRecordResultBlock = { recordID, result in
                switch result {
                case .success(let record):
                    fetched[recordID] = record
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        return
                    }
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let error = firstError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: fetched)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func modifySharedRecords(recordsToSave: [CKRecord],
                                     recordIDsToDelete: [CKRecord.ID],
                                     database: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var savedRecords: [CKRecord] = []
            var firstError: Error?

            let records = recordsToSave.isEmpty ? nil : recordsToSave
            let deletions = recordIDsToDelete.isEmpty ? nil : recordIDsToDelete

            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: deletions)
            operation.savePolicy = .allKeys
            operation.isAtomic = false
            operation.perRecordSaveBlock = { _, result in
                switch result {
                case .success(let record):
                    savedRecords.append(record)
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let error = firstError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: savedRecords)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func mergeSharedRecords(_ records: [CKRecord],
                                    deletedRecordIDs: [CKRecord.ID],
                                    profileID: UUID) {
        guard records.isEmpty == false || deletedRecordIDs.isEmpty == false else { return }

        var didMutate = false
        for record in records where record.recordType == CloudKitSharingManager.RecordType.babyAction.rawValue {
            if mergeSharedBabyActionRecord(record, profileID: profileID) {
                didMutate = true
            }
        }

        for recordID in deletedRecordIDs {
            if deleteSharedBabyActionRecord(recordID) {
                didMutate = true
            }
        }

        if didMutate {
            dataStack.scheduleSaveIfNeeded(on: modelContext, reason: "merge-shared-actions")
            notifyChange()
        }
    }

    private func mergeSharedBabyActionRecord(_ record: CKRecord, profileID: UUID) -> Bool {
        guard let idString = record["id"] as? String,
              let actionID = UUID(uuidString: idString) else {
            return false
        }

        let predicate = #Predicate<BabyActionModel> { model in
            model.id == actionID
        }
        var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            let existing = try modelContext.fetch(descriptor).first
            let model = existing ?? BabyActionModel(id: actionID)
            if existing == nil {
                model.profile = profileModel(for: profileID)
                modelContext.insert(model)
            } else if model.profile == nil {
                model.profile = profileModel(for: profileID)
            }

            var mutated = false
            if let categoryRaw = record["category"] as? String,
               let category = BabyActionCategory(rawValue: categoryRaw),
               model.category != category {
                model.category = category
                mutated = true
            }
            if let startDate = record["startDate"] as? Date, model.startDate != startDate {
                model.startDate = startDate
                mutated = true
            }
            let endDate = record["endDate"] as? Date
            if model.endDate != endDate {
                model.endDate = endDate
                mutated = true
            }
            if let diaper = record["diaperType"] as? String {
                let diaperType = BabyActionSnapshot.DiaperType(rawValue: diaper)
                if model.diaperType != diaperType {
                    model.diaperType = diaperType
                    mutated = true
                }
            } else if model.diaperType != nil {
                model.diaperType = nil
                mutated = true
            }
            if let feeding = record["feedingType"] as? String {
                let feedingType = BabyActionSnapshot.FeedingType(rawValue: feeding)
                if model.feedingType != feedingType {
                    model.feedingType = feedingType
                    mutated = true
                }
            } else if model.feedingType != nil {
                model.feedingType = nil
                mutated = true
            }
            if let bottleTypeRaw = record["bottleType"] as? String {
                let bottleType = BabyActionSnapshot.BottleType(rawValue: bottleTypeRaw)
                if model.bottleType != bottleType {
                    model.bottleType = bottleType
                    mutated = true
                }
            } else if model.bottleType != nil {
                model.bottleType = nil
                mutated = true
            }
            if let bottleVolumeNumber = record["bottleVolume"] as? NSNumber {
                let volume = bottleVolumeNumber.intValue
                if model.bottleVolume != volume {
                    model.bottleVolume = volume
                    mutated = true
                }
            } else if model.bottleVolume != nil {
                model.bottleVolume = nil
                mutated = true
            }
            if let updatedAt = record["updatedAt"] as? Date, model.updatedAt != updatedAt {
                model.updatedAt = updatedAt
                mutated = true
            }

            return mutated
        } catch {
            shareLogger.error("Failed to merge shared action \(record.recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func deleteSharedBabyActionRecord(_ recordID: CKRecord.ID) -> Bool {
        guard recordID.recordName.hasPrefix("action-"),
              let uuid = UUID(uuidString: recordID.recordName.replacingOccurrences(of: "action-", with: "")) else {
            return false
        }

        let predicate = #Predicate<BabyActionModel> { model in
            model.id == uuid
        }
        var descriptor = FetchDescriptor<BabyActionModel>(predicate: predicate)
        descriptor.fetchLimit = 1

        do {
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
                return true
            }
        } catch {
            shareLogger.error("Failed to delete shared action \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return false
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

    private func observeModelContextChanges() {
        let primaryToken = notificationCenter.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                                                           object: modelContext,
                                                           queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleModelContextChange()
            }
        }
        contextObservers.append(primaryToken)

        let externalToken = notificationCenter.addObserver(forName: .NSManagedObjectContextDidSave,
                                                            object: nil,
                                                            queue: nil) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.shouldHandleExternalContextChange(from: notification) else { return }
                self.handleModelContextChange()
            }
        }
        contextObservers.append(externalToken)

        let remoteToken = notificationCenter.addObserver(forName: .NSPersistentStoreRemoteChange,
                                                          object: nil,
                                                          queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleModelContextChange()
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

        return false
    }

    private func handleModelContextChange() {
        objectWillChange.send()
        synchronizeMetadataFromModelContext()
        refreshDurationActivityForAllProfiles()
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

    private func refreshDurationActivityForAllProfiles() {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }
        guard let profileStore else { return }
        let profileIDs = profileStore.profiles.map { $0.id }
        for identifier in profileIDs {
            refreshDurationActivity(for: identifier)
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

    private func database(for metadata: ShareMetadataStore.ShareMetadata) -> CKDatabase {
        if metadata.ownerName == CKCurrentUserDefaultName {
            return privateDatabase
        }
        return sharedDatabase
    }
}
