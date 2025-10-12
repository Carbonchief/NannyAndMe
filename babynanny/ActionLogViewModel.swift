import SwiftUI

struct BabyAction: Identifiable, Codable {
    enum DiaperType: String, CaseIterable, Identifiable, Codable {
        case pee
        case poo
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pee:
                return L10n.DiaperType.pee
            case .poo:
                return L10n.DiaperType.poo
            case .both:
                return L10n.DiaperType.both
            }
        }

        var icon: String {
            switch self {
            case .pee:
                return "drop.fill"
            case .poo:
                return "leaf.fill"
            case .both:
                return "drop.circle.fill"
            }
        }
    }

    enum FeedingType: String, CaseIterable, Identifiable, Codable {
        case bottle
        case leftBreast
        case rightBreast
        case meal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bottle:
                return L10n.FeedingType.bottle
            case .leftBreast:
                return L10n.FeedingType.leftBreast
            case .rightBreast:
                return L10n.FeedingType.rightBreast
            case .meal:
                return L10n.FeedingType.meal
            }
        }

        var icon: String {
            switch self {
            case .bottle:
                return "takeoutbag.and.cup.and.straw.fill"
            case .leftBreast:
                return "heart.fill"
            case .rightBreast:
                return "heart.circle.fill"
            case .meal:
                return "fork.knife.circle.fill"
            }
        }

        var requiresVolume: Bool {
            self == .bottle
        }
    }

    var id: UUID
    let category: BabyActionCategory
    var startDate: Date
    var endDate: Date?
    var diaperType: DiaperType?
    var feedingType: FeedingType?
    var bottleVolume: Int?
    var mealNotes: String?

    init(id: UUID = UUID(),
         category: BabyActionCategory,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: DiaperType? = nil,
         feedingType: FeedingType? = nil,
         bottleVolume: Int? = nil,
         mealNotes: String? = nil) {
        self.id = id
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.diaperType = diaperType
        self.feedingType = feedingType
        self.bottleVolume = bottleVolume
        self.mealNotes = mealNotes
    }

    var title: String {
        category.title
    }

    var icon: String {
        if let diaperType {
            return diaperType.icon
        }
        if let feedingType {
            return feedingType.icon
        }
        return category.icon
    }

    var detailDescription: String {
        switch category {
        case .sleep:
            return L10n.Actions.sleep
        case .diaper:
            if let diaperType {
                return L10n.Actions.diaperWithType(diaperType.title)
            }
            return L10n.Actions.diaperChange
        case .feeding:
            if let feedingType {
                if feedingType == .bottle, let bottleVolume {
                    return L10n.Actions.feedingBottle(bottleVolume)
                }
                if feedingType == .meal,
                   let note = mealNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   note.isEmpty == false {
                    return L10n.Actions.feedingMealWithNotes(note)
                }
                return L10n.Actions.feedingWithType(feedingType.title)
            }
            return L10n.Actions.feeding
        }
    }

    var subtypeWord: String? {
        switch category {
        case .sleep:
            return nil
        case .diaper:
            return diaperType?.title
        case .feeding:
            return feedingType?.title
        }
    }

    var isInstant: Bool {
        category.isInstant(feedingType: feedingType)
    }

    func durationDescription(asOf referenceDate: Date = Date()) -> String {
        let endReference = endDate ?? referenceDate
        let duration = endReference.timeIntervalSince(startDate)
        return BabyActionFormatter.shared.format(duration: duration)
    }

    func startTimeDescription() -> String {
        BabyActionFormatter.shared.format(time: startDate)
    }

    func startDateTimeDescription() -> String {
        BabyActionFormatter.shared.format(dateTime: startDate)
    }

    func endDateTimeDescription() -> String? {
        guard let endDate else { return nil }
        return BabyActionFormatter.shared.format(dateTime: endDate)
    }

    func loggedTimestampDescription(relativeTo referenceDate: Date = Date()) -> String {
        let logDate = endDate ?? startDate
        let calendar = Calendar.current

        if calendar.isDate(logDate, inSameDayAs: referenceDate) {
            return BabyActionFormatter.shared.format(time: logDate)
        }

        return BabyActionFormatter.shared.format(dateTime: logDate)
    }

    func withValidatedDates() -> BabyAction {
        var copy = self
        if isInstant {
            copy.endDate = copy.startDate
        } else if let endDate = copy.endDate, endDate < copy.startDate {
            copy.endDate = copy.startDate
        }
        return copy
    }
}

extension BabyAction: Equatable {
    static func == (lhs: BabyAction, rhs: BabyAction) -> Bool {
        lhs.id == rhs.id
            && lhs.category == rhs.category
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.diaperType == rhs.diaperType
            && lhs.feedingType == rhs.feedingType
            && lhs.bottleVolume == rhs.bottleVolume
            && lhs.mealNotes == rhs.mealNotes
    }
}

enum BabyActionCategory: String, CaseIterable, Identifiable, Codable {
    case sleep
    case diaper
    case feeding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return L10n.Actions.sleep
        case .diaper:
            return L10n.Actions.diaper
        case .feeding:
            return L10n.Actions.feeding
        }
    }

    var icon: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .diaper:
            return "sparkles"
        case .feeding:
            return "fork.knife"
        }
    }

    var accentColor: Color {
        switch self {
        case .sleep:
            return Color.indigo
        case .diaper:
            return Color.green
        case .feeding:
            return Color.orange
        }
    }

    func isInstant(feedingType: BabyAction.FeedingType? = nil) -> Bool {
        switch self {
        case .diaper:
            return true
        case .sleep:
            return false
        case .feeding:
            return feedingType == .meal
        }
    }

    var isInstant: Bool {
        isInstant()
    }

    func startActionButtonTitle(feedingType: BabyAction.FeedingType? = nil) -> String {
        isInstant(feedingType: feedingType) ? L10n.Common.log : L10n.Common.start
    }

    var startActionButtonTitle: String {
        startActionButtonTitle()
    }
}

struct ProfileActionState: Codable {
    var activeActions: [BabyActionCategory: BabyAction]
    var history: [BabyAction]

    init(activeActions: [BabyActionCategory: BabyAction] = [:], history: [BabyAction] = []) {
        self.activeActions = activeActions
        self.history = history
    }

    func latestHistoryEntriesPerCategory() -> [BabyAction] {
        var seenCategories = Set<BabyActionCategory>()
        var uniqueEntries: [BabyAction] = []

        for action in history {
            guard !seenCategories.contains(action.category) else { continue }
            seenCategories.insert(action.category)
            uniqueEntries.append(action)
        }

        return uniqueEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawActive = try container.decode([String: BabyAction].self, forKey: .activeActions)
        self.activeActions = rawActive.reduce(into: [:]) { partialResult, element in
            let (key, value) = element
            guard let category = BabyActionCategory(rawValue: key) else { return }
            partialResult[category] = value
        }
        self.history = try container.decode([BabyAction].self, forKey: .history)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawActive = Dictionary(uniqueKeysWithValues: activeActions.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawActive, forKey: .activeActions)
        try container.encode(history, forKey: .history)
    }

    func activeAction(for category: BabyActionCategory) -> BabyAction? {
        activeActions[category]
    }

    func lastCompletedAction(for category: BabyActionCategory) -> BabyAction? {
        history.first(where: { $0.category == category })
    }

    var mostRecentAction: BabyAction? {
        if let running = activeActions.values.sorted(by: { $0.startDate > $1.startDate }).first {
            return running
        }
        return history.first
    }

    private enum CodingKeys: String, CodingKey {
        case activeActions
        case history
    }
}

@MainActor
final class ActionLogStore: ObservableObject {
    private let saveURL: URL
    private let reminderScheduler: ReminderScheduling?
    private weak var profileStore: ProfileStore?

    @Published private var storage: ActionStoreState {
        didSet {
            persist()
            scheduleReminders()
        }
    }

    struct MergeSummary: Equatable {
        var added: Int
        var updated: Int

        static let empty = MergeSummary(added: 0, updated: 0)
    }

    func mergeProfileState(_ importedState: ProfileActionState, for profileID: UUID) -> MergeSummary {
        var summary = MergeSummary.empty

        updateState(for: profileID) { profileState in
            var existingHistory = Dictionary(uniqueKeysWithValues: profileState.history.map { ($0.id, $0) })

            for action in importedState.history {
                let sanitized = action.withValidatedDates()
                if let existing = existingHistory[sanitized.id] {
                    if existing != sanitized {
                        existingHistory[sanitized.id] = sanitized
                        summary.updated += 1
                    }
                } else {
                    existingHistory[sanitized.id] = sanitized
                    summary.added += 1
                }
            }

            profileState.history = Array(existingHistory.values)

            for (category, action) in importedState.activeActions {
                let sanitized = action.withValidatedDates()

                if let existing = profileState.activeActions[category] {
                    if existing.id == sanitized.id {
                        if existing != sanitized {
                            profileState.activeActions[category] = sanitized
                            summary.updated += 1
                        }
                    } else if sanitized.startDate >= existing.startDate {
                        profileState.activeActions[category] = sanitized
                        summary.added += 1
                    }
                } else {
                    profileState.activeActions[category] = sanitized
                    summary.added += 1
                }
            }
        }

        refreshDurationActivity(for: profileID)

        return summary
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "babyActions.json",
        reminderScheduler: ReminderScheduling? = nil
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.reminderScheduler = reminderScheduler

        if let data = try? Data(contentsOf: saveURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode(ActionStoreState.self, from: data) {
                self.storage = Self.sanitized(state: decoded)
            } else {
                self.storage = Self.defaultState()
            }
        } else {
            self.storage = Self.defaultState()
        }

        persist()
        scheduleReminders()
    }

    fileprivate init(
        initialState: ActionStoreState,
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "babyActions.json",
        reminderScheduler: ReminderScheduling? = nil
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.storage = Self.sanitized(state: initialState)
        self.reminderScheduler = reminderScheduler
        persist()
        scheduleReminders()
    }

    func state(for profileID: UUID) -> ProfileActionState {
        storage.profiles[profileID] ?? ProfileActionState()
    }

    func registerProfileStore(_ store: ProfileStore) {
        profileStore = store
        scheduleReminders()
        refreshDurationActivityOnLaunch()
    }

    var actionStatesSnapshot: [UUID: ProfileActionState] {
        storage.profiles
    }

    func startAction(for profileID: UUID,
                     category: BabyActionCategory,
                     diaperType: BabyAction.DiaperType? = nil,
                     feedingType: BabyAction.FeedingType? = nil,
                     bottleVolume: Int? = nil) {
        updateState(for: profileID) { profileState in
            let now = Date()

            if category.isInstant(feedingType: feedingType) {
                if var existing = profileState.activeActions.removeValue(forKey: category) {
                    existing.endDate = now
                    profileState.history.insert(existing, at: 0)
                }

                let action = BabyAction(category: category,
                                        startDate: now,
                                        endDate: now,
                                        diaperType: diaperType,
                                        feedingType: feedingType,
                                        bottleVolume: bottleVolume)
                profileState.history.insert(action, at: 0)
                return
            }

            let conflictingCategories = profileState.activeActions.keys.filter { key in
                key != category && !key.isInstant
            }

            for conflict in conflictingCategories {
                if var running = profileState.activeActions.removeValue(forKey: conflict) {
                    running.endDate = now
                    profileState.history.insert(running, at: 0)
                }
            }

            if var existing = profileState.activeActions.removeValue(forKey: category) {
                existing.endDate = now
                profileState.history.insert(existing, at: 0)
            }

            let action = BabyAction(category: category,
                                    startDate: now,
                                    diaperType: diaperType,
                                    feedingType: feedingType,
                                    bottleVolume: bottleVolume)
            profileState.activeActions[category] = action
        }

        refreshDurationActivity(for: profileID)
    }

    func stopAction(for profileID: UUID, category: BabyActionCategory) {
        updateState(for: profileID) { profileState in
            guard var action = profileState.activeActions.removeValue(forKey: category) else { return }
            action.endDate = Date()
            profileState.history.insert(action, at: 0)
        }

        refreshDurationActivity(for: profileID)
    }

    func updateAction(for profileID: UUID, action updatedAction: BabyAction) {
        updateState(for: profileID) { profileState in
            var normalizedAction = updatedAction.withValidatedDates()

            let relatedHistory = profileState.history.filter {
                $0.category == normalizedAction.category && $0.id != normalizedAction.id
            }
            let relatedActive = profileState.activeActions.values.filter {
                $0.category == normalizedAction.category && $0.id != normalizedAction.id
            }
            let conflictingActions = relatedHistory + relatedActive

            if !conflictingActions.isEmpty {
                normalizedAction = Self.clamp(normalizedAction, avoiding: conflictingActions)
            }

            if let index = profileState.history.firstIndex(where: { $0.id == updatedAction.id }) {
                profileState.history[index] = normalizedAction
            }

            for (category, action) in profileState.activeActions {
                guard action.id == updatedAction.id else { continue }
                profileState.activeActions[category] = normalizedAction
                break
            }
        }

        refreshDurationActivity(for: profileID)
    }

    func deleteAction(for profileID: UUID, actionID: UUID) {
        updateState(for: profileID) { profileState in
            profileState.history.removeAll { $0.id == actionID }

            let categoriesToRemove = profileState.activeActions.compactMap { element -> BabyActionCategory? in
                let (category, action) = element
                return action.id == actionID ? category : nil
            }

            for category in categoriesToRemove {
                profileState.activeActions.removeValue(forKey: category)
            }
        }

        refreshDurationActivity(for: profileID)
    }

    private static func clamp(_ action: BabyAction, avoiding conflicts: [BabyAction]) -> BabyAction {
        guard !conflicts.isEmpty else { return action.withValidatedDates() }

        func effectiveEndDate(for other: BabyAction) -> Date {
            if let endDate = other.endDate {
                return endDate
            }

            if other.isInstant {
                return other.startDate
            }

            return .distantFuture
        }

        var adjustedStart = action.startDate

        while true {
            let lowerBound = conflicts
                .filter { $0.startDate <= adjustedStart }
                .map { effectiveEndDate(for: $0) }
                .max()

            guard let lowerBound, adjustedStart < lowerBound else { break }
            adjustedStart = lowerBound
        }

        var adjustedAction = action
        adjustedAction.startDate = adjustedStart

        if let upperBound = conflicts
            .filter({ $0.startDate >= adjustedStart })
            .map({ $0.startDate })
            .min()
        {
            if let currentEnd = adjustedAction.endDate {
                if currentEnd > upperBound {
                    adjustedAction.endDate = max(adjustedStart, upperBound)
                }
            } else if !adjustedAction.isInstant {
                adjustedAction.endDate = max(adjustedStart, upperBound)
            }
        }

        return adjustedAction.withValidatedDates()
    }

    func removeProfileData(for profileID: UUID) {
        var profiles = storage.profiles
        guard profiles.removeValue(forKey: profileID) != nil else { return }
        storage = Self.sanitized(state: ActionStoreState(profiles: profiles))

        refreshDurationActivity(for: profileID)
    }

    private func updateState(for profileID: UUID, _ updates: (inout ProfileActionState) -> Void) {
        var profiles = storage.profiles
        var profileState = profiles[profileID] ?? ProfileActionState()
        updates(&profileState)
        profileState.history.sort { $0.startDate > $1.startDate }
        var seenIDs = Set<UUID>()
        profileState.history = profileState.history.filter { action in
            if seenIDs.contains(action.id) {
                return false
            }
            seenIDs.insert(action.id)
            return true
        }
        profiles[profileID] = profileState
        storage = ActionStoreState(profiles: profiles)
    }

    private func refreshDurationActivity(for profileID: UUID) {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }

        let profile = profileStore?.profiles.first(where: { $0.id == profileID })
        let profileName = profile?.displayName
        let activeActions = Array(
            storage.profiles[profileID]?.activeActions.values
                ?? Dictionary<BabyActionCategory, BabyAction>().values
        )
        DurationActivityController.shared.update(
            for: profileName,
            actions: activeActions
        )
#endif
    }

    private func refreshDurationActivityOnLaunch() {
#if canImport(ActivityKit)
        guard #available(iOS 17.0, *) else { return }

        if let runningProfileID = storage.profiles.first(where: { _, state in
            state.activeActions.values.contains(where: { $0.endDate == nil && $0.isInstant == false })
        })?.key {
            refreshDurationActivity(for: runningProfileID)
            return
        }

        if let fallbackProfileID = profileStore?.activeProfileID ?? storage.profiles.keys.first {
            refreshDurationActivity(for: fallbackProfileID)
        }
#endif
    }

    private func persist() {
        let snapshot = storage
        let url = saveURL

        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to persist baby actions: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func scheduleReminders() {
        guard let reminderScheduler else { return }
        let profiles = profileStore?.profiles ?? []
        let actionStates = storage.profiles

        Task { [profiles, actionStates] in
            await reminderScheduler.refreshReminders(for: profiles, actionStates: actionStates)
        }
    }

    private static func sanitized(state: ActionStoreState?) -> ActionStoreState {
        var state = state ?? ActionStoreState(profiles: [:])
        for (key, var value) in state.profiles {
            var normalizedActive: [BabyActionCategory: BabyAction] = [:]
            var endedActions: [BabyAction] = []

            for (category, action) in value.activeActions {
                let normalized = action.withValidatedDates()
                if normalized.endDate != nil {
                    endedActions.append(normalized)
                } else {
                    normalizedActive[category] = normalized
                }
            }

            value.activeActions = normalizedActive
            value.history = value.history.map { $0.withValidatedDates() }
            value.history.append(contentsOf: endedActions)
            value.history.sort { $0.startDate > $1.startDate }

            var seenIDs = Set<UUID>()
            value.history = value.history.filter { action in
                if seenIDs.contains(action.id) {
                    return false
                }
                seenIDs.insert(action.id)
                return true
            }

            state.profiles[key] = value
        }
        return state
    }

    private static func defaultState() -> ActionStoreState {
        ActionStoreState(profiles: [:])
    }

    private static let appGroupIdentifier = "group.com.prioritybit.babynanny"

    private static func resolveSaveURL(fileManager: FileManager, directory: URL?, filename: String) -> URL {
        if let directory {
            return directory.appendingPathComponent(filename)
        }

        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return containerURL.appendingPathComponent(filename)
        }

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent(filename)
        }

        return fileManager.temporaryDirectory.appendingPathComponent(filename)
    }
}

private struct ActionStoreState: Codable {
    var profiles: [UUID: ProfileActionState]
}

extension ActionLogStore {
    static func previewStore(profiles: [UUID: ProfileActionState]) -> ActionLogStore {
        ActionLogStore(
            initialState: ActionStoreState(profiles: profiles),
            directory: FileManager.default.temporaryDirectory,
            filename: "previewBabyActions-\(UUID().uuidString).json"
        )
    }
}

private final class BabyActionFormatter {
    static let shared = BabyActionFormatter()

    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter

    private init() {
        timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.timeStyle = .short
        dateTimeFormatter.dateStyle = .short

        durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
    }

    func format(time: Date) -> String {
        timeFormatter.string(from: time)
    }

    func format(dateTime: Date) -> String {
        dateTimeFormatter.string(from: dateTime)
    }

    func format(duration: TimeInterval) -> String {
        durationFormatter.string(from: duration) ?? L10n.Formatter.justNow
    }
}
