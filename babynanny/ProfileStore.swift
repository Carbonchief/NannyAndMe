import Foundation
import SwiftUI

struct ChildProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date
    var imageData: Data?
    var remindersEnabled: Bool
    var actionReminderIntervals: [BabyActionCategory: TimeInterval]
    var actionRemindersEnabled: [BabyActionCategory: Bool]

    init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        imageData: Data? = nil,
        remindersEnabled: Bool = false,
        actionReminderIntervals: [BabyActionCategory: TimeInterval] = ChildProfile.defaultActionReminderIntervals(),
        actionRemindersEnabled: [BabyActionCategory: Bool] = ChildProfile.defaultActionRemindersEnabled()
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.imageData = imageData
        self.remindersEnabled = remindersEnabled
        self.actionReminderIntervals = actionReminderIntervals
        self.actionRemindersEnabled = actionRemindersEnabled
        normalizeReminderPreferences()
    }

    var displayName: String {
        name.isEmpty ? L10n.Profile.newProfile : name
    }

    func ageDescription(referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let now = max(referenceDate, birthDate)
        var components = calendar.dateComponents([.year, .month, .day], from: birthDate, to: now)

        let years = max(components.year ?? 0, 0)
        let months = max(components.month ?? 0, 0)
        let days = max(components.day ?? 0, 0)

        if years <= 0 && months <= 0 && days <= 0 {
            return L10n.Profiles.ageNewborn
        }

        components.year = years
        components.month = months
        components.day = days

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2

        if years > 0 {
            formatter.allowedUnits = [.year, .month]
        } else if months > 0 {
            formatter.allowedUnits = [.month, .day]
        } else {
            formatter.allowedUnits = [.day]
        }

        if let formatted = formatter.string(from: components), formatted.isEmpty == false {
            return L10n.Profiles.ageDescription(formatted)
        }

        return L10n.Profiles.ageNewborn
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case birthDate
        case imageData
        case remindersEnabled
        case actionReminderIntervals
        case actionRemindersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        birthDate = try container.decode(Date.self, forKey: .birthDate)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        if let rawIntervals = try container.decodeIfPresent([String: TimeInterval].self, forKey: .actionReminderIntervals) {
            let mapped = rawIntervals.reduce(into: [BabyActionCategory: TimeInterval]()) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = max(0, value)
                }
            }
            actionReminderIntervals = mapped
        } else {
            actionReminderIntervals = Self.defaultActionReminderIntervals()
        }
        if let rawEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .actionRemindersEnabled) {
            let mapped = rawEnabled.reduce(into: [BabyActionCategory: Bool]()) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = value
                }
            }
            actionRemindersEnabled = mapped
        } else {
            actionRemindersEnabled = Self.defaultActionRemindersEnabled()
        }
        normalizeReminderPreferences()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        let rawIntervals = Dictionary(uniqueKeysWithValues: actionReminderIntervals.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawIntervals, forKey: .actionReminderIntervals)
        let rawEnabled = Dictionary(uniqueKeysWithValues: actionRemindersEnabled.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawEnabled, forKey: .actionRemindersEnabled)
    }

    func reminderInterval(for category: BabyActionCategory) -> TimeInterval {
        actionReminderIntervals[category] ?? Self.defaultActionReminderInterval
    }

    mutating func setReminderInterval(_ interval: TimeInterval, for category: BabyActionCategory) {
        actionReminderIntervals[category] = max(0, interval)
        normalizeReminderPreferences()
    }

    func isActionReminderEnabled(for category: BabyActionCategory) -> Bool {
        actionRemindersEnabled[category] ?? true
    }

    mutating func setReminderEnabled(_ isEnabled: Bool, for category: BabyActionCategory) {
        actionRemindersEnabled[category] = isEnabled
        normalizeReminderPreferences()
    }

    mutating func normalizeReminderPreferences() {
        for category in BabyActionCategory.allCases {
            if let value = actionReminderIntervals[category], value > 0 {
                continue
            }
            actionReminderIntervals[category] = Self.defaultActionReminderInterval
            if actionRemindersEnabled[category] == nil {
                actionRemindersEnabled[category] = true
            }
        }

        for category in BabyActionCategory.allCases where actionRemindersEnabled[category] == nil {
            actionRemindersEnabled[category] = true
        }
    }

    static var defaultActionReminderInterval: TimeInterval { 3 * 60 * 60 }

    static func defaultActionReminderIntervals() -> [BabyActionCategory: TimeInterval] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, defaultActionReminderInterval) })
    }

    static func defaultActionRemindersEnabled() -> [BabyActionCategory: Bool] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, true) })
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
    private weak var actionStore: ActionLogStore?
    struct ActionReminderSummary: Equatable, Sendable {
        let fireDate: Date
        let message: String
    }
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

    func registerActionStore(_ store: ActionLogStore) {
        actionStore = store
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

    enum ShareDataError: LocalizedError {
        case mismatchedProfile

        var errorDescription: String? {
            switch self {
            case .mismatchedProfile:
                return L10n.ShareData.Error.mismatchedProfile
            }
        }
    }

    @discardableResult
    func mergeActiveProfile(with importedProfile: ChildProfile) throws -> Bool {
        if state.profiles.contains(where: { $0.id == importedProfile.id }) == false {
            var newState = state
            newState.profiles.append(importedProfile)
            newState.activeProfileID = importedProfile.id
            state = Self.sanitized(state: newState)
            return true
        }

        guard let activeID = state.activeProfileID else { return false }

        guard importedProfile.id == activeID else {
            throw ShareDataError.mismatchedProfile
        }

        let currentProfile = activeProfile

        guard currentProfile != importedProfile else { return false }

        updateActiveProfile { profile in
            profile = importedProfile
        }

        return true
    }

    enum ReminderAuthorizationResult: Equatable {
        case enabled
        case disabled
        case authorizationDenied
    }

    enum ReminderPreviewResult: Equatable {
        case scheduled
        case authorizationDenied
        case disabled
    }

    @discardableResult
    func setRemindersEnabled(_ isEnabled: Bool) async -> ReminderAuthorizationResult {
        var desiredValue = isEnabled
        var result: ReminderAuthorizationResult = isEnabled ? .enabled : .disabled

        if isEnabled {
            let authorized = await reminderScheduler.ensureAuthorization()
            if authorized == false {
                desiredValue = false
                result = .authorizationDenied
            }
        }

        updateActiveProfile { $0.remindersEnabled = desiredValue }
        return result
    }

    func nextReminder(for profileID: UUID) async -> ReminderOverview? {
        let profiles = state.profiles
        let actionStates = actionStore?.actionStatesSnapshot ?? [:]
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, actionStates: actionStates, reference: Date())
        return reminders.first(where: { $0.includes(profileID: profileID) })
    }

    func nextActionReminderSummaries(for profileID: UUID) async -> [BabyActionCategory: ActionReminderSummary] {
        let profiles = state.profiles
        let actionStates = actionStore?.actionStatesSnapshot ?? [:]
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, actionStates: actionStates, reference: Date())

        var summaries: [BabyActionCategory: ActionReminderSummary] = [:]

        for overview in reminders {
            guard case let .action(category) = overview.category else { continue }
            guard overview.includes(profileID: profileID) else { continue }
            guard let message = overview.message(for: profileID) else { continue }

            let summary = ActionReminderSummary(fireDate: overview.fireDate, message: message)
            if let existing = summaries[category], existing.fireDate <= summary.fireDate {
                continue
            }

            summaries[category] = summary
        }

        return summaries
    }

    func scheduleActionReminderPreview(for category: BabyActionCategory, delay: TimeInterval = 60) async -> ReminderPreviewResult {
        guard let profile = state.activeProfile else { return .disabled }
        guard profile.remindersEnabled, profile.isActionReminderEnabled(for: category) else { return .disabled }

        let scheduled = await reminderScheduler.schedulePreviewReminder(
            for: profile,
            category: category,
            delay: delay
        )

        return scheduled ? .scheduled : .authorizationDenied
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
        let actionStates = actionStore?.actionStatesSnapshot ?? [:]
        Task {
            await reminderScheduler.refreshReminders(for: profiles, actionStates: actionStates)
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

        state.profiles = state.profiles.map { profile in
            var normalized = profile
            normalized.normalizeReminderPreferences()
            return normalized
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
            func refreshReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState]) async {}
            func upcomingReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState], reference: Date) async -> [ReminderOverview] {
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

            func schedulePreviewReminder(for profile: ChildProfile,
                                         category: BabyActionCategory,
                                         delay _: TimeInterval) async -> Bool {
                true
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
