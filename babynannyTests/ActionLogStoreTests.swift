import Foundation
import SwiftData
import Testing
@testable import babynanny

@Suite("Action Log Store")
struct ActionLogStoreTests {
    @Test
    func updatesProfilesWhenMetadataChangesInSwiftData() async throws {
        let profile = ChildProfile(name: "Initial", birthDate: Date())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: [ProfileActionStateModel.self, BabyActionModel.self],
            configurations: configuration
        )
        let actionStore = await ActionLogStore(modelContext: container.mainContext)
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileStore = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        await profileStore.registerActionStore(actionStore)
        await actionStore.registerProfileStore(profileStore)

        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = try container.mainContext.fetch(descriptor)
        let metadataModel = try #require(models.first(where: { $0.resolvedProfileID == profile.id }))
        metadataModel.name = "Remote Update"
        let imageData = Data([0xCA, 0xFE])
        metadataModel.imageData = imageData
        let updatedBirthDate = Date().addingTimeInterval(-2_400)
        metadataModel.birthDate = updatedBirthDate
        try container.mainContext.save()

        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await profileStore.activeProfile
        #expect(updatedProfile.name == "Remote Update")
        #expect(updatedProfile.birthDate == updatedBirthDate)
        #expect(updatedProfile.imageData == imageData)
    }

    @Test
    func updatesProfilesWhenMetadataChangesInBackgroundContext() async throws {
        let profile = ChildProfile(name: "Initial", birthDate: Date())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: [ProfileActionStateModel.self, BabyActionModel.self],
            configurations: configuration
        )
        let actionStore = await ActionLogStore(modelContext: container.mainContext)
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileStore = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        await profileStore.registerActionStore(actionStore)
        await actionStore.registerProfileStore(profileStore)

        let backgroundContext = ModelContext(container)
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = try backgroundContext.fetch(descriptor)
        let metadataModel = try #require(models.first(where: { $0.resolvedProfileID == profile.id }))
        metadataModel.name = "Background Update"
        let imageData = Data([0xDE, 0xAD])
        metadataModel.imageData = imageData
        let updatedBirthDate = Date().addingTimeInterval(-3_600)
        metadataModel.birthDate = updatedBirthDate
        try backgroundContext.save()

        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await profileStore.activeProfile
        #expect(updatedProfile.name == "Background Update")
        #expect(updatedProfile.birthDate == updatedBirthDate)
        #expect(updatedProfile.imageData == imageData)
    }
}

private actor MockReminderScheduler: ReminderScheduling {
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
