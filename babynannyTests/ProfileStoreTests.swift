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

        await store.scheduleCustomActionReminder(for: .feeding, delay: 600, isOneOff: false)

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

        await store.scheduleCustomActionReminder(for: .feeding, delay: 600, isOneOff: false)
        let scheduledOverride = await store.activeProfile.actionReminderOverride(for: .feeding)
        #expect(scheduledOverride != nil)

        await actionStore.startAction(for: profile.id, category: .feeding)
        await actionStore.stopAction(for: profile.id, category: .feeding)
        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedProfile = await store.activeProfile
        #expect(updatedProfile.actionReminderOverride(for: .feeding) == nil)
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
    func doesNotBootstrapPlaceholderProfileBeforeCloudImportCompletes() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let importer = DeferredCloudImporter()

        let store = await ProfileStore(
            fileManager: .default,
            directory: directory,
            filename: "profiles.json",
            reminderScheduler: scheduler,
            cloudImporter: importer
        )

        #expect(await store.isAwaitingInitialCloudImport)

        let initialProfiles = await store.profiles
        #expect(initialProfiles.isEmpty)

        await importer.waitForRequest()

        let profile = ChildProfile(name: "Cloud", birthDate: Date().addingTimeInterval(-10_000))
        let snapshot = CloudProfileSnapshot(
            profiles: [profile],
            activeProfileID: profile.id,
            showRecentActivityOnHome: true
        )

        await importer.resume(with: .success(snapshot))

        try await Task.sleep(nanoseconds: 100_000_000)

        let importedProfiles = await store.profiles
        #expect(importedProfiles == [profile])
        #expect(await store.activeProfileID == profile.id)
        #expect(await store.isAwaitingInitialCloudImport == false)
    }

    @Test
    func retriesCloudImportAfterRecoverableError() async throws {
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

        let importer = MockCloudImporter(results: [
            .failure(CloudProfileImportError.recoverable(MockRecoverableError())),
            .success(snapshot)
        ])

        let store = await ProfileStore(
            fileManager: .default,
            directory: directory,
            filename: "profiles.json",
            reminderScheduler: scheduler,
            cloudImporter: importer
        )

        try await Task.sleep(nanoseconds: 1_000_000_000)

        let importedProfiles = await store.profiles
        #expect(importedProfiles == [profile])
        #expect(await store.activeProfileID == profile.id)
        #expect(await store.showRecentActivityOnHome == false)
        #expect(await importer.fetchCount == 2)
    }

    @Test
    func mergesCloudProfilesWithExistingProfiles() async throws {
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
        #expect(profiles.contains(localProfile))
        #expect(profiles.contains(cloudProfile))
        #expect(await importer.fetchCount == 1)
    }

    @Test
    func updatesLocalProfilesWithCloudChanges() async throws {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var localProfile = ChildProfile(name: "Local", birthDate: Date())
        let profileID = localProfile.id
        let localState = TestProfileState(
            profiles: [localProfile],
            activeProfileID: localProfile.id,
            showRecentActivityOnHome: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(localState)
        try data.write(to: directory.appendingPathComponent("profiles.json"))

        var updatedProfile = localProfile
        updatedProfile.name = "Updated"
        updatedProfile.remindersEnabled = true
        let snapshot = CloudProfileSnapshot(
            profiles: [updatedProfile],
            activeProfileID: updatedProfile.id,
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
        let fetchedProfile = try #require(profiles.first(where: { $0.id == profileID }))
        #expect(fetchedProfile.name == "Updated")
        #expect(fetchedProfile.remindersEnabled)
        #expect(await store.showRecentActivityOnHome == false)
        #expect(await importer.fetchCount == 1)
    }

    @Test
    func downloadsMissingCloudProfilesWhenAbsentLocally() async throws {
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

        let newProfile = ChildProfile(name: "Cloud", birthDate: Date().addingTimeInterval(-50_000))
        let snapshot = CloudProfileSnapshot(
            profiles: [newProfile],
            activeProfileID: newProfile.id,
            showRecentActivityOnHome: true
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
        #expect(profiles.contains(localProfile))
        #expect(profiles.contains(newProfile))
        #expect(await importer.fetchCount == 1)
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
        #expect(metadataModel.birthDate == addedProfile.birthDate)
        #expect(metadataModel.imageData == imageData)

        await store.setActiveProfile(addedProfile)
        await store.updateActiveProfile { profile in
            profile.name = "Skylar"
            profile.imageData = nil
        }

        let updatedModels = try container.mainContext.fetch(descriptor)
        let updatedMetadata = try #require(updatedModels.first(where: { $0.resolvedProfileID == addedProfile.id }))

        #expect(updatedMetadata.name == "Skylar")
        #expect(updatedMetadata.birthDate == addedProfile.birthDate)
        #expect(updatedMetadata.imageData == nil)
    }

    @Test
    func appliesRemoteMetadataToCreateMissingProfiles() async {
        let scheduler = MockReminderScheduler(authorizationResult: true)
        let localProfile = ChildProfile(name: "Local", birthDate: Date())
        let store = await ProfileStore(
            initialProfiles: [localProfile],
            activeProfileID: localProfile.id,
            reminderScheduler: scheduler
        )

        let remoteID = UUID()
        let birthDate = Date().addingTimeInterval(-100_000)
        let update = ProfileStore.ProfileMetadataUpdate(
            id: remoteID,
            name: "Remote", 
            birthDate: birthDate,
            imageData: Data([0x01, 0x02])
        )

        await store.applyMetadataUpdates([update])

        let profiles = await store.profiles
        let remoteProfile = profiles.first(where: { $0.id == remoteID })
        #expect(remoteProfile?.name == "Remote")
        #expect(remoteProfile?.birthDate == birthDate)
        #expect(remoteProfile?.imageData == Data([0x01, 0x02]))
        #expect(profiles.contains(localProfile))
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

private struct MockRecoverableError: Error {}

private actor MockCloudImporter: ProfileCloudImporting {
    enum Result {
        case success(CloudProfileSnapshot?)
        case failure(Error)
    }

    private var results: [Result]
    private let fallbackResult: Result
    private(set) var fetchCount: Int = 0

    init(result: Result) {
        self.results = [result]
        self.fallbackResult = result
    }

    init(results: [Result]) {
        precondition(results.isEmpty == false)
        self.results = results
        self.fallbackResult = results.last!
    }

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        fetchCount += 1
        let outcome: Result
        if results.isEmpty {
            outcome = fallbackResult
        } else {
            outcome = results.removeFirst()
        }

        switch outcome {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}

private actor DeferredCloudImporter: ProfileCloudImporting {
    enum DeferredResult {
        case success(CloudProfileSnapshot?)
        case failure(Error)
    }

    private var continuation: CheckedContinuation<CloudProfileSnapshot?, Error>?

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForRequest() async {
        while continuation == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func resume(with result: DeferredResult) {
        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case let .success(snapshot):
            continuation.resume(returning: snapshot)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
