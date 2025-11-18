import Foundation
import SwiftData
import Testing
@testable import babynanny

@Suite("Action Log Store")
struct ActionLogStoreTests {
    @Test
    func updatesProfilesWhenMetadataChangesInSwiftData() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = ProfileActionStateModel(name: "Initial", birthDate: Date())
        profileModel.normalizeReminderPreferences()
        stack.mainContext.insert(profileModel)
        let profileStore = await ProfileStore(modelContext: stack.mainContext,
                                              dataStack: stack,
                                              reminderScheduler: scheduler)

        await profileStore.registerActionStore(actionStore)
        await actionStore.registerProfileStore(profileStore)

        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = try stack.mainContext.fetch(descriptor)
        let metadataModel = try #require(models.first(where: { $0.resolvedProfileID == profileModel.resolvedProfileID }))
        metadataModel.name = "Remote Update"
        let imageData = Data([0xCA, 0xFE])
        metadataModel.imageData = imageData
        let updatedBirthDate = Date().addingTimeInterval(-2_400)
        metadataModel.setBirthDate(updatedBirthDate)
        try stack.mainContext.save()

        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await profileStore.activeProfile
        #expect(updatedProfile.name == "Remote Update")
        #expect(updatedProfile.birthDate == updatedBirthDate.normalizedToUTC())
        #expect(updatedProfile.imageData == imageData)
    }

    @Test
    func updatesProfilesWhenMetadataChangesInBackgroundContext() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = ProfileActionStateModel(name: "Initial", birthDate: Date())
        profileModel.normalizeReminderPreferences()
        stack.mainContext.insert(profileModel)
        let profileStore = await ProfileStore(modelContext: stack.mainContext,
                                              dataStack: stack,
                                              reminderScheduler: scheduler)

        await profileStore.registerActionStore(actionStore)
        await actionStore.registerProfileStore(profileStore)

        let backgroundContext = ModelContext(container)
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = try backgroundContext.fetch(descriptor)
        let metadataModel = try #require(models.first(where: { $0.resolvedProfileID == profileModel.resolvedProfileID }))
        metadataModel.name = "Background Update"
        let imageData = Data([0xDE, 0xAD])
        metadataModel.imageData = imageData
        let updatedBirthDate = Date().addingTimeInterval(-3_600)
        metadataModel.setBirthDate(updatedBirthDate)
        try backgroundContext.save()

        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await profileStore.activeProfile
        #expect(updatedProfile.name == "Background Update")
        #expect(updatedProfile.birthDate == updatedBirthDate.normalizedToUTC())
        #expect(updatedProfile.imageData == imageData)
    }

    @Test
    func skipsNoOpSaveWhenUpdatingActionWithIdenticalValues() async throws {
        let stack = await AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let profileID = UUID()

        await actionStore.startAction(for: profileID, category: .sleep)
        await stack.flushPendingSaves()

        let currentState = await actionStore.state(for: profileID)
        let running = try #require(currentState.activeActions[.sleep])

        await actionStore.updateAction(for: profileID, action: running)

        let hasChanges = await MainActor.run { stack.mainContext.hasChanges }
        #expect(hasChanges == false)
    }

    @Test
    func conflictResolverFavorsNewestTimestamp() {
        var local = BabyActionSnapshot(category: .sleep, startDate: Date(timeIntervalSince1970: 0))
        local.updatedAt = Date(timeIntervalSince1970: 1)
        var remote = local
        remote.updatedAt = Date(timeIntervalSince1970: 2)

        let resolver = ActionConflictResolver()
        let resolved = resolver.resolve(local: local, remote: remote)

        #expect(resolved == remote)
    }

    @Test
    func conflictResolverUsesEndDateAsDeterministicTieBreaker() {
        let baseline = Date()
        var local = BabyActionSnapshot(category: .sleep, startDate: baseline, endDate: baseline.addingTimeInterval(10))
        local.updatedAt = Date(timeIntervalSince1970: 100)
        var remote = local
        remote.endDate = baseline.addingTimeInterval(20)
        remote.updatedAt = local.updatedAt

        let resolver = ActionConflictResolver()
        let resolved = resolver.resolve(local: local, remote: remote)

        #expect(resolved == remote)
    }

    @Test
    func conflictResolverTreatsNearIdenticalTimestampsAsEqual() {
        var local = BabyActionSnapshot(category: .diaper, startDate: Date(timeIntervalSince1970: 0), diaperType: .poo)
        local.updatedAt = Date(timeIntervalSince1970: 10)
        var remote = local
        remote.updatedAt = local.updatedAt.addingTimeInterval(-0.5)
        remote.diaperType = .pee

        var resolver = ActionConflictResolver()
        resolver.timestampEqualityTolerance = 1

        let resolved = resolver.resolve(local: local, remote: remote)

        #expect(resolved == remote)
    }

    @Test
    func conflictResolverKeepsMeaningfullyNewerLocalSnapshot() {
        var local = BabyActionSnapshot(category: .feeding, startDate: Date(timeIntervalSince1970: 0), feedingType: .bottle)
        local.updatedAt = Date(timeIntervalSince1970: 20)
        var remote = local
        remote.updatedAt = local.updatedAt.addingTimeInterval(-5)
        remote.feedingType = .meal

        var resolver = ActionConflictResolver()
        resolver.timestampEqualityTolerance = 1

        let resolved = resolver.resolve(local: local, remote: remote)

        #expect(resolved == local)
    }

    @Test
    func retainsOfflineActionsWhenReconcilingOlderSnapshot() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let profileID = UUID()

        var offlineState = ProfileActionState()
        var offlineAction = BabyActionSnapshot(category: .sleep,
                                               startDate: Date(),
                                               endDate: Date().addingTimeInterval(60))
        offlineAction.updatedAt = Date()
        offlineState.history = [offlineAction]

        await actionStore.mergeProfileState(offlineState, for: profileID)
        await stack.flushPendingSaves()

        var capturedPushes: [(UUID, [BabyActionSnapshot], [UUID])] = []
        actionStore.syncObserver = { profile, upserts, deletions in
            capturedPushes.append((profile, upserts, deletions))
        }

        let remoteSnapshot = SupabaseAuthManager.CaregiverSnapshot(actionsByProfile: [profileID: []])
        await actionStore.reconcileWithSupabase(snapshot: remoteSnapshot)
        await stack.flushPendingSaves()

        let resultingState = await actionStore.state(for: profileID)
        #expect(resultingState.history.contains(where: { $0.id == offlineAction.id }))

        let captured = try #require(capturedPushes.first(where: { $0.0 == profileID }))
        #expect(captured.1.contains(where: { $0.id == offlineAction.id }))
        #expect(captured.2.isEmpty)

        let descriptor = FetchDescriptor<BabyActionModel>()
        let storedActions = try stack.mainContext.fetch(descriptor)
        let storedOffline = try #require(storedActions.first(where: { $0.id == offlineAction.id }))
        #expect(storedOffline.isPendingSync)
    }

    @Test
    func userRefreshOnlyQueuesModifiedActionsAfterNoOp() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let profileID = UUID()

        var remoteAction = BabyActionSnapshot(category: .sleep,
                                              startDate: Date().addingTimeInterval(-600),
                                              endDate: Date().addingTimeInterval(-300))
        remoteAction.updatedAt = Date()
        let remoteSnapshot = SupabaseAuthManager.CaregiverSnapshot(actionsByProfile: [profileID: [remoteAction]])

        var capturedPushes: [(UUID, [BabyActionSnapshot], [UUID])] = []
        actionStore.syncObserver = { profile, upserts, deletions in
            capturedPushes.append((profile, upserts, deletions))
        }

        await actionStore.performUserInitiatedRefresh(using: remoteSnapshot)
        #expect(capturedPushes.isEmpty)

        capturedPushes.removeAll()
        await actionStore.performUserInitiatedRefresh(using: remoteSnapshot)
        #expect(capturedPushes.isEmpty)

        var currentState = await actionStore.state(for: profileID)
        var modifiedAction = try #require(currentState.history.first(where: { $0.id == remoteAction.id }))
        modifiedAction.endDate = modifiedAction.endDate?.addingTimeInterval(60)

        await actionStore.updateAction(for: profileID, action: modifiedAction)
        await stack.flushPendingSaves()

        capturedPushes.removeAll()
        await actionStore.performUserInitiatedRefresh(using: remoteSnapshot)

        let pendingSync = try #require(capturedPushes.first)
        #expect(pendingSync.0 == profileID)
        #expect(pendingSync.1.count == 1)
        #expect(pendingSync.1.first?.id == modifiedAction.id)
        #expect(pendingSync.2.isEmpty)
    }

    @Test
    func preventsMutationsWhenProfileIsReadOnly() async {
        let stack = await AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let profileID = UUID()

        let model = ProfileActionStateModel(profileID: profileID)
        model.sharePermission = .view
        stack.mainContext.insert(model)

        await actionStore.startAction(for: profileID, category: .sleep)
        let state = await actionStore.state(for: profileID)
        #expect(state.activeActions[.sleep] == nil)
    }

    @Test
    func preventsManualEntriesWhenProfileIsReadOnly() async {
        let stack = await AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let profileID = UUID()

        let model = ProfileActionStateModel(profileID: profileID)
        model.sharePermission = .view
        stack.mainContext.insert(model)

        var snapshot = BabyActionSnapshot(category: .feeding,
                                          startDate: Date().addingTimeInterval(-300),
                                          endDate: Date(),
                                          feedingType: .bottle,
                                          bottleType: .formula,
                                          bottleVolume: 90)
        snapshot.updatedAt = Date()

        await actionStore.addManualAction(for: profileID, action: snapshot)

        let state = await actionStore.state(for: profileID)
        #expect(state.history.isEmpty)
        #expect(state.activeActions.isEmpty)
    }

    @Test
    func treatsUnknownProfilesAsReadOnlyUntilPermissionIsKnown() async throws {
        let stack = await AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let unknownProfileID = UUID()

        await actionStore.startAction(for: unknownProfileID, category: .sleep)

        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let storedModels = try stack.mainContext.fetch(descriptor)
        #expect(storedModels.isEmpty)

        let resultingState = await actionStore.state(for: unknownProfileID)
        #expect(resultingState.activeActions.isEmpty)
        #expect(resultingState.history.isEmpty)
    }
}

@MainActor
private final class MockReminderScheduler: ReminderScheduling {
    private var authorizationResult: Bool

    init(authorizationResult: Bool) {
        self.authorizationResult = authorizationResult
    }

    func ensureAuthorization() async -> Bool {
        authorizationResult
    }

    func refreshReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState]) async {}

    func upcomingReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState], reference: Date) async -> [ReminderOverview] {
        []
    }

    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool {
        false
    }
}
