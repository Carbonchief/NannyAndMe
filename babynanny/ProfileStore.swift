import Foundation
import SwiftUI

struct ChildProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date
    var imageData: Data?
    var remindersEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        imageData: Data? = nil,
        remindersEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.imageData = imageData
        self.remindersEnabled = remindersEnabled
    }

    var displayName: String {
        name.isEmpty ? L10n.Profile.newProfile : name
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case birthDate
        case imageData
        case remindersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        birthDate = try container.decode(Date.self, forKey: .birthDate)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    var profiles: [ChildProfile] {
        state.profiles
    }

    var activeProfileID: UUID? {
        state.activeProfileID
    }

    var activeProfile: ChildProfile {
        if let profile = state.activeProfile {
            return profile
        }

        ensureValidState()
        return state.activeProfile ?? ChildProfile(name: "", birthDate: Date())
    }

    private let saveURL: URL
    private let reminderScheduler: ReminderScheduling
    @Published private var state: ProfileState {
        didSet {
            persistState()
            scheduleReminders()
        }
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json",
        reminderScheduler: ReminderScheduling = UserNotificationReminderScheduler()
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler

        if let data = try? Data(contentsOf: saveURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode(ProfileState.self, from: data) {
                self.state = Self.sanitized(state: decoded)
            } else {
                self.state = Self.defaultState()
            }
        } else {
            self.state = Self.defaultState()
        }

        persistState()
        scheduleReminders()
    }

    init(
        initialProfiles: [ChildProfile],
        activeProfileID: UUID? = nil,
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json",
        reminderScheduler: ReminderScheduling = UserNotificationReminderScheduler()
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler
        let state = ProfileState(profiles: initialProfiles, activeProfileID: activeProfileID)
        self.state = Self.sanitized(state: state)
        persistState()
        scheduleReminders()
    }

    func setActiveProfile(_ profile: ChildProfile) {
        guard state.profiles.contains(where: { $0.id == profile.id }) else { return }
        var newState = state
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState)
    }

    func addProfile() {
        var newState = state
        let profile = ChildProfile(name: "", birthDate: Date())
        newState.profiles.append(profile)
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState)
    }

    func deleteProfile(_ profile: ChildProfile) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        var newState = state
        newState.profiles.remove(at: index)

        if newState.activeProfileID == profile.id {
            newState.activeProfileID = newState.profiles.first?.id
        }

        state = Self.sanitized(state: newState)
    }

    func updateActiveProfile(_ updates: (inout ChildProfile) -> Void) {
        guard let activeID = state.activeProfileID,
              let index = state.profiles.firstIndex(where: { $0.id == activeID }) else { return }

        var newState = state
        updates(&newState.profiles[index])
        state = Self.sanitized(state: newState)
    }

    func setRemindersEnabled(_ isEnabled: Bool) async {
        var desiredValue = isEnabled

        if isEnabled {
            let authorized = await reminderScheduler.ensureAuthorization()
            if authorized == false {
                desiredValue = false
            }
        }

        updateActiveProfile { $0.remindersEnabled = desiredValue }
    }

    func nextReminder(for profileID: UUID) async -> ReminderOverview? {
        let profiles = state.profiles
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, reference: Date())
        return reminders.first(where: { $0.includes(profileID: profileID) })
    }

    private func ensureValidState() {
        let sanitized = Self.sanitized(state: state)
        if sanitized != state {
            state = sanitized
        }
    }

    private func persistState() {
        let stateSnapshot = state
        let url = saveURL

        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(stateSnapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to save child profiles: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func scheduleReminders() {
        let profiles = state.profiles
        Task {
            await reminderScheduler.refreshReminders(for: profiles)
        }
    }

    private static func sanitized(state: ProfileState?) -> ProfileState {
        var state = state ?? ProfileState(profiles: [], activeProfileID: nil)

        if state.profiles.isEmpty {
            let defaultProfile = ChildProfile(name: "", birthDate: Date())
            state.profiles = [defaultProfile]
            state.activeProfileID = defaultProfile.id
        } else if let activeID = state.activeProfileID,
                  state.profiles.contains(where: { $0.id == activeID }) == false {
            state.activeProfileID = state.profiles.first?.id
        } else if state.activeProfileID == nil {
            state.activeProfileID = state.profiles.first?.id
        }

        return state
    }

    private static func defaultState() -> ProfileState {
        sanitized(state: nil)
    }

    private static func resolveSaveURL(fileManager: FileManager, directory: URL?, filename: String) -> URL {
        if let directory {
            return directory.appendingPathComponent(filename)
        }

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent(filename)
        }

        return fileManager.temporaryDirectory.appendingPathComponent(filename)
    }
}

private struct ProfileState: Codable, Equatable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?

    var activeProfile: ChildProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first(where: { $0.id == activeProfileID })
    }
}

extension ProfileStore {
    static var preview: ProfileStore {
        struct PreviewReminderScheduler: ReminderScheduling {
            func ensureAuthorization() async -> Bool { true }
            func refreshReminders(for profiles: [ChildProfile]) async {}
            func upcomingReminders(for profiles: [ChildProfile], reference: Date) async -> [ReminderOverview] {
                let enabledProfiles = profiles.filter { $0.remindersEnabled }
                guard let profile = enabledProfiles.first else { return [] }

                let entry = ReminderOverview.Entry(
                    profileID: profile.id,
                    message: L10n.Notifications.ageReminderMessage(profile.displayName, 1)
                )

                return [
                    ReminderOverview(
                        identifier: UUID().uuidString,
                        category: .ageMilestone,
                        fireDate: reference.addingTimeInterval(3600),
                        entries: [entry]
                    )
                ]
            }
        }

        let profiles = [
            ChildProfile(
                name: "Aria",
                birthDate: Date(timeIntervalSince1970: 1_600_000_000),
                remindersEnabled: true
            ),
            ChildProfile(name: "Luca", birthDate: Date(timeIntervalSince1970: 1_650_000_000))
        ]

        return ProfileStore(
            initialProfiles: profiles,
            activeProfileID: profiles.first?.id,
            directory: FileManager.default.temporaryDirectory,
            filename: "previewChildProfiles.json",
            reminderScheduler: PreviewReminderScheduler()
        )
    }
}
