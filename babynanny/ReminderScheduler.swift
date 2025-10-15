import Foundation
import UserNotifications

protocol UserNotificationCenterType: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterType {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

protocol ReminderScheduling {
    func ensureAuthorization() async -> Bool
    func refreshReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState]) async
    func upcomingReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState], reference: Date) async -> [ReminderOverview]
    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool
}

actor UserNotificationReminderScheduler: ReminderScheduling {
    private let center: UserNotificationCenterType
    private var calendar: Calendar
    private let ageIdentifierPrefix = "age-reminder-"
    private let actionIdentifierPrefix = "action-reminder-"
    private let previewIdentifierPrefix = "preview-action-reminder-"
    private let isoFormatter: ISO8601DateFormatter
    private let schedulingWindowMonths = 24
    private let maxNotifications = 64

    init(
        center: UserNotificationCenterType = UNUserNotificationCenter.current(),
        calendar: Calendar = .current
    ) {
        self.center = center
        var calendar = calendar
        calendar.timeZone = TimeZone.current
        self.calendar = calendar
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter = formatter
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
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func refreshReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState]) async {
        let status = await center.authorizationStatus()
        guard status == .authorized ||
            status == .provisional ||
            status == .ephemeral
        else {
            await removePendingReminders()
            return
        }

        var payloads = reminderPayloads(for: profiles, actionStates: actionStates, reference: Date())
            .sorted { $0.fireDate < $1.fireDate }

        guard payloads.isEmpty == false else {
            await removePendingReminders()
            return
        }

        if payloads.count > maxNotifications {
            payloads = Array(payloads.prefix(maxNotifications))
        }

        let existingRequests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ageIdentifierPrefix) || $0.identifier.hasPrefix(actionIdentifierPrefix) }
        let existingByIdentifier = Dictionary(uniqueKeysWithValues: existingRequests.map { ($0.identifier, $0) })
        let existingIdentifiers = Set(existingByIdentifier.keys)
        let newIdentifiers = Set(payloads.map { $0.identifier })

        let identifiersToRemove = existingIdentifiers.subtracting(newIdentifiers)
        if identifiersToRemove.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: Array(identifiersToRemove))
        }

        for payload in payloads {
            let content = UNMutableNotificationContent()
            content.title = payload.contentTitle
            content.body = payload.contentBody
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: payload.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: trigger)

            if let existing = existingByIdentifier[payload.identifier],
               reminderRequest(existing, matchesContent: content, components: components) {
                continue
            }

            schedule(request, retryOnFailure: true)
        }
    }

    func upcomingReminders(for profiles: [ChildProfile], actionStates: [UUID: ProfileActionState], reference: Date) async -> [ReminderOverview] {
        let payloads = reminderPayloads(for: profiles, actionStates: actionStates, reference: reference)
        guard payloads.isEmpty == false else { return [] }

        var sorted = payloads.sorted { $0.fireDate < $1.fireDate }
        if sorted.count > maxNotifications {
            sorted = Array(sorted.prefix(maxNotifications))
        }
        return sorted.map(\.overview)
    }

    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool {
        let authorized = await ensureAuthorization()
        guard authorized else { return false }

        let normalizedDelay = max(60, delay)
        let title = L10n.Notifications.actionReminderTitle(category.title)
        let body = L10n.Notifications.actionReminderMessage(for: category, name: profile.displayName)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let identifier = previewIdentifier(for: profile.id, category: category)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: normalizedDelay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        schedule(request, retryOnFailure: false)

        return true
    }

    private func reminderPayloads(
        for profiles: [ChildProfile],
        actionStates: [UUID: ProfileActionState],
        reference: Date
    ) -> [ReminderPayload] {
        let agePayloads = ageReminderPayloads(for: profiles, reference: reference)
        let actionPayloads = actionReminderPayloads(for: profiles, actionStates: actionStates, reference: reference)
        return agePayloads + actionPayloads
    }

    private func ageReminderPayloads(for profiles: [ChildProfile], reference now: Date) -> [ReminderPayload] {
        guard schedulingWindowMonths > 0 else { return [] }

        let events = profiles
            .filter { $0.remindersEnabled }
            .flatMap { ageReminderEvents(for: $0, reference: now) }

        guard events.isEmpty == false else { return [] }

        let grouped = Dictionary(grouping: events, by: { $0.fireDate })

        return grouped.map { fireDate, events in
            let sortedEvents = events.sorted { lhs, rhs in
                lhs.profileName.localizedCaseInsensitiveCompare(rhs.profileName) == .orderedAscending
            }
            let body = sortedEvents
                .map { L10n.Notifications.ageReminderMessage($0.profileName, $0.monthsOld) }
                .joined(separator: " ")
            let identifier = ageIdentifier(for: fireDate)
            let entries = sortedEvents.map { event in
                ReminderOverview.Entry(
                    profileID: event.profileID,
                    message: L10n.Notifications.ageReminderMessage(event.profileName, event.monthsOld)
                )
            }
            let overview = ReminderOverview(
                identifier: identifier,
                category: .ageMilestone,
                fireDate: fireDate,
                entries: entries
            )

            return ReminderPayload(
                identifier: identifier,
                fireDate: fireDate,
                contentTitle: L10n.Notifications.ageReminderTitle,
                contentBody: body,
                overview: overview
            )
        }
    }

    private func ageReminderEvents(for profile: ChildProfile, reference now: Date) -> [ReminderEvent] {
        let monthsSinceBirth = max(
            calendar.dateComponents([.month], from: profile.birthDate, to: now).month ?? 0,
            0
        )
        let startMonth = max(monthsSinceBirth + 1, 1)
        let endMonth = startMonth + schedulingWindowMonths - 1

        var events: [ReminderEvent] = []
        events.reserveCapacity(schedulingWindowMonths)

        for month in startMonth...endMonth {
            guard let anniversary = calendar.date(byAdding: .month, value: month, to: profile.birthDate) else { continue }
            guard let fireDate = fireDate(for: anniversary) else { continue }
            if fireDate < now { continue }

            events.append(
                ReminderEvent(
                    profileID: profile.id,
                    profileName: profile.displayName,
                    monthsOld: month,
                    fireDate: fireDate
                )
            )
        }

        return events
    }

    private func actionReminderPayloads(
        for profiles: [ChildProfile],
        actionStates: [UUID: ProfileActionState],
        reference now: Date
    ) -> [ReminderPayload] {
        var payloads: [ReminderPayload] = []

        for profile in profiles where profile.remindersEnabled {
            let state = actionStates[profile.id]
            let events = actionReminderEvents(for: profile, state: state, reference: now)

            for event in events {
                let title = L10n.Notifications.actionReminderTitle(event.category.title)
                let body = L10n.Notifications.actionReminderMessage(for: event.category, name: event.profileName)
                let overview = ReminderOverview(
                    identifier: event.identifier,
                    category: .action(event.category),
                    fireDate: event.fireDate,
                    entries: [
                        ReminderOverview.Entry(
                            profileID: event.profileID,
                            message: body
                        )
                    ]
                )

                payloads.append(
                    ReminderPayload(
                        identifier: event.identifier,
                        fireDate: event.fireDate,
                        contentTitle: title,
                        contentBody: body,
                        overview: overview
                    )
                )
            }
        }

        return payloads
    }

    private func actionReminderEvents(
        for profile: ChildProfile,
        state: ProfileActionState?,
        reference now: Date
    ) -> [ActionReminderEvent] {
        var events: [ActionReminderEvent] = []

        for category in BabyActionCategory.allCases {
            let interval = profile.reminderInterval(for: category)
            if interval <= 0 { continue }
            if profile.isActionReminderEnabled(for: category) == false { continue }

            if category.isInstant == false,
               let active = state?.activeAction(for: category),
               active.endDate == nil {
                continue
            }

            let baseline: Date
            if let lastAction = state?.lastCompletedAction(for: category) {
                baseline = lastAction.endDate ?? lastAction.startDate
            } else {
                baseline = now
            }

            var fireDate = baseline.addingTimeInterval(interval)
            let maxIterations = 48
            var iterations = 0
            while fireDate <= now && iterations < maxIterations {
                fireDate = fireDate.addingTimeInterval(interval)
                iterations += 1
            }
            if fireDate <= now {
                fireDate = now.addingTimeInterval(max(interval, 60))
            }

            events.append(
                ActionReminderEvent(
                    identifier: actionIdentifier(for: profile.id, category: category),
                    profileID: profile.id,
                    profileName: profile.displayName,
                    category: category,
                    fireDate: fireDate
                )
            )
        }

        return events
    }

    private func fireDate(for anniversary: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: anniversary)
        components.hour = 10
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private func ageIdentifier(for date: Date) -> String {
        ageIdentifierPrefix + isoFormatter.string(from: date)
    }

    private func actionIdentifier(for profileID: UUID, category: BabyActionCategory) -> String {
        actionIdentifierPrefix + profileID.uuidString + "-" + category.rawValue
    }

    private func previewIdentifier(for profileID: UUID, category: BabyActionCategory) -> String {
        previewIdentifierPrefix + profileID.uuidString + "-" + category.rawValue
    }

    private func currentReminderIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests
            .map(\.identifier)
            .filter { identifier in
                identifier.hasPrefix(ageIdentifierPrefix) || identifier.hasPrefix(actionIdentifierPrefix)
            }
    }

    private func removePendingReminders() async {
        let identifiers = await currentReminderIdentifiers()
        if identifiers.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private func reminderRequest(
        _ request: UNNotificationRequest,
        matchesContent content: UNNotificationContent,
        components: DateComponents
    ) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        guard trigger.repeats == false else { return false }

        let fields: [Calendar.Component] = [.year, .month, .day, .hour, .minute]
        for component in fields {
            if trigger.dateComponents.value(for: component) != components.value(for: component) {
                return false
            }
        }

        return request.content.title == content.title &&
            request.content.body == content.body
    }

    private func schedule(_ request: UNNotificationRequest, retryOnFailure: Bool) {
        let notificationCenter = center
        notificationCenter.add(request) { error in
            #if DEBUG
            if let error {
                print("Failed to schedule reminder: \(error.localizedDescription)")
            }
            #endif

            guard retryOnFailure, error != nil else { return }

            notificationCenter.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            notificationCenter.add(request) { retryError in
                #if DEBUG
                if let retryError {
                    print("Failed to reschedule reminder after removal: \(retryError.localizedDescription)")
                }
                #endif
            }
        }
    }
}

private struct ReminderEvent {
    let profileID: UUID
    let profileName: String
    let monthsOld: Int
    let fireDate: Date
}

private struct ActionReminderEvent {
    let identifier: String
    let profileID: UUID
    let profileName: String
    let category: BabyActionCategory
    let fireDate: Date
}

private struct ReminderPayload {
    let identifier: String
    let fireDate: Date
    let contentTitle: String
    let contentBody: String
    let overview: ReminderOverview
}

struct ReminderOverview: Identifiable, Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let profileID: UUID
        let message: String
    }

    enum Category: Equatable, Sendable {
        case ageMilestone
        case action(BabyActionCategory)

        var localizedTitle: String {
            switch self {
            case .ageMilestone:
                return L10n.Notifications.ageReminderTitle
            case .action(let category):
                return L10n.Notifications.actionReminderOverviewTitle(category.title)
            }
        }
    }

    let identifier: String
    let category: Category
    let fireDate: Date
    let entries: [Entry]

    var id: String { identifier }

    var combinedMessage: String {
        entries.map(\.message).joined(separator: " ")
    }

    func message(for profileID: UUID) -> String? {
        entries.first(where: { $0.profileID == profileID })?.message
    }

    func includes(profileID: UUID) -> Bool {
        entries.contains(where: { $0.profileID == profileID })
    }
}
