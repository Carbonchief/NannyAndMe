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
