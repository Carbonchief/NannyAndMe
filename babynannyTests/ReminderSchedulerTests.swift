import Foundation
import Testing
import UserNotifications
@testable import babynanny

@Suite("Reminder Scheduler")
struct ReminderSchedulerTests {
    @Test
    func reschedulesAfterBirthDateChange() async throws {
        let center = MockUserNotificationCenter()
        let scheduler = UserNotificationReminderScheduler(center: center, calendar: .gregorianCurrent)

        var profile = ChildProfile(
            name: "Alex",
            birthDate: Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date(),
            remindersEnabled: true
        )

        await scheduler.refreshReminders(for: [profile], actionStates: [:])
        #expect(center.pendingRequests.isEmpty == false)

        let previousIdentifiers = Set(center.pendingRequests.map(\.identifier))

        profile.birthDate = Calendar.current.date(byAdding: .month, value: -6, to: profile.birthDate) ?? profile.birthDate
        await scheduler.refreshReminders(for: [profile], actionStates: [:])

        let updatedIdentifiers = Set(center.pendingRequests.map(\.identifier))
        let removedIdentifiers = previousIdentifiers.subtracting(updatedIdentifiers)

        #expect(removedIdentifiers.isEmpty == false)
        #expect(center.removedIdentifiersHistory.flatMap { $0 }.contains(where: removedIdentifiers.contains))
    }

    @Test
    func removesAndReschedulesWhenUpdateFails() async throws {
        let center = MockUserNotificationCenter()
        let scheduler = UserNotificationReminderScheduler(center: center, calendar: .gregorianCurrent)

        var profile = ChildProfile(
            name: "Maya",
            birthDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
            remindersEnabled: true
        )

        await scheduler.refreshReminders(for: [profile], actionStates: [:])
        guard let targetIdentifier = center.pendingRequests.first?.identifier else {
            Issue.record("No reminder scheduled for profile")
            return
        }

        center.addFailures[targetIdentifier] = 1

        profile.name = "Amelia"
        await scheduler.refreshReminders(for: [profile], actionStates: [:])

        #expect(center.addCallCounts[targetIdentifier] == 2)
        #expect(center.removedIdentifiersHistory.flatMap { $0 }.contains(targetIdentifier))
        let updatedRequest = center.pendingRequests.first { $0.identifier == targetIdentifier }
        #expect(updatedRequest?.content.body.contains("Amelia") == true)
    }

    @Test
    func updatesActionReminderSchedulingWhenSettingsChange() async throws {
        let center = MockUserNotificationCenter()
        let scheduler = UserNotificationReminderScheduler(center: center, calendar: .gregorianCurrent)

        var profile = ChildProfile(
            name: "Noah",
            birthDate: Calendar.current.date(byAdding: .month, value: -4, to: Date()) ?? Date(),
            remindersEnabled: true
        )

        await scheduler.refreshReminders(for: [profile], actionStates: [:])

        let profileID = profile.id
        let sleepIdentifier = actionIdentifier(for: profileID, category: .sleep)
        let feedingIdentifier = actionIdentifier(for: profileID, category: .feeding)
        let diaperIdentifier = actionIdentifier(for: profileID, category: .diaper)

        let initialIdentifiers = pendingActionIdentifiers(in: center)
        #expect(initialIdentifiers.contains(sleepIdentifier))
        #expect(initialIdentifiers.contains(feedingIdentifier))
        #expect(initialIdentifiers.contains(diaperIdentifier))

        profile.setReminderEnabled(false, for: .feeding)

        await scheduler.refreshReminders(for: [profile], actionStates: [:])

        let updatedIdentifiers = pendingActionIdentifiers(in: center)
        #expect(updatedIdentifiers.contains(sleepIdentifier))
        #expect(updatedIdentifiers.contains(diaperIdentifier))
        #expect(updatedIdentifiers.contains(feedingIdentifier) == false)
        #expect(center.removedIdentifiersHistory.flatMap { $0 }.contains(feedingIdentifier))
    }
}

// MARK: - Helpers

private final class MockUserNotificationCenter: UserNotificationCenterType {
    var authorizationStatusValue: UNAuthorizationStatus = .authorized
    var requestAuthorizationOptions: UNAuthorizationOptions?
    var requestAuthorizationResult: Bool = true
    private(set) var pendingRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiersHistory: [[String]] = []
    var addCallCounts: [String: Int] = [:]
    var addFailures: [String: Int] = [:]

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationOptions = options
        return requestAuthorizationResult
    }

    func pendingNotificationRequestSnapshots() async -> [NotificationRequestSnapshot] {
        pendingRequests.map(NotificationRequestSnapshot.init)
    }

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        addCallCounts[request.identifier, default: 0] += 1

        if let remainingFailures = addFailures[request.identifier], remainingFailures > 0 {
            addFailures[request.identifier] = remainingFailures - 1
            completionHandler?(TestError.addFailed)
            return
        }

        pendingRequests.removeAll { $0.identifier == request.identifier }
        pendingRequests.append(request)
        completionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiersHistory.append(identifiers)
        pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }
}

private enum TestError: Error {
    case addFailed
}

private func actionIdentifier(for profileID: UUID, category: BabyActionCategory) -> String {
    "action-reminder-" + profileID.uuidString + "-" + category.rawValue
}

private func pendingActionIdentifiers(in center: MockUserNotificationCenter) -> Set<String> {
    Set(
        center.pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix("action-reminder-") }
    )
}

private extension Calendar {
    static var gregorianCurrent: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }
}
