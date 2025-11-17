import Foundation
import SwiftData
import SwiftUI

extension BabyActionCategory: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return L10n.Actions.sleep
        case .diaper:
            return L10n.Actions.diaper
        case .feeding:
            return L10n.Actions.feeding
        @unknown default:
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
        @unknown default:
            return "sparkles"
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
        @unknown default:
            return Color.accentColor
        }
    }

    var isInstant: Bool {
        switch self {
        case .diaper:
            return true
        case .sleep, .feeding:
            return false
        @unknown default:
            return false
        }
    }

    var startActionButtonTitle: String {
        isInstant ? L10n.Common.log : L10n.Common.start
    }
}

extension BabyActionDiaperType: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .pee:
            return L10n.DiaperType.pee
        case .poo:
            return L10n.DiaperType.poo
        case .both:
            return L10n.DiaperType.both
        @unknown default:
            return L10n.DiaperType.pee
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
        @unknown default:
            return "sparkles"
        }
    }
}

extension BabyActionFeedingType: Identifiable {
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
        @unknown default:
            return L10n.FeedingType.bottle
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
        @unknown default:
            return "fork.knife"
        }
    }

    var requiresVolume: Bool {
        self == .bottle
    }
}

extension BabyActionBottleType: Identifiable {
    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula:
            return L10n.BottleType.formula
        case .breastMilk:
            return L10n.BottleType.breastMilk
        @unknown default:
            return L10n.BottleType.formula
        }
    }
}

struct BabyActionSnapshot: Identifiable, Codable, Equatable, Sendable {
    typealias DiaperType = BabyActionDiaperType
    typealias FeedingType = BabyActionFeedingType
    typealias BottleType = BabyActionBottleType

    var id: UUID
    let category: BabyActionCategory
    private var startDateStorage: Date
    private var endDateStorage: Date?
    var diaperType: DiaperType?
    var feedingType: FeedingType?
    var bottleType: BottleType?
    var bottleVolume: Int?
    var latitude: Double?
    var longitude: Double?
    var placename: String?
    var updatedAt: Date

    init(id: UUID = UUID(),
         category: BabyActionCategory,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: DiaperType? = nil,
         feedingType: FeedingType? = nil,
         bottleType: BottleType? = nil,
         bottleVolume: Int? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         placename: String? = nil,
         updatedAt: Date = Date()) {
        self.id = id
        self.category = category
        self.startDateStorage = startDate.normalizedToUTC()
        self.endDateStorage = endDate?.normalizedToUTC()
        self.diaperType = diaperType
        self.feedingType = feedingType
        self.bottleType = bottleType
        self.bottleVolume = bottleVolume
        self.latitude = latitude
        self.longitude = longitude
        self.placename = placename
        self.updatedAt = updatedAt
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

    @MainActor
    func durationDescription(asOf referenceDate: Date = Date()) -> String {
        let endReference = endDate ?? referenceDate
        let duration = endReference.timeIntervalSince(startDate)
        return BabyActionFormatter.shared.format(duration: duration)
    }

    @MainActor
    func startTimeDescription() -> String {
        BabyActionFormatter.shared.format(time: startDate)
    }

    @MainActor
    func startDateTimeDescription() -> String {
        BabyActionFormatter.shared.format(dateTime: startDate)
    }

    @MainActor
    func endDateTimeDescription() -> String? {
        guard let endDate else { return nil }
        return BabyActionFormatter.shared.format(dateTime: endDate)
    }

    @MainActor
    func loggedTimestampDescription(relativeTo referenceDate: Date = Date()) -> String {
        let logDate = endDate ?? startDate
        let calendar = Calendar.current

        if calendar.isDate(logDate, inSameDayAs: referenceDate) {
            return BabyActionFormatter.shared.format(time: logDate)
        }

        return BabyActionFormatter.shared.format(dateTime: logDate)
    }

    @MainActor
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

    func withValidatedDates() -> BabyActionSnapshot {
        var copy = self
        if category.isInstant {
            copy.endDate = copy.startDate
        } else if let endDate = copy.endDate, endDate < copy.startDate {
            copy.endDate = copy.startDate
        }
        return copy
    }

    var startDate: Date {
        get { startDateStorage }
        set { startDateStorage = newValue.normalizedToUTC() }
    }

    var endDate: Date? {
        get { endDateStorage }
        set { endDateStorage = newValue?.normalizedToUTC() }
    }
}

extension BabyActionSnapshot {
    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case startDateStorage = "startDate"
        case endDateStorage = "endDate"
        case diaperType
        case feedingType
        case bottleType
        case bottleVolume
        case updatedAt
        case latitude
        case longitude
        case placename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        category = try container.decode(BabyActionCategory.self, forKey: .category)
        let decodedStartDate = try container.decode(Date.self, forKey: .startDateStorage)
        startDateStorage = decodedStartDate.normalizedToUTC()
        let decodedEndDate = try container.decodeIfPresent(Date.self, forKey: .endDateStorage)
        endDateStorage = decodedEndDate?.normalizedToUTC()
        diaperType = try container.decodeIfPresent(BabyActionDiaperType.self, forKey: .diaperType)
        feedingType = try container.decodeIfPresent(BabyActionFeedingType.self, forKey: .feedingType)
        bottleType = try container.decodeIfPresent(BabyActionBottleType.self, forKey: .bottleType)
        bottleVolume = try container.decodeIfPresent(Int.self, forKey: .bottleVolume)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        placename = try container.decodeIfPresent(String.self, forKey: .placename)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(category, forKey: .category)
        try container.encode(startDateStorage, forKey: .startDateStorage)
        try container.encodeIfPresent(endDateStorage, forKey: .endDateStorage)
        try container.encodeIfPresent(diaperType, forKey: .diaperType)
        try container.encodeIfPresent(feedingType, forKey: .feedingType)
        try container.encodeIfPresent(bottleType, forKey: .bottleType)
        try container.encodeIfPresent(bottleVolume, forKey: .bottleVolume)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(placename, forKey: .placename)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ProfileActionState: Codable, Sendable {
    var activeActions: [BabyActionCategory: BabyActionSnapshot]
    var history: [BabyActionSnapshot]

    init(activeActions: [BabyActionCategory: BabyActionSnapshot] = [:], history: [BabyActionSnapshot] = []) {
        self.activeActions = activeActions
        self.history = history
    }

    func latestHistoryEntriesPerCategory() -> [BabyActionSnapshot] {
        var seenCategories = Set<BabyActionCategory>()
        var uniqueEntries: [BabyActionSnapshot] = []

        for action in history {
            guard !seenCategories.contains(action.category) else { continue }
            seenCategories.insert(action.category)
            uniqueEntries.append(action)
        }

        return uniqueEntries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawActive = try container.decode([String: BabyActionSnapshot].self, forKey: .activeActions)
        self.activeActions = rawActive.reduce(into: [:]) { partialResult, element in
            let (key, value) = element
            guard let category = BabyActionCategory(rawValue: key) else { return }
            partialResult[category] = value
        }
        self.history = try container.decode([BabyActionSnapshot].self, forKey: .history)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawActive = Dictionary(uniqueKeysWithValues: activeActions.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawActive, forKey: .activeActions)
        try container.encode(history, forKey: .history)
    }

    func activeAction(for category: BabyActionCategory) -> BabyActionSnapshot? {
        activeActions[category]
    }

    func lastCompletedAction(for category: BabyActionCategory) -> BabyActionSnapshot? {
        history.first(where: { $0.category == category })
    }

    var mostRecentAction: BabyActionSnapshot? {
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

struct ProfileActionReminderOverride: Codable, Equatable, Sendable {
    var fireDate: Date
    var isOneOff: Bool
}

@Model
final class ProfileReminderPreference {
    var categoryRawValue: String = BabyActionCategory.sleep.rawValue
    var interval: TimeInterval = 3 * 60 * 60
    var isEnabled: Bool = true
    var overrideFireDate: Date?
    var overrideIsOneOff: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \Profile.reminderPreferences)
    var profile: Profile?

    init(category: BabyActionCategory = .sleep,
         interval: TimeInterval = 3 * 60 * 60,
         isEnabled: Bool = true,
         override: ProfileActionReminderOverride? = nil,
         profile: Profile? = nil) {
        self.category = category
        self.interval = max(0, interval)
        self.isEnabled = isEnabled
        self.overrideFireDate = override?.fireDate
        self.overrideIsOneOff = override?.isOneOff ?? false
        self.profile = profile
    }

    var category: BabyActionCategory {
        get { BabyActionCategory(rawValue: categoryRawValue) ?? .sleep }
        set { categoryRawValue = newValue.rawValue }
    }

    var override: ProfileActionReminderOverride? {
        get {
            guard let fireDate = overrideFireDate else { return nil }
            return ProfileActionReminderOverride(fireDate: fireDate, isOneOff: overrideIsOneOff)
        }
        set {
            overrideFireDate = newValue?.fireDate
            overrideIsOneOff = newValue?.isOneOff ?? false
        }
    }
}

@Model
final class ProfileStoreSettings {
    var identifier: String = "profile-store-settings"
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool = true

    init(identifier: String = "profile-store-settings",
         activeProfileID: UUID? = nil,
         showRecentActivityOnHome: Bool = true) {
        self.identifier = identifier
        self.activeProfileID = activeProfileID
        self.showRecentActivityOnHome = showRecentActivityOnHome
    }
}

@Model
final class Profile {
    /// Stable identifier used for SwiftData uniqueness and JSON exports.
    var profileID: UUID = UUID()
    var name: String?
    var birthDate: Date?
    @Attribute(.externalStorage)
    var imageData: Data?
    var avatarURL: String?
    var remindersEnabled: Bool = false
    private var updatedAtRawValue: Date = Date()
    @Relationship(deleteRule: .cascade)
    var storedActions: [BabyAction]?
    @Relationship(deleteRule: .cascade)
    var reminderPreferences: [ProfileReminderPreference]?
    var sharePermissionRawValue: String = ProfileSharePermission.edit.rawValue
    var shareStatusRawValue: String?
    var isSharedProfile: Bool = false

    init(profileID: UUID = UUID(),
         name: String? = nil,
         birthDate: Date? = nil,
         imageData: Data? = nil,
         avatarURL: String? = nil,
         remindersEnabled: Bool = false,
         reminderPreferences: [ProfileReminderPreference]? = nil,
         actions: [BabyAction] = []) {
        self.profileID = profileID
        self.name = name
        self.birthDate = birthDate?.normalizedToUTC()
        self.imageData = imageData
        self.avatarURL = avatarURL
        self.remindersEnabled = remindersEnabled
        self.storedActions = actions
        self.updatedAtRawValue = Date()
        if let reminderPreferences {
            self.reminderPreferences = reminderPreferences
        } else {
            self.reminderPreferences = BabyActionCategory.allCases.map { category in
                ProfileReminderPreference(category: category,
                                           interval: Profile.defaultActionReminderInterval,
                                           isEnabled: true,
                                           profile: self)
            }
        }
        ensureActionOwnership()
    }

    var resolvedProfileID: UUID {
        get { profileID }
        set { profileID = newValue }
    }

    var sharePermission: ProfileSharePermission {
        get { ProfileSharePermission(rawValue: sharePermissionRawValue) ?? .edit }
        set { sharePermissionRawValue = newValue.rawValue }
    }

    var shareStatus: ProfileShareStatus? {
        get { shareStatusRawValue.flatMap { ProfileShareStatus(rawValue: $0) } }
        set { shareStatusRawValue = newValue?.rawValue }
    }

    var actions: [BabyAction] {
        get { storedActions ?? [] }
        set {
            storedActions = newValue
            ensureActionOwnership()
        }
    }

    func ensureActionOwnership() {
        guard let currentActions = storedActions else { return }
        var needsUpdate = false
        for index in currentActions.indices where currentActions[index].profile == nil {
            currentActions[index].profile = self
            needsUpdate = true
        }
        if needsUpdate {
            storedActions = currentActions
        }
    }

    var updatedAt: Date {
        get { updatedAtRawValue }
        set { updatedAtRawValue = newValue }
    }

    func touch(_ date: Date = Date()) {
        updatedAt = date
    }
}

typealias ProfileActionStateModel = Profile

extension ProfileActionStateModel {
    static var defaultActionReminderInterval: TimeInterval { 3 * 60 * 60 }

    func reminderPreference(for category: BabyActionCategory) -> ProfileReminderPreference {
        if let existing = reminderPreferences?.first(where: { $0.category == category }) {
            return existing
        }

        let preference = ProfileReminderPreference(category: category,
                                                   interval: Self.defaultActionReminderInterval,
                                                   isEnabled: true,
                                                   profile: self)
        if reminderPreferences == nil {
            reminderPreferences = []
        }
        reminderPreferences?.append(preference)
        return preference
    }

    func reminderInterval(for category: BabyActionCategory) -> TimeInterval {
        let interval = reminderPreference(for: category).interval
        return interval > 0 ? interval : Self.defaultActionReminderInterval
    }

    func setReminderInterval(_ interval: TimeInterval, for category: BabyActionCategory) {
        let normalized = max(0, interval)
        let preference = reminderPreference(for: category)
        preference.interval = normalized > 0 ? normalized : Self.defaultActionReminderInterval
    }

    func isReminderEnabled(for category: BabyActionCategory) -> Bool {
        reminderPreference(for: category).isEnabled
    }

    func setReminderEnabled(_ isEnabled: Bool, for category: BabyActionCategory) {
        let preference = reminderPreference(for: category)
        preference.isEnabled = isEnabled
    }

    func reminderOverride(for category: BabyActionCategory) -> ProfileActionReminderOverride? {
        reminderPreference(for: category).override
    }

    func setReminderOverride(_ override: ProfileActionReminderOverride?,
                             for category: BabyActionCategory,
                             referenceDate: Date = Date()) {
        let preference = reminderPreference(for: category)
        if let override, override.fireDate > referenceDate {
            preference.override = override
        } else {
            preference.override = nil
        }
    }

    func clearReminderOverride(for category: BabyActionCategory) {
        reminderPreference(for: category).override = nil
    }

    func pruneReminderOverrides(referenceDate: Date = Date()) {
        reminderPreferences?.forEach { preference in
            if let override = preference.override, override.fireDate <= referenceDate {
                preference.override = nil
            }
        }
    }

    func normalizeReminderPreferences() {
        for category in BabyActionCategory.allCases {
            let preference = reminderPreference(for: category)
            if preference.interval <= 0 {
                preference.interval = Self.defaultActionReminderInterval
            }
        }
        pruneReminderOverrides()
    }

    func reminderIntervalsByCategory() -> [BabyActionCategory: TimeInterval] {
        var intervals: [BabyActionCategory: TimeInterval] = [:]
        for category in BabyActionCategory.allCases {
            intervals[category] = reminderInterval(for: category)
        }
        return intervals
    }

    func reminderEnabledByCategory() -> [BabyActionCategory: Bool] {
        var values: [BabyActionCategory: Bool] = [:]
        for category in BabyActionCategory.allCases {
            values[category] = isReminderEnabled(for: category)
        }
        return values
    }

    func reminderOverridesByCategory(referenceDate: Date = Date()) -> [BabyActionCategory: ProfileActionReminderOverride] {
        var overrides: [BabyActionCategory: ProfileActionReminderOverride] = [:]
        for category in BabyActionCategory.allCases {
            if let override = reminderOverride(for: category), override.fireDate > referenceDate {
                overrides[category] = override
            }
        }
        return overrides
    }

    func setBirthDate(_ date: Date?) {
        birthDate = date?.normalizedToUTC()
    }

    func makeActionState() -> ProfileActionState {
        ensureActionOwnership()

        var activeActions: [BabyActionCategory: BabyActionSnapshot] = [:]
        var history: [BabyActionSnapshot] = []
        var seenIDs = Set<UUID>()

        for actionModel in actions {
            var action = actionModel.asSnapshot().withValidatedDates()
            guard seenIDs.insert(action.id).inserted else { continue }

            if action.endDate == nil {
                if action.category.isInstant {
                    action.endDate = action.startDate
                    history.append(action)
                } else {
                    if let existing = activeActions[action.category], existing.startDate > action.startDate {
                        continue
                    }
                    activeActions[action.category] = action
                }
            } else {
                history.append(action)
            }
        }

        history.sort { $0.startDate > $1.startDate }
        return ProfileActionState(activeActions: activeActions, history: history)
    }
}

@Model
final class BabyAction {
    /// Stable identifier used to deduplicate actions during merges and exports.
    var id: UUID = UUID()
    private var categoryRawValue: String = BabyActionCategory.sleep.rawValue
    var startDateRawValue: Date = Date().normalizedToUTC()
    private var endDateRawValue: Date?
    var diaperTypeRawValue: String?
    var feedingTypeRawValue: String?
    var bottleTypeRawValue: String?
    var bottleVolume: Int?
    private var updatedAtRawValue: Date = Date()
    private var pendingSyncRawValue = false
    var latitude: Double?
    var longitude: Double?
    var placename: String?
    @Relationship(deleteRule: .nullify, inverse: \Profile.storedActions)
    var profile: Profile?

    init(id: UUID = UUID(),
         category: BabyActionCategory = .sleep,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: BabyActionDiaperType? = nil,
         feedingType: BabyActionFeedingType? = nil,
         bottleType: BabyActionBottleType? = nil,
         bottleVolume: Int? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         placename: String? = nil,
         updatedAt: Date = Date(),
         isPendingSync: Bool = false,
         profile: Profile? = nil) {
        self.id = id
        self.category = category
        self.startDateRawValue = startDate.normalizedToUTC()
        self.endDateRawValue = endDate?.normalizedToUTC()
        self.diaperTypeRawValue = diaperType?.rawValue
        self.feedingTypeRawValue = feedingType?.rawValue
        self.bottleTypeRawValue = bottleType?.rawValue
        self.bottleVolume = bottleVolume
        self.latitude = latitude
        self.longitude = longitude
        self.placename = placename
        self.updatedAtRawValue = updatedAt
        self.pendingSyncRawValue = isPendingSync
        self.profile = profile
    }

    var startDate: Date {
        get { startDateRawValue }
        set { startDateRawValue = newValue.normalizedToUTC() }
    }

    var category: BabyActionCategory {
        get { BabyActionCategory(rawValue: categoryRawValue) ?? .sleep }
        set { categoryRawValue = newValue.rawValue }
    }

    var endDate: Date? {
        get { endDateRawValue }
        set { endDateRawValue = newValue?.normalizedToUTC() }
    }

    var updatedAt: Date {
        get { updatedAtRawValue }
        set { updatedAtRawValue = newValue }
    }

    var isPendingSync: Bool {
        get { pendingSyncRawValue }
        set { pendingSyncRawValue = newValue }
    }
}

typealias BabyActionModel = BabyAction

extension BabyAction {
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

    var diaperType: BabyActionDiaperType? {
        get {
            guard let rawValue = diaperTypeRawValue else { return nil }
            return BabyActionDiaperType(rawValue: rawValue)
        }
        set {
            diaperTypeRawValue = newValue?.rawValue
        }
    }

    var feedingType: BabyActionFeedingType? {
        get {
            guard let rawValue = feedingTypeRawValue else { return nil }
            return BabyActionFeedingType(rawValue: rawValue)
        }
        set {
            feedingTypeRawValue = newValue?.rawValue
        }
    }

    var bottleType: BabyActionBottleType? {
        get {
            guard let rawValue = bottleTypeRawValue else { return nil }
            return BabyActionBottleType(rawValue: rawValue)
        }
        set {
            bottleTypeRawValue = newValue?.rawValue
        }
    }

    func asSnapshot() -> BabyActionSnapshot {
        BabyActionSnapshot(
            id: id,
            category: category,
            startDate: startDate,
            endDate: endDate,
            diaperType: diaperType,
            feedingType: feedingType,
            bottleType: bottleType,
            bottleVolume: bottleVolume,
            latitude: latitude,
            longitude: longitude,
            placename: placename,
            updatedAt: updatedAt
        )
    }

    func update(from action: BabyActionSnapshot) {
        id = action.id
        category = action.category
        startDate = action.startDate
        endDate = action.endDate
        diaperType = action.diaperType
        feedingType = action.feedingType
        bottleType = action.bottleType
        bottleVolume = action.bottleVolume
        latitude = action.latitude
        longitude = action.longitude
        placename = action.placename
        updatedAt = action.updatedAt
    }
}

@MainActor
final class BabyActionFormatter {
    static let shared = BabyActionFormatter()

    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter
    private let timeSinceFormatter: DateComponentsFormatter
    private let twentyFourHourFormatter: DateFormatter

    private init() {
        timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        timeFormatter.timeZone = .current

        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.timeStyle = .short
        dateTimeFormatter.dateStyle = .short
        dateTimeFormatter.timeZone = .current

        durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]

        timeSinceFormatter = DateComponentsFormatter()
        timeSinceFormatter.allowedUnits = [.day, .hour, .minute]
        timeSinceFormatter.unitsStyle = .abbreviated
        timeSinceFormatter.maximumUnitCount = 1
        timeSinceFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]

        twentyFourHourFormatter = DateFormatter()
        twentyFourHourFormatter.locale = Locale(identifier: "en_US_POSIX")
        twentyFourHourFormatter.dateFormat = "HH:mm"
        twentyFourHourFormatter.timeZone = .current
    }

    func format(time: Date) -> String {
        timeFormatter.string(from: time)
    }

    func format(dateTime: Date) -> String {
        dateTimeFormatter.string(from: dateTime)
    }

    func format(time24Hour date: Date) -> String {
        twentyFourHourFormatter.string(from: date)
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
