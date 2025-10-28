import Foundation
import SwiftData
import SwiftUI

enum ProfileNavigationDirection: Sendable {
    case next
    case previous
}

struct ChildProfile: Identifiable, Equatable, Codable, Sendable {
    struct ActionReminderOverride: Codable, Equatable, Sendable {
        var fireDate: Date
        var isOneOff: Bool
    }

    var id: UUID
    var name: String
    var birthDate: Date
    var imageData: Data?
    var remindersEnabled: Bool
    private var actionReminderIntervals: [BabyActionCategory: TimeInterval]
    private var actionRemindersEnabled: [BabyActionCategory: Bool]
    private var actionReminderOverrides: [BabyActionCategory: ActionReminderOverride]

    init(id: UUID = UUID(),
         name: String,
         birthDate: Date,
         imageData: Data? = nil,
         remindersEnabled: Bool = false,
         actionReminderIntervals: [BabyActionCategory: TimeInterval] = ChildProfile.defaultActionReminderIntervals(),
         actionRemindersEnabled: [BabyActionCategory: Bool] = ChildProfile.defaultActionRemindersEnabled(),
         actionReminderOverrides: [BabyActionCategory: ActionReminderOverride] = [:]) {
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

    init(model: ProfileActionStateModel, referenceDate: Date = Date()) {
        let overrides = model.reminderOverridesByCategory(referenceDate: referenceDate)
        let mappedOverrides = overrides.reduce(into: [BabyActionCategory: ActionReminderOverride]()) { partialResult, element in
            let (category, value) = element
            partialResult[category] = ActionReminderOverride(fireDate: value.fireDate, isOneOff: value.isOneOff)
        }

        self.init(id: model.resolvedProfileID,
                  name: model.name ?? "",
                  birthDate: model.birthDate ?? Date(),
                  imageData: model.imageData,
                  remindersEnabled: model.remindersEnabled,
                  actionReminderIntervals: model.reminderIntervalsByCategory(),
                  actionRemindersEnabled: model.reminderEnabledByCategory(),
                  actionReminderOverrides: mappedOverrides)
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

    func reminderInterval(for category: BabyActionCategory) -> TimeInterval {
        actionReminderIntervals[category] ?? Self.defaultActionReminderInterval
    }

    func isActionReminderEnabled(for category: BabyActionCategory) -> Bool {
        actionRemindersEnabled[category] ?? true
    }

    func actionReminderOverride(for category: BabyActionCategory) -> ActionReminderOverride? {
        actionReminderOverrides[category]
    }

    var reminderOverridesByCategory: [BabyActionCategory: ActionReminderOverride] {
        actionReminderOverrides
    }

    mutating func setReminderInterval(_ interval: TimeInterval, for category: BabyActionCategory) {
        actionReminderIntervals[category] = max(0, interval)
        normalizeReminderPreferences()
    }

    mutating func setReminderEnabled(_ isEnabled: Bool, for category: BabyActionCategory) {
        actionRemindersEnabled[category] = isEnabled
        normalizeReminderPreferences()
    }

    mutating func setActionReminderOverride(_ override: ActionReminderOverride?,
                                             for category: BabyActionCategory,
                                             referenceDate: Date = Date()) {
        if let override {
            actionReminderOverrides[category] = override
        } else {
            actionReminderOverrides.removeValue(forKey: category)
        }
        normalizeReminderPreferences(referenceDate: referenceDate)
    }

    mutating func clearActionReminderOverride(for category: BabyActionCategory) {
        actionReminderOverrides.removeValue(forKey: category)
    }

    mutating func normalizeReminderPreferences(referenceDate: Date = Date()) {
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

        actionReminderOverrides = actionReminderOverrides.filter { _, override in
            override.fireDate > referenceDate
        }
    }

    static var defaultActionReminderInterval: TimeInterval { 3 * 60 * 60 }

    static func defaultActionReminderIntervals() -> [BabyActionCategory: TimeInterval] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, defaultActionReminderInterval) })
    }

    static func defaultActionRemindersEnabled() -> [BabyActionCategory: Bool] {
        Dictionary(uniqueKeysWithValues: BabyActionCategory.allCases.map { ($0, true) })
    }

    static func placeholder() -> ChildProfile {
        ChildProfile(name: "", birthDate: Date())
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
            actionReminderIntervals = rawIntervals.reduce(into: [:]) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = max(0, value)
                }
            }
        } else {
            actionReminderIntervals = Self.defaultActionReminderIntervals()
        }

        if let rawEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .actionRemindersEnabled) {
            actionRemindersEnabled = rawEnabled.reduce(into: [:]) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = value
                }
            }
        } else {
            actionRemindersEnabled = Self.defaultActionRemindersEnabled()
        }

        if let rawOverrides = try container.decodeIfPresent([String: ActionReminderOverride].self,
                                                            forKey: .actionReminderOverrides) {
            actionReminderOverrides = rawOverrides.reduce(into: [:]) { partialResult, element in
                let (key, value) = element
                if let category = BabyActionCategory(rawValue: key) {
                    partialResult[category] = value
                }
            }
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
}

@MainActor
final class ProfileStore: ObservableObject {
    struct ActionReminderSummary: Equatable, Sendable {
        let fireDate: Date
        let message: String
    }

    struct ProfileMetadataUpdate: Equatable, Sendable {
        let id: UUID
        let name: String
        let birthDate: Date?
        let imageData: Data?
    }

    enum ShareDataError: LocalizedError, Sendable {
        case mismatchedProfile

        var errorDescription: String? {
            switch self {
            case .mismatchedProfile:
                return L10n.ShareData.Error.mismatchedProfile
            }
        }
    }

    enum ReminderAuthorizationResult: Equatable, Sendable {
        case enabled
        case disabled
        case authorizationDenied
    }

    enum ReminderPreviewResult: Equatable, Sendable {
        case scheduled
        case authorizationDenied
        case disabled
    }

    static let customReminderDelayRange: ClosedRange<TimeInterval> = (5 * 60)...(24 * 60 * 60)

    @Published private(set) var profiles: [ChildProfile] = [] {
        didSet {
            guard oldValue != profiles else { return }
            scheduleReminders()
            synchronizeProfileMetadata()
        }
    }

    @Published private(set) var activeProfileID: UUID? {
        didSet {
            guard oldValue != activeProfileID else { return }
            settings.activeProfileID = activeProfileID
            persistSettings(reason: "profile-active-id")
        }
    }

    @Published var showRecentActivityOnHome: Bool {
        didSet {
            guard oldValue != showRecentActivityOnHome else { return }
            settings.showRecentActivityOnHome = showRecentActivityOnHome
            persistSettings(reason: "profile-show-recent")
        }
    }

    var activeProfile: ChildProfile {
        if let activeID = activeProfileID,
           let profile = profiles.first(where: { $0.id == activeID }) {
            return profile
        }
        return profiles.first ?? ChildProfile.placeholder()
    }

    private let modelContext: ModelContext
    private let dataStack: AppDataStack
    private let reminderScheduler: ReminderScheduling
    private weak var actionStore: ActionLogStore?
    private let fileManager: FileManager
    private let saveURL: URL
    private var settings: ProfileStoreSettings
    private var isEnsuringProfile = false
    private struct NotificationObserverToken: @unchecked Sendable {
        let token: NSObjectProtocol
    }

    private let notificationCenter: NotificationCenter
    private var notificationObservers: [NotificationObserverToken] = []

    init(modelContext: ModelContext,
         dataStack: AppDataStack,
         notificationCenter: NotificationCenter = .default,
         fileManager: FileManager = .default,
         directory: URL? = nil,
         filename: String = "childProfiles.json",
         reminderScheduler: ReminderScheduling = UserNotificationReminderScheduler()) {
        self.modelContext = modelContext
        self.dataStack = dataStack
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler
        self.settings = Self.fetchOrCreateSettings(in: modelContext)
        self.showRecentActivityOnHome = settings.showRecentActivityOnHome
        self.activeProfileID = settings.activeProfileID

        migrateLegacyProfilesIfNeeded()
        refreshProfiles()
        ensureActiveProfileExists()
        scheduleReminders()
        observeSyncNotifications()
    }

    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer.token)
        }
    }

    func registerActionStore(_ store: ActionLogStore) {
        actionStore = store
        scheduleReminders()
        synchronizeProfileMetadata()
    }

    func setActiveProfile(_ profile: ChildProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        activeProfileID = profile.id
    }

    @discardableResult
    func cycleActiveProfile(direction: ProfileNavigationDirection) -> ChildProfile? {
        guard profiles.count > 1 else { return nil }
        guard let activeID = activeProfileID,
              let currentIndex = profiles.firstIndex(where: { $0.id == activeID }) else {
            if let first = profiles.first {
                setActiveProfile(first)
                return first
            }
            return nil
        }

        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (currentIndex + 1) % profiles.count
        case .previous:
            nextIndex = (currentIndex - 1 + profiles.count) % profiles.count
        }

        let targetProfile = profiles[nextIndex]
        setActiveProfile(targetProfile)
        return targetProfile
    }

    func addProfile(name: String, imageData: Data? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ProfileActionStateModel(name: trimmedName,
                                              birthDate: Date(),
                                              imageData: imageData)
        profile.normalizeReminderPreferences()
        modelContext.insert(profile)
        persistContextIfNeeded(reason: "profile-insert")
        refreshProfiles()
        activeProfileID = profile.resolvedProfileID
    }

    func addProfile() {
        addProfile(name: "")
    }

    func setShowRecentActivityOnHome(_ newValue: Bool) {
        showRecentActivityOnHome = newValue
    }

    func deleteProfile(_ profile: ChildProfile) {
        mutateProfiles(reason: "profile-delete") {
            guard let model = profileModel(withID: profile.id) else { return false }
            modelContext.delete(model)
            return true
        }

        if activeProfileID == profile.id {
            activeProfileID = profiles.first?.id
        }

        actionStore?.removeProfileData(for: profile.id)
    }

    func updateActiveProfile(_ updates: (ProfileActionStateModel) -> Void) {
        guard let activeID = activeProfileID else { return }
        updateProfile(withID: activeID, reason: "profile-update-active", updates: updates)
    }

    func updateProfile(withID id: UUID, reason: String = "profile-update", updates: (ProfileActionStateModel) -> Void) {
        mutateProfiles(reason: reason) {
            guard let model = profileModel(withID: id) else { return false }
            updates(model)
            model.normalizeReminderPreferences()
            return true
        }
    }

    func applyMetadataUpdates(_ updates: [ProfileMetadataUpdate]) {
        guard updates.isEmpty == false else { return }

        mutateProfiles(reason: "profile-metadata-update") {
            var didChange = false
            var insertedProfiles: [ProfileActionStateModel] = []

            for update in updates {
                if let model = profileModel(withID: update.id) {
                    let trimmedName = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if model.name != trimmedName {
                        model.name = trimmedName
                        didChange = true
                    }
                    if let birthDate = update.birthDate, model.birthDate != birthDate.normalizedToUTC() {
                        model.setBirthDate(birthDate)
                        didChange = true
                    }
                    if model.imageData != update.imageData {
                        model.imageData = update.imageData
                        didChange = true
                    }
                } else {
                    let trimmedName = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let birthDate = update.birthDate?.normalizedToUTC() ?? Date()
                    let model = ProfileActionStateModel(profileID: update.id,
                                                        name: trimmedName,
                                                        birthDate: birthDate,
                                                        imageData: update.imageData)
                    model.normalizeReminderPreferences()
                    modelContext.insert(model)
                    insertedProfiles.append(model)
                    didChange = true
                }
            }

            if insertedProfiles.isEmpty == false, activeProfileID == nil {
                activeProfileID = insertedProfiles.first?.resolvedProfileID
            }

            return didChange
        }
    }

    @discardableResult
    func mergeActiveProfile(with importedProfile: ChildProfile) throws -> Bool {
        if profiles.contains(where: { $0.id == importedProfile.id }) == false {
            var didInsert = false

            mutateProfiles(reason: "profile-import-insert") {
                let trimmedName = importedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let model = ProfileActionStateModel(profileID: importedProfile.id,
                                                    name: trimmedName,
                                                    birthDate: importedProfile.birthDate,
                                                    imageData: importedProfile.imageData,
                                                    remindersEnabled: importedProfile.remindersEnabled)

                for category in BabyActionCategory.allCases {
                    model.setReminderInterval(importedProfile.reminderInterval(for: category), for: category)
                    model.setReminderEnabled(importedProfile.isActionReminderEnabled(for: category), for: category)
                    if let override = importedProfile.actionReminderOverride(for: category) {
                        let mapped = ProfileActionReminderOverride(fireDate: override.fireDate, isOneOff: override.isOneOff)
                        model.setReminderOverride(mapped, for: category, referenceDate: Date())
                    } else {
                        model.clearReminderOverride(for: category)
                    }
                }

                model.normalizeReminderPreferences()
                modelContext.insert(model)
                didInsert = true
                return true
            }

            if didInsert {
                activeProfileID = importedProfile.id
            }

            return didInsert
        }

        guard let activeID = activeProfileID else { return false }

        guard importedProfile.id == activeID else {
            throw ShareDataError.mismatchedProfile
        }

        let currentProfile = activeProfile
        guard currentProfile != importedProfile else { return false }

        updateProfile(withID: activeID, reason: "profile-import-merge") { model in
            let trimmedName = importedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            model.name = trimmedName
            model.setBirthDate(importedProfile.birthDate)
            model.imageData = importedProfile.imageData
            model.remindersEnabled = importedProfile.remindersEnabled

            for category in BabyActionCategory.allCases {
                model.setReminderInterval(importedProfile.reminderInterval(for: category), for: category)
                model.setReminderEnabled(importedProfile.isActionReminderEnabled(for: category), for: category)

                if let override = importedProfile.actionReminderOverride(for: category) {
                    let mapped = ProfileActionReminderOverride(fireDate: override.fireDate, isOneOff: override.isOneOff)
                    model.setReminderOverride(mapped, for: category, referenceDate: Date())
                } else {
                    model.clearReminderOverride(for: category)
                }
            }
        }

        return true
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

        updateActiveProfile { model in
            model.remindersEnabled = desiredValue
        }

        return result
    }

    func ensureNotificationAuthorization() async -> Bool {
        await reminderScheduler.ensureAuthorization()
    }

    func nextReminder(for profileID: UUID) async -> ReminderOverview? {
        let actionStates = await actionStore?.actionStatesSnapshot() ?? [:]
        let reminders = await reminderScheduler.upcomingReminders(for: profiles, actionStates: actionStates, reference: Date())
        return reminders.first(where: { $0.includes(profileID: profileID) })
    }

    func nextActionReminderSummaries(for profileID: UUID) async -> [BabyActionCategory: ActionReminderSummary] {
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
        let profile = activeProfile
        guard profile.remindersEnabled, profile.isActionReminderEnabled(for: category) else { return .disabled }

        let scheduled = await reminderScheduler.schedulePreviewReminder(
            for: profile,
            category: category,
            delay: delay
        )

        return scheduled ? .scheduled : .authorizationDenied
    }

    func scheduleCustomActionReminder(for profileID: UUID,
                                      category: BabyActionCategory,
                                      delay: TimeInterval,
                                      isOneOff: Bool) {
        let clampedDelay = Self.clampCustomReminderDelay(delay)
        let fireDate = Date().addingTimeInterval(clampedDelay)

        updateProfile(withID: profileID, reason: "profile-custom-reminder") { model in
            let override = ProfileActionReminderOverride(fireDate: fireDate, isOneOff: isOneOff)
            model.setReminderOverride(override, for: category, referenceDate: Date())
        }
    }

    func clearActionReminderOverride(for profileID: UUID, category: BabyActionCategory) {
        updateProfile(withID: profileID, reason: "profile-clear-reminder") { model in
            model.clearReminderOverride(for: category)
        }
    }

    func actionLogged(for profileID: UUID, category: BabyActionCategory) {
        clearActionReminderOverride(for: profileID, category: category)
    }

    private func migrateLegacyProfilesIfNeeded() {
        guard fileManager.fileExists(atPath: saveURL.path) else { return }

        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let existingCount = (try? modelContext.fetch(descriptor).count) ?? 0
        guard existingCount == 0 else {
            try? fileManager.removeItem(at: saveURL)
            return
        }

        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let legacyState = try decoder.decode(LegacyProfileState.self, from: data)

            for legacy in legacyState.profiles {
                let model = ProfileActionStateModel(profileID: legacy.id,
                                                    name: legacy.name,
                                                    birthDate: legacy.birthDate,
                                                    imageData: legacy.imageData,
                                                    remindersEnabled: legacy.remindersEnabled)
                modelContext.insert(model)
                model.remindersEnabled = legacy.remindersEnabled
                for category in BabyActionCategory.allCases {
                    model.setReminderInterval(legacy.reminderInterval(for: category), for: category)
                    model.setReminderEnabled(legacy.isActionReminderEnabled(for: category), for: category)
                    if let override = legacy.actionReminderOverride(for: category) {
                        let mapped = ProfileActionReminderOverride(fireDate: override.fireDate, isOneOff: override.isOneOff)
                        model.setReminderOverride(mapped, for: category, referenceDate: Date())
                    }
                }
                model.normalizeReminderPreferences()
            }

            activeProfileID = legacyState.activeProfileID
            showRecentActivityOnHome = legacyState.showRecentActivityOnHome
            persistSettings(reason: "profile-migration-settings")
            persistContextIfNeeded(reason: "profile-migration")
            try? fileManager.removeItem(at: saveURL)
        } catch {
            #if DEBUG
            print("Failed to migrate legacy profiles: \(error.localizedDescription)")
            #endif
        }
    }

    private func refreshProfiles() {
        let sortDescriptors = [
            SortDescriptor(\ProfileActionStateModel.name),
            SortDescriptor(\ProfileActionStateModel.birthDate, order: .reverse)
        ]
        let descriptor = FetchDescriptor<ProfileActionStateModel>(sortBy: sortDescriptors)
        if let models = try? modelContext.fetch(descriptor) {
            profiles = models.map { ChildProfile(model: $0) }
        } else {
            profiles = []
        }
    }

    private func ensureActiveProfileExists() {
        if profiles.isEmpty {
            guard isEnsuringProfile == false else { return }
            isEnsuringProfile = true
            defer { isEnsuringProfile = false }

            let model = ProfileActionStateModel(name: "", birthDate: Date())
            model.normalizeReminderPreferences()
            modelContext.insert(model)
            persistContextIfNeeded(reason: "profile-ensure-default")
            refreshProfiles()
            activeProfileID = model.resolvedProfileID
            return
        }

        if let activeID = activeProfileID,
           profiles.contains(where: { $0.id == activeID }) {
            return
        }

        activeProfileID = profiles.first?.id
    }

    private func scheduleReminders() {
        let profiles = profiles
        Task { @MainActor [weak self, profiles] in
            guard let self else { return }
            let actionStates = await self.actionStore?.actionStatesSnapshot() ?? [:]
            await self.reminderScheduler.refreshReminders(for: profiles, actionStates: actionStates)
        }
    }

    private func synchronizeProfileMetadata() {
        actionStore?.synchronizeProfileMetadata(profiles)
    }

    private func observeSyncNotifications() {
        let token = notificationCenter.addObserver(forName: SyncCoordinator.mergeDidCompleteNotification,
                                                   object: nil,
                                                   queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshProfiles()
                self.ensureActiveProfileExists()
            }
        }
        notificationObservers.append(.init(token: token))
    }

    private func mutateProfiles(reason: String, _ work: () -> Bool) {
        let didChange = work()
        guard didChange else { return }
        persistContextIfNeeded(reason: reason)
        refreshProfiles()
        ensureActiveProfileExists()
    }

    private func persistContextIfNeeded(reason: String) {
        if modelContext.hasChanges {
            dataStack.saveIfNeeded(on: modelContext, reason: reason)
        }
    }

    private func persistSettings(reason: String) {
        persistContextIfNeeded(reason: reason)
    }

    private func profileModel(withID id: UUID) -> ProfileActionStateModel? {
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == id
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try? modelContext.fetch(descriptor)
        return results?.first
    }

    private static func clampCustomReminderDelay(_ delay: TimeInterval) -> TimeInterval {
        let range = customReminderDelayRange
        return min(max(delay, range.lowerBound), range.upperBound)
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

    private static func fetchOrCreateSettings(in context: ModelContext) -> ProfileStoreSettings {
        var descriptor = FetchDescriptor<ProfileStoreSettings>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), let model = existing.first {
            return model
        }

        let settings = ProfileStoreSettings()
        context.insert(settings)
        return settings
    }
}

extension ProfileStore {
    static var preview: ProfileStore {
        let stack = AppDataStack.preview()
        let context = stack.mainContext

        let profileA = ProfileActionStateModel(name: "Aria",
                                               birthDate: Date(timeIntervalSince1970: 1_600_000_000),
                                               remindersEnabled: true)
        let profileB = ProfileActionStateModel(name: "Luca",
                                               birthDate: Date(timeIntervalSince1970: 1_650_000_000))
        profileA.normalizeReminderPreferences()
        profileB.normalizeReminderPreferences()
        context.insert(profileA)
        context.insert(profileB)

        let scheduler = PreviewReminderScheduler()
        let store = ProfileStore(modelContext: context,
                                 dataStack: stack,
                                 directory: FileManager.default.temporaryDirectory,
                                 filename: "previewChildProfiles.json",
                                 reminderScheduler: scheduler)
        return store
    }
}

private extension ProfileStore {
    struct LegacyProfileState: Decodable {
        var profiles: [LegacyChildProfile]
        var activeProfileID: UUID?
        var showRecentActivityOnHome: Bool

        private enum CodingKeys: String, CodingKey {
            case profiles
            case activeProfileID
            case showRecentActivityOnHome
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profiles = try container.decode([LegacyChildProfile].self, forKey: .profiles)
            activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
            showRecentActivityOnHome = try container.decodeIfPresent(Bool.self, forKey: .showRecentActivityOnHome) ?? true
        }
    }

    struct LegacyChildProfile: Decodable {
        var id: UUID
        var name: String
        var birthDate: Date
        var imageData: Data?
        var remindersEnabled: Bool
        var actionReminderIntervals: [BabyActionCategory: TimeInterval]
        var actionRemindersEnabled: [BabyActionCategory: Bool]
        var actionReminderOverrides: [BabyActionCategory: ChildProfile.ActionReminderOverride]

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
                actionReminderIntervals = rawIntervals.reduce(into: [:]) { partialResult, element in
                    let (key, value) = element
                    if let category = BabyActionCategory(rawValue: key) {
                        partialResult[category] = max(0, value)
                    }
                }
            } else {
                actionReminderIntervals = ChildProfile.defaultActionReminderIntervals()
            }

            if let rawEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .actionRemindersEnabled) {
                actionRemindersEnabled = rawEnabled.reduce(into: [:]) { partialResult, element in
                    let (key, value) = element
                    if let category = BabyActionCategory(rawValue: key) {
                        partialResult[category] = value
                    }
                }
            } else {
                actionRemindersEnabled = ChildProfile.defaultActionRemindersEnabled()
            }

            if let rawOverrides = try container.decodeIfPresent([String: ChildProfile.ActionReminderOverride].self,
                                                                forKey: .actionReminderOverrides) {
                actionReminderOverrides = rawOverrides.reduce(into: [:]) { partialResult, element in
                    let (key, value) = element
                    if let category = BabyActionCategory(rawValue: key) {
                        partialResult[category] = value
                    }
                }
            } else {
                actionReminderOverrides = [:]
            }
        }

        func reminderInterval(for category: BabyActionCategory) -> TimeInterval {
            actionReminderIntervals[category] ?? ChildProfile.defaultActionReminderInterval
        }

        func isActionReminderEnabled(for category: BabyActionCategory) -> Bool {
            actionRemindersEnabled[category] ?? true
        }

        func actionReminderOverride(for category: BabyActionCategory) -> ChildProfile.ActionReminderOverride? {
            actionReminderOverrides[category]
        }
    }

    @MainActor
    final class PreviewReminderScheduler: ReminderScheduling {
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
                                     delay: TimeInterval) async -> Bool {
            true
        }
    }
}
