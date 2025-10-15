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
    func importsProfilesFromCloudOnFirstLaunch() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = ChildProfile(name: "Cloud", birthDate: Date().addingTimeInterval(-10_000))
        let snapshot = CloudProfileSnapshot(
            profiles: [profile],
            activeProfileID: profile.id,
            showRecentActivityOnHome: false
        )
        let importer = MockCloudImporter(result: .success(snapshot))

        let store = await ProfileStore(
            fileManager: .default,
            directory: directory,
            filename: "profiles.json",
            reminderScheduler: scheduler,
            cloudImporter: importer
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let importedProfiles = await store.profiles
        #expect(importedProfiles == [profile])
        #expect(await store.activeProfileID == profile.id)
        #expect(await store.showRecentActivityOnHome == false)
        #expect(await importer.fetchCount == 1)
    }

    @Test
    func doesNotOverrideExistingProfilesWithCloudImport() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let localProfile = ChildProfile(name: "Local", birthDate: Date())
        let localState = TestProfileState(
            profiles: [localProfile],
            activeProfileID: localProfile.id,
            showRecentActivityOnHome: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(localState)
        try data.write(to: directory.appendingPathComponent("profiles.json"))

        let cloudProfile = ChildProfile(name: "Cloud", birthDate: Date().addingTimeInterval(-50_000))
        let snapshot = CloudProfileSnapshot(
            profiles: [cloudProfile],
            activeProfileID: cloudProfile.id,
            showRecentActivityOnHome: false
        )
        let importer = MockCloudImporter(result: .success(snapshot))

        let store = await ProfileStore(
            fileManager: .default,
            directory: directory,
            filename: "profiles.json",
            reminderScheduler: scheduler,
            cloudImporter: importer
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let profiles = await store.profiles
        #expect(profiles == [localProfile])
        #expect(await importer.fetchCount == 0)
    }

    @Test
    func synchronizesProfileMetadataToSwiftData() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let initialProfile = ChildProfile(name: "Initial", birthDate: Date())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: [ProfileActionStateModel.self, BabyActionModel.self],
            configurations: configuration
        )
        let actionStore = await ActionLogStore(modelContext: container.mainContext)
        let store = await ProfileStore(
            initialProfiles: [initialProfile],
            activeProfileID: initialProfile.id,
            reminderScheduler: scheduler
        )

        await store.registerActionStore(actionStore)

        let imageData = Data([0xBA, 0x0B, 0x00])
        await store.addProfile(name: "Sky", imageData: imageData)

        let profiles = await store.profiles
        let addedProfile = try #require(profiles.first(where: { $0.name == "Sky" }))

        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let models = try container.mainContext.fetch(descriptor)
        let metadataModel = try #require(models.first(where: { $0.resolvedProfileID == addedProfile.id }))

        #expect(metadataModel.name == "Sky")
        #expect(metadataModel.imageData == imageData)

        await store.setActiveProfile(addedProfile)
        await store.updateActiveProfile { profile in
            profile.name = "Skylar"
            profile.imageData = nil
        }

        let updatedModels = try container.mainContext.fetch(descriptor)
        let updatedMetadata = try #require(updatedModels.first(where: { $0.resolvedProfileID == addedProfile.id }))

        #expect(updatedMetadata.name == "Skylar")
        #expect(updatedMetadata.imageData == nil)
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

private struct TestProfileState: Codable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool
}

private actor MockCloudImporter: ProfileCloudImporting {
    enum Result {
        case success(CloudProfileSnapshot?)
        case failure(Error)
    }

    private let result: Result
    private(set) var fetchCount: Int = 0

    init(result: Result) {
        self.result = result
    }

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        fetchCount += 1
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}
