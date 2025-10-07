import Foundation
import Testing
@testable import babynanny

@Suite("Profile Store")
struct ProfileStoreTests {
    @Test
    func deniesRemindersWhenNotificationsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: false)
        let profile = ChildProfile(name: "Alex", birthDate: Date())
        let store = ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(true)

        #expect(result == .authorizationDenied)
        #expect(store.activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func enablesRemindersWhenAuthorized() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Maya", birthDate: Date())
        let store = ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(true)

        #expect(result == .enabled)
        #expect(store.activeProfile.remindersEnabled == true)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func disablingRemindersReturnsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profile = ChildProfile(name: "Avery", birthDate: Date(), remindersEnabled: true)
        let store = ProfileStore(
            initialProfiles: [profile],
            activeProfileID: profile.id,
            reminderScheduler: scheduler
        )

        let result = await store.setRemindersEnabled(false)

        #expect(result == .disabled)
        #expect(store.activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 0)
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
}
