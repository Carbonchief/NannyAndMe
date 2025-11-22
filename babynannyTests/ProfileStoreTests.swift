import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import babynanny

@Suite("Profile Store")
struct ProfileStoreTests {
    @Test
    func deniesRemindersWhenNotificationsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: false)
        let profileModel = await makeProfile(name: "Alex")
        let (store, _) = await makeStore(initialProfiles: [profileModel],
                                         activeProfileID: profileModel.resolvedProfileID,
                                         reminderScheduler: scheduler)

        let result = await store.setRemindersEnabled(true)

        #expect(result == .authorizationDenied)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func enablesRemindersWhenAuthorized() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = await makeProfile(name: "Maya")
        let (store, _) = await makeStore(initialProfiles: [profileModel],
                                         activeProfileID: profileModel.resolvedProfileID,
                                         reminderScheduler: scheduler)

        let result = await store.setRemindersEnabled(true)

        #expect(result == .enabled)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == true)
        #expect(await scheduler.ensureAuthorizationInvocations == 1)
    }

    @Test
    func schedulingCustomReminderStoresOverride() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = await makeProfile(name: "Ivy", remindersEnabled: true)
        let profileID = profileModel.resolvedProfileID
        let (store, _) = await makeStore(initialProfiles: [profileModel],
                                         activeProfileID: profileID,
                                         reminderScheduler: scheduler)

        await store.scheduleCustomActionReminder(for: profileID, category: .feeding, delay: 600, isOneOff: false)

        let activeProfile = await store.activeProfile
        let override = try #require(activeProfile.actionReminderOverride(for: .feeding))
        #expect(override.isOneOff == false)
        #expect(override.fireDate.timeIntervalSinceNow > 500)
    }

    @Test
    func addProfileStoresProvidedImage() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let (store, _) = await makeStore(reminderScheduler: scheduler)

        let sampleData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        await store.addProfile(name: "Nova", imageData: sampleData)

        let profiles = await store.profiles
        let inserted = try #require(profiles.first(where: { $0.imageData == sampleData }))
        #expect(inserted.name == "Nova")
    }

    @Test
    func disablingRemindersReturnsDisabled() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = await makeProfile(name: "Avery", remindersEnabled: true)
        let profileID = profileModel.resolvedProfileID
        let (store, _) = await makeStore(initialProfiles: [profileModel],
                                         activeProfileID: profileID,
                                         reminderScheduler: scheduler)

        let result = await store.setRemindersEnabled(false)

        #expect(result == .disabled)
        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == false)
        #expect(await scheduler.ensureAuthorizationInvocations == 0)
    }

    @Test
    func synchronizeAuthorizationDisablesRemindersWhenSystemSettingIsOff() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true, authorizationStatus: .denied)
        let profileModel = await makeProfile(name: "Khai", remindersEnabled: true)
        let profileID = profileModel.resolvedProfileID
        let (store, _) = await makeStore(initialProfiles: [profileModel],
                                         activeProfileID: profileID,
                                         reminderScheduler: scheduler)

        await store.synchronizeReminderAuthorizationState()

        let activeProfile = await store.activeProfile
        #expect(activeProfile.remindersEnabled == false)
    }

    @Test
    func deletingProfileRemovesAssociatedActionState() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileAModel = await makeProfile(name: "Aria")
        let profileBModel = await makeProfile(name: "Ben", birthDate: Date().addingTimeInterval(-86_400))
        let profileAID = profileAModel.resolvedProfileID
        let profileBID = profileBModel.resolvedProfileID

        let (store, stack) = await makeStore(initialProfiles: [profileAModel, profileBModel],
                                             activeProfileID: profileAID,
                                             directory: directory,
                                             filename: "profiles.json",
                                             reminderScheduler: scheduler)

        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)
        await store.registerActionStore(actionStore)
        await actionStore.registerProfileStore(store)

        await actionStore.startAction(for: profileAID, category: .feeding)
        await actionStore.stopAction(for: profileAID, category: .feeding)

        let currentProfiles = await store.profiles
        let profileToDelete = try #require(currentProfiles.first(where: { $0.id == profileAID }))
        await store.deleteProfile(profileToDelete)

        let remainingProfiles = await store.profiles
        #expect(remainingProfiles.contains(where: { $0.id == profileAID }) == false)
        #expect(await store.activeProfileID == profileBID)

        let removedState = await actionStore.state(for: profileAID)
        #expect(removedState.history.isEmpty)
        #expect(removedState.activeActions.isEmpty)
    }

    @Test
    func loggingActionClearsCustomReminderOverride() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let profileModel = await makeProfile(name: "Luca", remindersEnabled: true)
        let profileID = profileModel.resolvedProfileID
        let (store, stack) = await makeStore(initialProfiles: [profileModel],
                                             activeProfileID: profileID,
                                             reminderScheduler: scheduler)
        let actionStore = await ActionLogStore(modelContext: stack.mainContext, dataStack: stack)

        await store.registerActionStore(actionStore)
        await actionStore.registerProfileStore(store)

        await store.scheduleCustomActionReminder(for: profileID, category: .feeding, delay: 600, isOneOff: false)
        let scheduledOverride = await store.activeProfile.actionReminderOverride(for: .feeding)
        #expect(scheduledOverride != nil)

        await actionStore.startAction(for: profileID, category: .feeding)
        await actionStore.stopAction(for: profileID, category: .feeding)
        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await store.activeProfile
        #expect(updatedProfile.actionReminderOverride(for: .feeding) == nil)
    }

    @MainActor
    private func makeProfile(name: String,
                             birthDate: Date = Date(),
                             remindersEnabled: Bool = false) -> ProfileActionStateModel {
        let model = ProfileActionStateModel(name: name,
                                            birthDate: birthDate,
                                            remindersEnabled: remindersEnabled)
        model.normalizeReminderPreferences()
        return model
    }

    @MainActor
    private func makeStore(initialProfiles: [ProfileActionStateModel] = [],
                           activeProfileID: UUID? = nil,
                           directory: URL? = nil,
                           filename: String = "childProfiles.json",
                           reminderScheduler: MockReminderScheduler) async -> (ProfileStore, AppDataStack) {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let context = stack.mainContext
        initialProfiles.forEach { context.insert($0) }
        let store = ProfileStore(modelContext: context,
                                 dataStack: stack,
                                 fileManager: .default,
                                 directory: directory,
                                 filename: filename,
                                 reminderScheduler: reminderScheduler)
        if let activeProfileID,
           let profile = store.profiles.first(where: { $0.id == activeProfileID }) {
            store.setActiveProfile(profile)
        }
        return (store, stack)
    }

    @MainActor
    private final class MockReminderScheduler: ReminderScheduling {
        private var authorizationResult: Bool
        private let status: UNAuthorizationStatus
        private(set) var ensureAuthorizationInvocations: Int = 0

        init(authorizationResult: Bool, authorizationStatus: UNAuthorizationStatus? = nil) {
            self.authorizationResult = authorizationResult
            self.status = authorizationStatus ?? (authorizationResult ? .authorized : .denied)
        }

        func ensureAuthorization() async -> Bool {
            ensureAuthorizationInvocations += 1
            return authorizationResult
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            status
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
