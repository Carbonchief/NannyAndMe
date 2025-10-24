import Foundation
import SwiftData
import Testing
@testable import babynanny

@Suite("Profile Store")
struct ProfileStoreTests {
    @Test
    func deniesRemindersWhenNotificationsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: false)
        let profile = ChildProfile(name: "Alex", birthDate: Date())
        let store = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(true)

        #expect(result == .authorizationDenied)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func enablesRemindersWhenAuthorized() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Maya", birthDate: Date())
        let store = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(true)

        #expect(result == .enabled)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == true)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func schedulingCustomReminderStoresOverride() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Ivy", birthDate: Date(), remindersEnabled: true)
        let store = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        await store.scheduleCustomActionReminder(for: profile.id, category: .feeding, delay: 600, isOneOff: false)

        let activeProfile = await store.activeProfile
        let override = try #require(activeProfile.actionReminderOverride(for: .feeding))
        #expect(override.isOneOff == false)
        #expect(override.fireDate.timeIntervalSinceNow > 500)
    }

    @Test
    func addProfileStoresProvidedImage() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let store = await ProfileStore(
            initialProfiles: [],
            reminderScheduler: scheduler
        )

        let sampleData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        await store.addProfile(name: "Nova", imageData: sampleData)

        let profiles = await store.profiles
        #expect(profiles.count == 1)
        #expect(profiles.first?.imageData == sampleData)
    }

    @Test
    func disablingRemindersReturnsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Avery", birthDate: Date(), remindersEnabled: true)
        let store = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(false)

        #expect(result == .disabled)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 0)
    }

    @Test
    func deletingProfileRemovesAssociatedActionState() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileA = ChildProfile(name: "Aria", birthDate: Date())
        let profileB = ChildProfile(name: "Ben", birthDate: Date().addingTimeInterval(-86_400))

        let store = await ProfileStore(
            initialProfiles: [profileA, profileB],
            activeProfileID: profileA.id,
            directory: directory,
            filename: "profiles.json",
            reminderScheduler: scheduler
        )

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: [ProfileActionStateModel.self, BabyActionModel.self],
            configurations: configuration
        )
        let actionStore = await ActionLogStore(modelContext: container.mainContext)
        await store.registerActionStore(actionStore)
        await actionStore.registerProfileStore(store)

        await actionStore.startAction(for: profileA.id, category: .feeding)
        await actionStore.stopAction(for: profileA.id, category: .feeding)

        await store.deleteProfile(profileA)

        let remainingProfiles = await store.profiles
        #expect(remainingProfiles.contains(where: { $0.id == profileA.id }) == false)
        #expect(await store.activeProfileID == profileB.id)

        let removedState = await actionStore.state(for: profileA.id)
        #expect(removedState.history.isEmpty)
        #expect(removedState.activeActions.isEmpty)
    }

    @Test
    func loggingActionClearsCustomReminderOverride() async throws {
        let stack = await AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Luca", birthDate: Date(), remindersEnabled: true)
        let store = await ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        await store.registerActionStore(actionStore)
        await actionStore.registerProfileStore(store)

        await store.scheduleCustomActionReminder(for: profile.id, category: .feeding, delay: 600, isOneOff: false)
        let scheduledOverride = await store.activeProfile.actionReminderOverride(for: .feeding)
        #expect(scheduledOverride != nil)

        await actionStore.startAction(for: profile.id, category: .feeding)
        await actionStore.stopAction(for: profile.id, category: .feeding)
        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await store.activeProfile
        #expect(updatedProfile.actionReminderOverride(for: .feeding) == nil)
    }

    private actor MockReminderScheduler: ReminderScheduling {
    private var authorizationResult: Bool
    private(set) var ensureAuthorizationInvocations: Int = 0

    init(authorizationResult: Bool) {
        self.authorizationResult = authorizationResult
    }

    func ensureAuthorization() async -> Bool {
        ensureAuthorizationInvocations += 1
        return authorizationResult
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

private struct TestProfileState: Codable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool
}
