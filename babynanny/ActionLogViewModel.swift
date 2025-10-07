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
    let startDate: Date
    var endDate: Date?
    let diaperType: DiaperType?
    let feedingType: FeedingType?
    let bottleVolume: Int?

    init(id: UUID = UUID(),
         category: BabyActionCategory,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: DiaperType? = nil,
         feedingType: FeedingType? = nil,
         bottleVolume: Int? = nil) {
        self.id = id
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.diaperType = diaperType
        self.feedingType = feedingType
        self.bottleVolume = bottleVolume
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
                return L10n.Actions.feedingWithType(feedingType.title)
            }
            return L10n.Actions.feeding
        }
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

    var isInstant: Bool {
        switch self {
        case .diaper:
            return true
        case .sleep, .feeding:
            return false
        }
    }

    var startActionButtonTitle: String {
        isInstant ? L10n.Common.log : L10n.Common.start
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

    @Published private var storage: ActionStoreState {
        didSet {
            persist()
        }
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "babyActions.json"
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)

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
    }

    fileprivate init(
        initialState: ActionStoreState,
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "babyActions.json"
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        self.storage = Self.sanitized(state: initialState)
        persist()
    }

    func state(for profileID: UUID) -> ProfileActionState {
        storage.profiles[profileID] ?? ProfileActionState()
    }

    func startAction(for profileID: UUID,
                     category: BabyActionCategory,
                     diaperType: BabyAction.DiaperType? = nil,
                     feedingType: BabyAction.FeedingType? = nil,
                     bottleVolume: Int? = nil) {
        updateState(for: profileID) { profileState in
            let now = Date()

            if category.isInstant {
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
    }

    func stopAction(for profileID: UUID, category: BabyActionCategory) {
        updateState(for: profileID) { profileState in
            guard var action = profileState.activeActions.removeValue(forKey: category) else { return }
            action.endDate = Date()
            profileState.history.insert(action, at: 0)
        }
    }

    func removeProfileData(for profileID: UUID) {
        var profiles = storage.profiles
        guard profiles.removeValue(forKey: profileID) != nil else { return }
        storage = Self.sanitized(state: ActionStoreState(profiles: profiles))
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

    private static func sanitized(state: ActionStoreState?) -> ActionStoreState {
        var state = state ?? ActionStoreState(profiles: [:])
        for (key, var value) in state.profiles {
            var endedActions: [BabyAction] = []
            value.activeActions = value.activeActions.filter { _, action in
                if let _ = action.endDate {
                    endedActions.append(action)
                    return false
                }
                return true
            }

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
        dateTimeFormatter.dateStyle = .medium

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
