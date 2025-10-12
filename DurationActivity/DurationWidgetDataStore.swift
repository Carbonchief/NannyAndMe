import Foundation

struct DurationWidgetSnapshot: Equatable {
    var profileName: String?
    var actions: [DurationWidgetAction]

    var hasActiveActions: Bool {
        actions.isEmpty == false
    }

    static let empty = DurationWidgetSnapshot(profileName: nil, actions: [])

    static let placeholder: DurationWidgetSnapshot = {
        let now = Date()
        let sleep = DurationWidgetAction(
            id: UUID(),
            category: .sleep,
            startDate: now.addingTimeInterval(-5400),
            endDate: nil,
            diaperType: nil,
            feedingType: nil,
            bottleType: nil,
            bottleVolume: nil
        )
        let feeding = DurationWidgetAction(
            id: UUID(),
            category: .feeding,
            startDate: now.addingTimeInterval(-1200),
            endDate: nil,
            diaperType: nil,
            feedingType: .bottle,
            bottleType: .formula,
            bottleVolume: 120
        )
        return DurationWidgetSnapshot(profileName: "Aria", actions: [sleep, feeding])
    }()
}

struct DurationWidgetAction: Identifiable, Codable, Equatable {
    enum DiaperType: String, Codable {
        case pee
        case poo
        case both
    }

    enum FeedingType: String, Codable {
        case bottle
        case leftBreast
        case rightBreast
        case meal
    }

    enum BottleType: String, Codable {
        case formula
        case breastMilk
    }

    let id: UUID
    let category: BabyActionCategory
    let startDate: Date
    var endDate: Date?
    let diaperType: DiaperType?
    let feedingType: FeedingType?
    let bottleType: BottleType?
    let bottleVolume: Int?

    var isRunning: Bool {
        endDate == nil
    }

    var displayTitle: String {
        switch category {
        case .sleep:
            return WidgetL10n.Actions.sleep
        case .diaper:
            return WidgetL10n.Actions.feeding // Diaper actions are not displayed; use a generic label.
        case .feeding:
            guard let feedingType else {
                return WidgetL10n.Actions.feeding
            }
            switch feedingType {
            case .bottle:
                let bottleTypeTitle = bottleType?.localizedTitle
                if let bottleTypeTitle, let bottleVolume, bottleVolume > 0 {
                    return WidgetL10n.Actions.feedingBottleWithType(bottleTypeTitle, bottleVolume)
                }
                if let bottleVolume, bottleVolume > 0 {
                    return WidgetL10n.Actions.feedingBottle(bottleVolume)
                }
                if let bottleTypeTitle {
                    return WidgetL10n.Actions.feedingBottleWithTypeOnly(bottleTypeTitle)
                }
                return WidgetL10n.Actions.feedingWithType(WidgetL10n.FeedingType.bottle)
            case .leftBreast:
                return WidgetL10n.Actions.feedingWithType(WidgetL10n.FeedingType.leftBreast)
            case .rightBreast:
                return WidgetL10n.Actions.feedingWithType(WidgetL10n.FeedingType.rightBreast)
            case .meal:
                return WidgetL10n.Actions.feedingWithType(WidgetL10n.FeedingType.meal)
            }
        }
    }

    func durationDescription(asOf referenceDate: Date) -> String {
        let endReference = endDate ?? referenceDate
        let duration = max(0, endReference.timeIntervalSince(startDate))
        return DurationWidgetFormatter.shared.format(duration: duration)
    }
}

private extension DurationWidgetAction.BottleType {
    var localizedTitle: String {
        switch self {
        case .formula:
            return WidgetL10n.BottleType.formula
        case .breastMilk:
            return WidgetL10n.BottleType.breastMilk
        }
    }
}

enum BabyActionCategory: String, Codable {
    case sleep
    case diaper
    case feeding

    var isLongRunning: Bool {
        switch self {
        case .diaper:
            return false
        case .sleep, .feeding:
            return true
        }
    }
}

private final class DurationWidgetFormatter {
    static let shared = DurationWidgetFormatter()

    private let durationFormatter: DateComponentsFormatter

    private init() {
        durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
    }

    func format(duration: TimeInterval) -> String {
        durationFormatter.string(from: duration) ?? WidgetL10n.Formatter.justNow
    }
}

struct DurationDataStore {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let actionFilename = "babyActions.json"
    private let profileFilename = "childProfiles.json"
    private let appGroupIdentifier = "group.com.prioritybit.babynanny"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func loadSnapshot() -> DurationWidgetSnapshot? {
        guard let profileState = loadProfileState(),
              let actionState = loadActionState(),
              let activeProfileID = profileState.activeProfileID,
              let profile = profileState.profile(withID: activeProfileID) else {
            return nil
        }

        let activeActions = actionState.profiles[activeProfileID]?.activeActions.map(\.value) ?? []
        let running = activeActions
            .filter { $0.category.isLongRunning && $0.endDate == nil }
            .sorted(by: { $0.startDate < $1.startDate })

        return DurationWidgetSnapshot(
            profileName: profile.displayName,
            actions: running
        )
    }

    func stopAction(withID actionID: UUID, at stopDate: Date = Date()) throws {
        guard let url = url(for: actionFilename) else {
            throw StopActionError.stateUnavailable
        }

        let data = try Data(contentsOf: url)
        var state = try decoder.decode(SharedActionStoreState.self, from: data)

        var didUpdate = false

        for (profileID, profileState) in state.profiles {
            guard let match = profileState.activeActions.first(where: { $0.value.id == actionID }) else { continue }

            var updatedProfile = profileState
            var finishedAction = updatedProfile.activeActions.removeValue(forKey: match.key)
            finishedAction?.endDate = stopDate

            if let finishedAction {
                updatedProfile.history.insert(finishedAction, at: 0)
                state.profiles[profileID] = updatedProfile
                didUpdate = true
                break
            }
        }

        guard didUpdate else {
            throw StopActionError.actionNotFound
        }

        let updatedData = try encoder.encode(state)
        try updatedData.write(to: url, options: .atomic)
    }

    private func loadProfileState() -> SharedProfileState? {
        guard let url = url(for: profileFilename),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(SharedProfileState.self, from: data)
    }

    private func loadActionState() -> SharedActionStoreState? {
        guard let url = url(for: actionFilename),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(SharedActionStoreState.self, from: data)
    }

    private func url(for filename: String) -> URL? {
        for directory in candidateDirectories() {
            let potential = directory.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: potential.path) {
                return potential
            }
        }
        return nil
    }

    private func candidateDirectories() -> [URL] {
        var directories: [URL] = []
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            directories.append(container)
        }
        let searchPaths: [FileManager.SearchPathDirectory] = [
            .documentDirectory,
            .libraryDirectory,
            .applicationSupportDirectory,
            .cachesDirectory
        ]
        for directory in searchPaths {
            if let url = fileManager.urls(for: directory, in: .userDomainMask).first {
                directories.append(url)
            }
        }
        return directories
    }
    enum StopActionError: Error {
        case stateUnavailable
        case actionNotFound
    }
}

private struct SharedActionStoreState: Codable {
    var profiles: [UUID: SharedProfileActionState]

    private enum CodingKeys: String, CodingKey {
        case profiles
    }

    init(profiles: [UUID: SharedProfileActionState]) {
        self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawProfiles = try container.decode([String: SharedProfileActionState].self, forKey: .profiles)
        var mapped: [UUID: SharedProfileActionState] = [:]
        for (key, value) in rawProfiles {
            guard let uuid = UUID(uuidString: key) else { continue }
            mapped[uuid] = value
        }
        profiles = mapped
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.key.uuidString, $0.value) })
        try container.encode(rawProfiles, forKey: .profiles)
    }
}

private struct SharedProfileActionState: Codable {
    var activeActions: [BabyActionCategory: DurationWidgetAction]
    var history: [DurationWidgetAction]

    private enum CodingKeys: String, CodingKey {
        case activeActions
        case history
    }

    init(activeActions: [BabyActionCategory: DurationWidgetAction], history: [DurationWidgetAction]) {
        self.activeActions = activeActions
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawActive = try container.decode([String: DurationWidgetAction].self, forKey: .activeActions)
        var mapped: [BabyActionCategory: DurationWidgetAction] = [:]
        for (key, value) in rawActive {
            guard let category = BabyActionCategory(rawValue: key) else { continue }
            mapped[category] = value
        }
        activeActions = mapped
        history = try container.decodeIfPresent([DurationWidgetAction].self, forKey: .history) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawActive = Dictionary(uniqueKeysWithValues: activeActions.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawActive, forKey: .activeActions)
        try container.encode(history, forKey: .history)
    }
}

private struct SharedProfileState: Decodable {
    var profiles: [SharedChildProfile]
    var activeProfileID: UUID?

    private enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileID
    }

    func profile(withID id: UUID) -> SharedChildProfile? {
        profiles.first(where: { $0.id == id })
    }
}

private struct SharedChildProfile: Decodable {
    var id: UUID
    var name: String
    var imageData: Data?

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? WidgetL10n.Profile.newProfile : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case imageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
    }
}
