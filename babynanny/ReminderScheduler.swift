@preconcurrency import UserNotifications
import Foundation

@MainActor
protocol ReminderScheduling: AnyObject {
    func ensureAuthorization() async -> Bool
    func refreshReminders(for profiles: [ChildProfile],
                          actionStates: [UUID: ProfileActionState]) async
    func upcomingReminders(for profiles: [ChildProfile],
                           actionStates: [UUID: ProfileActionState],
                           reference: Date) async -> [ReminderOverview]
    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool
}

struct ReminderOverview: Equatable, Sendable {
    enum Category: Equatable, Sendable {
        case ageMilestone
        case action(BabyActionCategory)
    }

    struct Entry: Equatable, Sendable {
        let profileID: UUID
        let message: String
    }

    let identifier: String
    let category: Category
    let fireDate: Date
    let entries: [Entry]

    func includes(profileID: UUID) -> Bool {
        entries.contains(where: { $0.profileID == profileID })
    }

    func message(for profileID: UUID) -> String? {
        entries.first(where: { $0.profileID == profileID })?.message
    }
}

struct NotificationRequestSnapshot: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let nextFireDate: Date?

    init(identifier: String, title: String, body: String, nextFireDate: Date?) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.nextFireDate = nextFireDate
    }

    init(request: UNNotificationRequest) {
        identifier = request.identifier
        title = request.content.title
        body = request.content.body

        if let calendarTrigger = request.trigger as? UNCalendarNotificationTrigger {
            nextFireDate = calendarTrigger.nextTriggerDate()
        } else if let intervalTrigger = request.trigger as? UNTimeIntervalNotificationTrigger, intervalTrigger.repeats == false {
            nextFireDate = Date().addingTimeInterval(intervalTrigger.timeInterval)
        } else {
            nextFireDate = nil
        }
    }
}

private extension NotificationRequestSnapshot {
    func matches(plan: UserNotificationReminderScheduler.ReminderPlan, tolerance: TimeInterval = 5) -> Bool {
        guard title == plan.title, body == plan.body else { return false }
        guard let nextFireDate else { return false }
        return abs(nextFireDate.timeIntervalSince(plan.fireDate)) <= tolerance
    }
}

@MainActor
protocol UserNotificationCenterType: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequestSnapshots() async -> [NotificationRequestSnapshot]
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
extension UNUserNotificationCenter: UserNotificationCenterType {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            let center = self
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let center = self
            center.requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func pendingNotificationRequestSnapshots() async -> [NotificationRequestSnapshot] {
        await withCheckedContinuation { continuation in
            let center = self
            center.getPendingNotificationRequests { requests in
                let snapshots = requests.map(NotificationRequestSnapshot.init)
                continuation.resume(returning: snapshots)
            }
        }
    }
}

@MainActor
final class UserNotificationReminderScheduler: ReminderScheduling {
    fileprivate struct ReminderPlan: Sendable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
        let category: ReminderOverview.Category
        let entries: [ReminderOverview.Entry]

        func makeRequest(calendar: Calendar) -> UNNotificationRequest {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            components.nanosecond = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }

        func overview() -> ReminderOverview {
            ReminderOverview(identifier: identifier, category: category, fireDate: fireDate, entries: entries)
        }
    }

    private static let actionIdentifierPrefix = "action-reminder-"
    private static let ageIdentifierPrefix = "age-milestone-"
    private static let previewIdentifierPrefix = "preview-reminder-"

    private let center: any UserNotificationCenterType
    private var calendar: Calendar

    init(center: any UserNotificationCenterType = UNUserNotificationCenter.current(),
         calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func ensureAuthorization() async -> Bool {
        let status = await center.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func refreshReminders(for profiles: [ChildProfile],
                          actionStates: [UUID: ProfileActionState]) async {
        let isAuthorized = await ensureAuthorization()
        let existingSnapshots = await center.pendingNotificationRequestSnapshots().filter { identifierIsManaged($0.identifier) }

        guard isAuthorized else {
            removeExistingIdentifiers(existingSnapshots.map(\.identifier))
            return
        }

        let plans = makeReminderPlans(for: profiles, actionStates: actionStates, reference: Date())
        let desiredIdentifiers = Set(plans.map(\.identifier))

        let staleIdentifiers = existingSnapshots.map(\.identifier).filter { desiredIdentifiers.contains($0) == false }
        removeExistingIdentifiers(staleIdentifiers)

        let existingByIdentifier = Dictionary(uniqueKeysWithValues: existingSnapshots.map { ($0.identifier, $0) })

        for plan in plans {
            let existing = existingByIdentifier[plan.identifier]
            await schedule(plan: plan, existing: existing)
        }
    }

    func upcomingReminders(for profiles: [ChildProfile],
                           actionStates: [UUID: ProfileActionState],
                           reference: Date) async -> [ReminderOverview] {
        makeReminderPlans(for: profiles, actionStates: actionStates, reference: reference)
            .sorted(by: { $0.fireDate < $1.fireDate })
            .map { $0.overview() }
    }

    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool {
        guard await ensureAuthorization() else { return false }

        let identifier = Self.previewIdentifierPrefix + UUID().uuidString
        let title = L10n.Notifications.actionReminderTitle(category.title)
        let body = L10n.Notifications.actionReminderMessage(for: category, name: profile.displayName)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let normalizedDelay = max(1, delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: normalizedDelay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        return await add(request)
    }
}

private extension UserNotificationReminderScheduler {
    func makeReminderPlans(for profiles: [ChildProfile],
                           actionStates: [UUID: ProfileActionState],
                           reference: Date) -> [ReminderPlan] {
        var plans: [ReminderPlan] = []
        for profile in profiles where profile.remindersEnabled {
            if let agePlan = makeAgeReminderPlan(for: profile, reference: reference) {
                plans.append(agePlan)
            }

            let state = actionStates[profile.id]
            for category in BabyActionCategory.allCases {
                guard profile.isActionReminderEnabled(for: category) else { continue }
                if let plan = makeActionReminderPlan(for: profile, category: category, state: state, reference: reference) {
                    plans.append(plan)
                }
            }
        }
        return plans
    }

    func makeAgeReminderPlan(for profile: ChildProfile, reference: Date) -> ReminderPlan? {
        let birthDate = profile.birthDate.normalizedToUTC()
        guard birthDate <= reference else { return nil }

        let components = calendar.dateComponents([.month], from: birthDate, to: reference)
        var nextMonthCount = max((components.month ?? 0) + 1, 1)
        let maximumMonths = 36
        var nextFireDate: Date?

        while nextMonthCount <= maximumMonths {
            if let candidate = calendar.date(byAdding: .month, value: nextMonthCount, to: birthDate), candidate > reference {
                nextFireDate = candidate
                break
            }
            nextMonthCount += 1
        }

        guard let fireDate = nextFireDate else { return nil }

        let title = L10n.Notifications.ageReminderTitle
        let body = L10n.Notifications.ageReminderMessage(profile.displayName, nextMonthCount)
        let entry = ReminderOverview.Entry(profileID: profile.id, message: body)

        return ReminderPlan(identifier: Self.ageIdentifier(for: profile.id),
                             fireDate: fireDate,
                             title: title,
                             body: body,
                             category: .ageMilestone,
                             entries: [entry])
    }

    func makeActionReminderPlan(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 state: ProfileActionState?,
                                 reference: Date) -> ReminderPlan? {
        if let override = profile.actionReminderOverride(for: category), override.fireDate > reference {
            let title = L10n.Notifications.actionReminderTitle(category.title)
            let body = L10n.Notifications.actionReminderMessage(for: category, name: profile.displayName)
            let entry = ReminderOverview.Entry(profileID: profile.id, message: body)
            return ReminderPlan(identifier: Self.actionIdentifier(for: profile.id, category: category),
                                 fireDate: override.fireDate,
                                 title: title,
                                 body: body,
                                 category: .action(category),
                                 entries: [entry])
        }

        let interval = max(profile.reminderInterval(for: category), 60)
        var baseline = reference

        if let state {
            if let active = state.activeAction(for: category) {
                baseline = active.endDate ?? active.startDate
            } else if let completed = state.lastCompletedAction(for: category) {
                baseline = completed.endDate ?? completed.startDate
            }
        }

        let candidate = baseline.addingTimeInterval(interval)
        let fireDate = candidate > reference ? candidate : reference.addingTimeInterval(interval)

        guard fireDate > reference else { return nil }

        let title = L10n.Notifications.actionReminderTitle(category.title)
        let body = L10n.Notifications.actionReminderMessage(for: category, name: profile.displayName)
        let entry = ReminderOverview.Entry(profileID: profile.id, message: body)

        return ReminderPlan(identifier: Self.actionIdentifier(for: profile.id, category: category),
                             fireDate: fireDate,
                             title: title,
                             body: body,
                             category: .action(category),
                             entries: [entry])
    }

    func schedule(plan: ReminderPlan, existing: NotificationRequestSnapshot?) async {
        if let existing, existing.matches(plan: plan) {
            return
        }

        let request = plan.makeRequest(calendar: calendar)

        if existing != nil {
            removeExistingIdentifiers([plan.identifier])
        }

        if await add(request) == false {
            removeExistingIdentifiers([plan.identifier])
            _ = await add(request)
        }
    }

    func add(_ request: UNNotificationRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func identifierIsManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix(Self.actionIdentifierPrefix) || identifier.hasPrefix(Self.ageIdentifierPrefix)
    }

    func removeExistingIdentifiers(_ identifiers: [String]) {
        guard identifiers.isEmpty == false else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func actionIdentifier(for profileID: UUID, category: BabyActionCategory) -> String {
        actionIdentifierPrefix + profileID.uuidString + "-" + category.rawValue
    }

    static func ageIdentifier(for profileID: UUID) -> String {
        ageIdentifierPrefix + profileID.uuidString
    }
}
