import Foundation
import SwiftUI

struct ChildProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date
    var imageData: Data?
    var remindersEnabled: Bool
    struct ActionReminderOverride: Codable, Equatable, Sendable {
        var fireDate: Date
        var isOneOff: Bool
    }

    var actionReminderIntervals: [BabyActionCategory: TimeInterval]
    var actionRemindersEnabled: [BabyActionCategory: Bool]
    var actionReminderOverrides: [BabyActionCategory: ActionReminderOverride]

    init(
        id: UUID = UUID(),
        name: String,
        birthDate: Date,
        imageData: Data? = nil,
        remindersEnabled: Bool = false,
        actionReminderIntervals: [BabyActionCategory: TimeInterval] = ChildProfile.defaultActionReminderIntervals(),
        actionRemindersEnabled: [BabyActionCategory: Bool] = ChildProfile.defaultActionRemindersEnabled(),
        actionReminderOverrides: [BabyActionCategory: ActionReminderOverride] = [:]
    ) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.imageData = imageData
        self.remindersEnabled = remindersEnabled
        self.actionReminderIntervals = actionReminderIntervals
        self.actionRemindersEnabled = actionRemindersEnabled
        self.actionReminderOverrides = actionReminderOverrides
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
        case actionReminderOverrides
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

        if let rawOverrides = try container.decodeIfPresent([String: ActionReminderOverride].self,
                                                            forKey: .actionReminderOverrides) {
            let mapped = rawOverrides.reduce(into: [BabyActionCategory: ActionReminderOverride]()) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = value
                }
            }
            actionReminderOverrides = mapped
        } else {
            actionReminderOverrides = [:]
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
        let rawOverrides = Dictionary(uniqueKeysWithValues: actionReminderOverrides.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawOverrides, forKey: .actionReminderOverrides)
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

        pruneActionReminderOverrides()
    }

    static var defaultActionReminderInterval: TimeInterval { 3 * 60 * 60 }

    static func defaultActionReminderIntervals() -> [BabyActionCategory: TimeInterval] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, defaultActionReminderInterval) })
    }

    static func defaultActionRemindersEnabled() -> [BabyActionCategory: Bool] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, true) })
    }
}

extension ChildProfile {
    mutating func setActionReminderOverride(_ override: ActionReminderOverride?,
                                            for category: BabyActionCategory,
                                            referenceDate: Date = Date()) {
        if let override {
            actionReminderOverrides[category] = override
        } else {
            actionReminderOverrides.removeValue(forKey: category)
        }
        pruneActionReminderOverrides(referenceDate: referenceDate)
    }

    func actionReminderOverride(for category: BabyActionCategory) -> ActionReminderOverride? {
        actionReminderOverrides[category]
    }

    mutating func pruneActionReminderOverrides(referenceDate: Date = Date()) {
        actionReminderOverrides = actionReminderOverrides.filter { _, override in
            override.fireDate > referenceDate
        }
    }

    mutating func clearActionReminderOverride(for category: BabyActionCategory) {
        actionReminderOverrides.removeValue(forKey: category)
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

        if shouldEnsureProfileExists {
            ensureValidState()
            if let profile = state.activeProfile {
                return profile
            }
        }

        return ChildProfile(name: "", birthDate: Date())
    }

    var showRecentActivityOnHome: Bool {
        state.showRecentActivityOnHome
    }

    private let saveURL: URL
    private let reminderScheduler: ReminderScheduling
    private var cloudImporter: ProfileCloudImporting?
    private var initialCloudImportTask: Task<Void, Never>?
    private weak var actionStore: ActionLogStore?
    private let didLoadProfilesFromDisk: Bool
    private var shouldEnsureProfileExists: Bool {
        didLoadProfilesFromDisk || cloudImporter == nil || isAwaitingInitialCloudImport == false
    }
    struct ActionReminderSummary: Equatable, Sendable {
        let fireDate: Date
        let message: String
    }

    static let customReminderDelayRange: ClosedRange<TimeInterval> = (5 * 60)...(24 * 60 * 60)

    struct ProfileMetadataUpdate: Equatable, Sendable {
        let id: UUID
        let name: String
        let birthDate: Date?
        let imageData: Data?
    }
    @Published private var state: ProfileState {
        didSet {
            persistState()
            scheduleReminders()
            synchronizeProfileMetadata()
        }
    }

    @Published private(set) var isAwaitingInitialCloudImport: Bool

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json",
        reminderScheduler: ReminderScheduling = UserNotificationReminderScheduler(),
        cloudImporter: ProfileCloudImporting? = CloudKitProfileImporter()
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler
        self.cloudImporter = cloudImporter
        self.didLoadProfilesFromDisk = fileManager.fileExists(atPath: saveURL.path)
        self.isAwaitingInitialCloudImport = (didLoadProfilesFromDisk == false && cloudImporter != nil)

        if let data = try? Data(contentsOf: saveURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode(ProfileState.self, from: data) {
                self.state = Self.sanitized(state: decoded, ensureProfileExists: true)
            } else {
                self.state = Self.defaultState()
            }
        } else {
            let shouldCreateBootstrapProfile = didLoadProfilesFromDisk || cloudImporter == nil
            self.state = Self.sanitized(state: nil, ensureProfileExists: shouldCreateBootstrapProfile)
        }

        persistState()
        scheduleReminders()

        scheduleInitialCloudImport()
    }

    init(
        initialProfiles: [ChildProfile],
        activeProfileID: UUID? = nil,
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json",
        reminderScheduler: ReminderScheduling = UserNotificationReminderScheduler(),
        cloudImporter: ProfileCloudImporting? = nil
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler
        self.cloudImporter = cloudImporter
        self.didLoadProfilesFromDisk = true
        self.isAwaitingInitialCloudImport = false
        let state = ProfileState(profiles: initialProfiles, activeProfileID: activeProfileID)
        self.state = Self.sanitized(state: state, ensureProfileExists: true)
        persistState()
        scheduleReminders()
    }

    func registerActionStore(_ store: ActionLogStore) {
        actionStore = store
        scheduleReminders()
        store.synchronizeProfileMetadata(state.profiles)
    }

    func setActiveProfile(_ profile: ChildProfile) {
        guard state.profiles.contains(where: { $0.id == profile.id }) else { return }
        var newState = state
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState, ensureProfileExists: true)
    }

    func addProfile(name: String, imageData: Data? = nil) {
        var newState = state
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ChildProfile(name: trimmedName, birthDate: Date(), imageData: imageData)
        newState.profiles.append(profile)
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState, ensureProfileExists: true)
    }

    func addProfile() {
        addProfile(name: "")
    }

    func setShowRecentActivityOnHome(_ newValue: Bool) {
        var newState = state
        newState.showRecentActivityOnHome = newValue
        state = Self.sanitized(state: newState, ensureProfileExists: true)
    }

    func deleteProfile(_ profile: ChildProfile) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }

        var newState = state
        newState.profiles.remove(at: index)

        if newState.activeProfileID == profile.id {
            if index < newState.profiles.count {
                newState.activeProfileID = newState.profiles[index].id
            } else {
                newState.activeProfileID = newState.profiles.last?.id
            }
        }

        state = Self.sanitized(state: newState, ensureProfileExists: true)
        actionStore?.removeProfileData(for: profile.id)
    }

    func updateActiveProfile(_ updates: (inout ChildProfile) -> Void) {
        guard let activeID = state.activeProfileID,
              let index = state.profiles.firstIndex(where: { $0.id == activeID }) else { return }

        var newState = state
        updates(&newState.profiles[index])
        state = Self.sanitized(state: newState, ensureProfileExists: true)
    }

    func updateProfile(withID id: UUID, updates: (inout ChildProfile) -> Void) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }

        var newState = state
        updates(&newState.profiles[index])
        state = Self.sanitized(state: newState, ensureProfileExists: true)
    }

    func applyMetadataUpdates(_ updates: [ProfileMetadataUpdate]) {
        guard updates.isEmpty == false else { return }

        var newState = state
        var didChange = false
        var insertedProfiles: [ChildProfile] = []

        for update in updates {
            guard let index = newState.profiles.firstIndex(where: { $0.id == update.id }) else { continue }
            var profile = newState.profiles[index]
            let trimmedName = update.name.trimmingCharacters(in: .whitespacesAndNewlines)

            if profile.name != trimmedName {
                profile.name = trimmedName
                didChange = true
            }

            if profile.imageData != update.imageData {
                profile.imageData = update.imageData
                didChange = true
            }

            if let birthDate = update.birthDate, profile.birthDate != birthDate {
                profile.birthDate = birthDate
                didChange = true
            }

            newState.profiles[index] = profile
        }

        let existingIDs = Set(newState.profiles.map { $0.id })
        for update in updates where existingIDs.contains(update.id) == false {
            let trimmedName = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let birthDate = update.birthDate ?? Date()
            var profile = ChildProfile(id: update.id,
                                       name: trimmedName,
                                       birthDate: birthDate,
                                       imageData: update.imageData)
            profile.normalizeReminderPreferences()
            insertedProfiles.append(profile)
        }

        if insertedProfiles.isEmpty == false {
            newState.profiles.append(contentsOf: insertedProfiles)
            if newState.activeProfileID == nil {
                newState.activeProfileID = insertedProfiles.first?.id ?? newState.profiles.first?.id
            }
            didChange = true
        }

        if didChange {
            state = Self.sanitized(state: newState, ensureProfileExists: true)
        }
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
            state = Self.sanitized(state: newState, ensureProfileExists: true)
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
        let actionStates = await actionStore?.actionStatesSnapshot() ?? [:]
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, actionStates: actionStates, reference: Date())
        return reminders.first(where: { $0.includes(profileID: profileID) })
    }

    func nextActionReminderSummaries(for profileID: UUID) async -> [BabyActionCategory: ActionReminderSummary] {
        let profiles = state.profiles
        let actionStates = await actionStore?.actionStatesSnapshot() ?? [:]
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

    func nextActionReminderSummary(for profileID: UUID, category targetCategory: BabyActionCategory) async -> ActionReminderSummary? {
        let profiles = state.profiles
        let actionStates = await actionStore?.actionStatesSnapshot() ?? [:]
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, actionStates: actionStates, reference: Date())

        var bestSummary: ActionReminderSummary?

        for overview in reminders {
            guard case let .action(category) = overview.category, category == targetCategory else { continue }
            guard overview.includes(profileID: profileID) else { continue }
            guard let message = overview.message(for: profileID) else { continue }

            let summary = ActionReminderSummary(fireDate: overview.fireDate, message: message)

            if let existing = bestSummary, existing.fireDate <= summary.fireDate {
                continue
            }

            bestSummary = summary
        }

        return bestSummary
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

    func scheduleCustomActionReminder(for category: BabyActionCategory,
                                      delay: TimeInterval,
                                      isOneOff: Bool) {
        let clampedDelay = Self.clampCustomReminderDelay(delay)
        let fireDate = Date().addingTimeInterval(clampedDelay)

        updateActiveProfile { profile in
            profile.setActionReminderOverride(
                ChildProfile.ActionReminderOverride(fireDate: fireDate, isOneOff: isOneOff),
                for: category,
                referenceDate: Date()
            )
        }
    }

    func clearActionReminderOverride(for profileID: UUID, category: BabyActionCategory) {
        updateProfile(withID: profileID) { profile in
            profile.clearActionReminderOverride(for: category)
        }
    }

    func actionLogged(for profileID: UUID, category: BabyActionCategory) {
        clearActionReminderOverride(for: profileID, category: category)
    }

    private static func clampCustomReminderDelay(_ delay: TimeInterval) -> TimeInterval {
        let range = customReminderDelayRange
        return min(max(delay, range.lowerBound), range.upperBound)
    }

    private func ensureValidState() {
        let sanitized = Self.sanitized(state: state, ensureProfileExists: shouldEnsureProfileExists)
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
        Task { @MainActor [weak self, profiles] in
            guard let self else { return }
            let actionStates = await self.actionStore?.actionStatesSnapshot() ?? [:]
            await self.reminderScheduler.refreshReminders(for: profiles, actionStates: actionStates)
        }
    }

    private func synchronizeProfileMetadata() {
        actionStore?.synchronizeProfileMetadata(state.profiles)
    }

    private func scheduleInitialCloudImport() {
        guard initialCloudImportTask == nil else { return }
        guard let cloudImporter else { return }

        initialCloudImportTask = Task { [weak self] in
            guard let self else { return }
            await self.performInitialCloudImport(using: cloudImporter)
        }
    }

    private func performInitialCloudImport(using importer: ProfileCloudImporting) async {
        defer {
            finishInitialCloudImport()
        }
        defer { initialCloudImportTask = nil }

        let maxRetryAttempts = 5
        var retryAttempt = 0

        while true {
            do {
                guard let snapshot = try await importer.fetchProfileSnapshot() else {
                    if shouldRetry() {
                        await scheduleRetry()
                        continue
                    }
                    return
                }

                let currentState = Self.sanitized(state: state, ensureProfileExists: shouldEnsureProfileExists)
                let importedState = Self.sanitized(state: ProfileState(
                    profiles: snapshot.profiles,
                    activeProfileID: snapshot.activeProfileID,
                    showRecentActivityOnHome: snapshot.showRecentActivityOnHome
                ), ensureProfileExists: true)

                guard importedState.profiles.isEmpty == false else { return }

                let mergedState = merged(localState: currentState, remoteState: importedState)

                guard mergedState != currentState else { return }

                state = mergedState
                return
            } catch let CloudProfileImportError.recoverable(error) {
                if shouldRetry() {
                    #if DEBUG
                    print("Recoverable CloudKit import error: \(error.localizedDescription). Retrying...")
                    #endif
                    await scheduleRetry()
                    continue
                }
                #if DEBUG
                print("Failed to import CloudKit profiles: \(error.localizedDescription)")
                #endif
                return
            } catch {
                #if DEBUG
                print("Failed to import CloudKit profiles: \(error.localizedDescription)")
                #endif
                return
            }
        }

        func shouldRetry() -> Bool {
            guard isBootstrapState(state) else { return false }
            guard retryAttempt < maxRetryAttempts else { return false }
            retryAttempt += 1
            return true
        }

        func scheduleRetry() async {
            let baseDelay: Double = 0.25
            let exponentialDelay = min(1.0, baseDelay * pow(2.0, Double(max(retryAttempt - 1, 0))))
            let nanoseconds = UInt64(exponentialDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    private func finishInitialCloudImport() {
        if isAwaitingInitialCloudImport {
            isAwaitingInitialCloudImport = false
            ensureValidState()
        }
    }

    func updateCloudImporter(_ importer: ProfileCloudImporting?) {
        if importer == nil {
            initialCloudImportTask?.cancel()
            initialCloudImportTask = nil
            cloudImporter = nil
            finishInitialCloudImport()
            return
        }

        cloudImporter = importer
        isAwaitingInitialCloudImport = true
        initialCloudImportTask?.cancel()
        initialCloudImportTask = nil
        scheduleInitialCloudImport()
    }

    private func merged(localState: ProfileState, remoteState: ProfileState) -> ProfileState {
        if didLoadProfilesFromDisk == false && isBootstrapState(localState) {
            return Self.sanitized(state: remoteState, ensureProfileExists: true)
        }

        let remoteProfilesByID = Dictionary(uniqueKeysWithValues: remoteState.profiles.map { ($0.id, $0) })
        let localIDs = Set(localState.profiles.map { $0.id })

        var combinedProfiles: [ChildProfile] = localState.profiles.map { profile in
            if let remoteProfile = remoteProfilesByID[profile.id] {
                return remoteProfile
            }
            return profile
        }

        for profile in remoteState.profiles where localIDs.contains(profile.id) == false {
            combinedProfiles.append(profile)
        }

        var mergedState = ProfileState(
            profiles: combinedProfiles,
            activeProfileID: remoteState.activeProfileID ?? localState.activeProfileID,
            showRecentActivityOnHome: remoteState.showRecentActivityOnHome
        )

        if let activeID = mergedState.activeProfileID,
           combinedProfiles.contains(where: { $0.id == activeID }) == false {
            if let localActiveID = localState.activeProfileID,
               combinedProfiles.contains(where: { $0.id == localActiveID }) {
                mergedState.activeProfileID = localActiveID
            } else {
                mergedState.activeProfileID = combinedProfiles.first?.id
            }
        }

        return Self.sanitized(state: mergedState, ensureProfileExists: true)
    }

    private func isBootstrapState(_ state: ProfileState) -> Bool {
        if state.profiles.isEmpty {
            return true
        }

        guard state.profiles.count == 1 else { return false }
        guard let profile = state.profiles.first else { return false }

        if profile.name.isEmpty == false { return false }
        if profile.imageData != nil { return false }
        if profile.remindersEnabled { return false }
        if profile.actionReminderIntervals != ChildProfile.defaultActionReminderIntervals() { return false }
        if profile.actionRemindersEnabled != ChildProfile.defaultActionRemindersEnabled() { return false }

        return true
    }

    private static func sanitized(state: ProfileState?, ensureProfileExists: Bool) -> ProfileState {
        var state = state ?? ProfileState(profiles: [], activeProfileID: nil)

        if state.profiles.isEmpty {
            if ensureProfileExists {
                let defaultProfile = ChildProfile(name: "", birthDate: Date())
                state.profiles = [defaultProfile]
                state.activeProfileID = defaultProfile.id
            }
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
        sanitized(state: nil, ensureProfileExists: true)
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
    var showRecentActivityOnHome: Bool = true

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
