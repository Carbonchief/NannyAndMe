import Foundation
import SwiftData
import SwiftUI

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

struct BabyAction: Identifiable, Codable, Equatable {
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
                return "waterbottle.fill"
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

    enum BottleType: String, CaseIterable, Identifiable, Codable {
        case formula
        case breastMilk

        var id: String { rawValue }

        var title: String {
            switch self {
            case .formula:
                return L10n.BottleType.formula
            case .breastMilk:
                return L10n.BottleType.breastMilk
            }
        }
    }

    var id: UUID
    let category: BabyActionCategory
    var startDate: Date
    var endDate: Date?
    var diaperType: DiaperType?
    var feedingType: FeedingType?
    var bottleType: BottleType?
    var bottleVolume: Int?

    init(id: UUID = UUID(),
         category: BabyActionCategory,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: DiaperType? = nil,
         feedingType: FeedingType? = nil,
         bottleType: BottleType? = nil,
         bottleVolume: Int? = nil) {
        self.id = id
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.diaperType = diaperType
        self.feedingType = feedingType
        self.bottleType = bottleType
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
                if feedingType == .bottle {
                    if let bottleType, let bottleVolume {
                        return L10n.Actions.feedingBottleWithType(bottleType.title, bottleVolume)
                    }
                    if let bottleType {
                        return L10n.Actions.feedingBottleWithTypeOnly(bottleType.title)
                    }
                    if let bottleVolume {
                        return L10n.Actions.feedingBottle(bottleVolume)
                    }
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
            if let feedingType {
                if feedingType == .bottle, let bottleType {
                    return bottleType.title
                }
                return feedingType.title
            }
            return nil
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

    func loggedTimestampDescription(relativeTo referenceDate: Date = Date()) -> String {
        let logDate = endDate ?? startDate
        let calendar = Calendar.current

        if calendar.isDate(logDate, inSameDayAs: referenceDate) {
            return BabyActionFormatter.shared.format(time: logDate)
        }

        return BabyActionFormatter.shared.format(dateTime: logDate)
    }

    func timeSinceCompletionDescription(asOf referenceDate: Date = Date()) -> String? {
        guard let endDate else { return nil }
        let interval = referenceDate.timeIntervalSince(endDate)
        guard interval > 1 else { return L10n.Formatter.justNow }
        return BabyActionFormatter.shared.format(timeSince: interval)
    }

    func timeSinceCompletionAccessibilityDescription(asOf referenceDate: Date = Date()) -> String? {
        guard let endDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: endDate, relativeTo: referenceDate)
    }

    func withValidatedDates() -> BabyAction {
        var copy = self
        if category.isInstant {
            copy.endDate = copy.startDate
        } else if let endDate = copy.endDate, endDate < copy.startDate {
            copy.endDate = copy.startDate
        }
        return copy
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

@Model
final class ProfileActionStateModel {
    @Attribute(.unique) var profileID: UUID
    @Relationship(deleteRule: .cascade, inverse: \BabyActionModel.profile)
    var actions: [BabyActionModel]

    init(profileID: UUID, actions: [BabyActionModel] = []) {
        self.profileID = profileID
        self.actions = actions
        for action in self.actions where action.profile !== self {
            action.profile = self
        }
    }
}

@Model
final class BabyActionModel {
    @Attribute(.unique) var id: UUID
    var categoryRawValue: String
    var startDate: Date
    var endDate: Date?
    var diaperTypeRawValue: String?
    var feedingTypeRawValue: String?
    var bottleTypeRawValue: String?
    var bottleVolume: Int?
    @Relationship(inverse: \ProfileActionStateModel.actions)
    var profile: ProfileActionStateModel

    init(id: UUID = UUID(),
         category: BabyActionCategory,
         startDate: Date,
         endDate: Date?,
         diaperType: BabyAction.DiaperType?,
         feedingType: BabyAction.FeedingType?,
         bottleType: BabyAction.BottleType?,
         bottleVolume: Int?,
         profile: ProfileActionStateModel) {
        self.id = id
        self.categoryRawValue = category.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.diaperTypeRawValue = diaperType?.rawValue
        self.feedingTypeRawValue = feedingType?.rawValue
        self.bottleTypeRawValue = bottleType?.rawValue
        self.bottleVolume = bottleVolume
        self.profile = profile
    }
}

extension BabyActionModel {
    var category: BabyActionCategory {
        get { BabyActionCategory(rawValue: categoryRawValue) ?? .sleep }
        set { categoryRawValue = newValue.rawValue }
    }

    var diaperType: BabyAction.DiaperType? {
        get {
            guard let rawValue = diaperTypeRawValue else { return nil }
            return BabyAction.DiaperType(rawValue: rawValue)
        }
        set {
            diaperTypeRawValue = newValue?.rawValue
        }
    }

    var feedingType: BabyAction.FeedingType? {
        get {
            guard let rawValue = feedingTypeRawValue else { return nil }
            return BabyAction.FeedingType(rawValue: rawValue)
        }
        set {
            feedingTypeRawValue = newValue?.rawValue
        }
    }

    var bottleType: BabyAction.BottleType? {
        get {
            guard let rawValue = bottleTypeRawValue else { return nil }
            return BabyAction.BottleType(rawValue: rawValue)
        }
        set {
            bottleTypeRawValue = newValue?.rawValue
        }
    }

    func asBabyAction() -> BabyAction {
        BabyAction(
            id: id,
            category: category,
            startDate: startDate,
            endDate: endDate,
            diaperType: diaperType,
            feedingType: feedingType,
            bottleType: bottleType,
            bottleVolume: bottleVolume
        )
    }

    func update(from action: BabyAction) {
        id = action.id
        category = action.category
        startDate = action.startDate
        endDate = action.endDate
        diaperType = action.diaperType
        feedingType = action.feedingType
        bottleType = action.bottleType
        bottleVolume = action.bottleVolume
    }
}

private final class BabyActionFormatter {
    static let shared = BabyActionFormatter()

    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter
    private let timeSinceFormatter: DateComponentsFormatter

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

        timeSinceFormatter = DateComponentsFormatter()
        timeSinceFormatter.allowedUnits = [.day, .hour, .minute]
        timeSinceFormatter.unitsStyle = .abbreviated
        timeSinceFormatter.maximumUnitCount = 1
        timeSinceFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
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

    func format(timeSince interval: TimeInterval) -> String {
        guard let value = timeSinceFormatter.string(from: interval), !value.isEmpty else {
            return L10n.Formatter.justNow
        }
        return L10n.Formatter.ago(value)
    }
}
