import Foundation
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

        let actionStore = await ActionLogStore(
            directory: directory,
            filename: "actions.json"
        )
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
