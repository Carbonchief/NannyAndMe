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
    func refreshReminders(for profiles: [ChildProfile]) async
    func upcomingReminders(for profiles: [ChildProfile], reference: Date) async -> [ReminderOverview]
}

actor UserNotificationReminderScheduler: ReminderScheduling {
    private let center: UserNotificationCenterType
    private var calendar: Calendar
    private let identifierPrefix = "age-reminder-"
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

    func refreshReminders(for profiles: [ChildProfile]) async {
        let status = await center.authorizationStatus()
        guard status == .authorized ||
            status == .provisional ||
            status == .ephemeral
        else {
            await removePendingAgeReminders()
            return
        }

        let now = Date()
        let events = profiles
            .filter { $0.remindersEnabled }
            .flatMap { upcomingEvents(for: $0, reference: now) }

        guard events.isEmpty == false else {
            await removePendingAgeReminders()
            return
        }

        let grouped = Dictionary(grouping: events, by: { $0.fireDate })
        var groups = grouped.map { fireDate, events -> ReminderGroup in
            let sorted = events.sorted { lhs, rhs in
                lhs.profileName.localizedCaseInsensitiveCompare(rhs.profileName) == .orderedAscending
            }
            return ReminderGroup(fireDate: fireDate, events: sorted)
        }
        .sorted { $0.fireDate < $1.fireDate }

        if groups.count > maxNotifications {
            groups = Array(groups.prefix(maxNotifications))
        }

        let existingRequests = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
        let existingByIdentifier = Dictionary(uniqueKeysWithValues: existingRequests.map { ($0.identifier, $0) })
        let existingIdentifiers = Set(existingByIdentifier.keys)
        let newIdentifiers = Set(groups.map { identifier(for: $0.fireDate) })

        let identifiersToRemove = existingIdentifiers.subtracting(newIdentifiers)
        if identifiersToRemove.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: Array(identifiersToRemove))
        }

        for group in groups {
            let content = UNMutableNotificationContent()
            content.title = L10n.Notifications.ageReminderTitle
            content.body = group.events
                .map { L10n.Notifications.ageReminderMessage($0.profileName, $0.monthsOld) }
                .joined(separator: " ")
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: group.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier = identifier(for: group.fireDate)

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            if let existing = existingByIdentifier[identifier],
               reminderRequest(existing, matchesContent: content, components: components) {
                continue
            }

            schedule(request, retryOnFailure: true)
        }
    }

    func upcomingReminders(for profiles: [ChildProfile], reference: Date) async -> [ReminderOverview] {
        let events = profiles
            .filter { $0.remindersEnabled }
            .flatMap { upcomingEvents(for: $0, reference: reference) }

        guard events.isEmpty == false else { return [] }

        let grouped = Dictionary(grouping: events, by: { $0.fireDate })

        let summaries: [ReminderOverview] = grouped.map { fireDate, events in
            let entries = events.map { event in
                ReminderOverview.Entry(
                    profileID: event.profileID,
                    message: L10n.Notifications.ageReminderMessage(event.profileName, event.monthsOld)
                )
            }

            return ReminderOverview(
                identifier: identifier(for: fireDate),
                category: .ageMilestone,
                fireDate: fireDate,
                entries: entries
            )
        }
        .sorted { $0.fireDate < $1.fireDate }

        return summaries
    }

    private func upcomingEvents(for profile: ChildProfile, reference now: Date) -> [ReminderEvent] {
        guard schedulingWindowMonths > 0 else { return [] }

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

    private func fireDate(for anniversary: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: anniversary)
        components.hour = 10
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private func identifier(for date: Date) -> String {
        identifierPrefix + isoFormatter.string(from: date)
    }

    private func currentReminderIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
    }

    private func removePendingAgeReminders() async {
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

private struct ReminderGroup {
    let fireDate: Date
    let events: [ReminderEvent]
}

struct ReminderOverview: Identifiable, Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let profileID: UUID
        let message: String
    }

    enum Category: Equatable, Sendable {
        case ageMilestone

        var localizedTitle: String {
            switch self {
            case .ageMilestone:
                return L10n.Notifications.ageReminderTitle
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
