//
//  ReminderScheduler.swift
//

@preconcurrency import UserNotifications
import Foundation

// MARK: - Abstraction to avoid carrying non-Sendable UNUserNotificationCenter across awaits

protocol UserNotificationCenterType {
    // Use the same argument labels as Apple's APIs
    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void)
    func requestAuthorization(options: UNAuthorizationOptions,
                              completionHandler: @escaping (Bool, Error?) -> Void)
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void)
}

// Conformance for the real center
extension UNUserNotificationCenter: UserNotificationCenterType {}

// MARK: - Scheduler

/// Schedules local notifications for reminders, handling authorization in a Swift 6 sendable-safe way.
@MainActor
final class ReminderScheduler {

    // Inject for testing; defaults to the shared center.
    private let center: any UserNotificationCenterType

    init(center: any UserNotificationCenterType = UNUserNotificationCenter.current()) {
        self.center = center
    }

    /// Ensures the app has (at least) provisional/authorized notification permission.
    /// This version never “carries” `center` across an await, eliminating Swift 6 data-race warnings.
    func ensureAuthorization() async -> Bool {
        // 1) Read current status without suspending while holding `center`
        let status: UNAuthorizationStatus = await withCheckedContinuation { cont in
            let c = center
            c.getNotificationSettings { settings in
                cont.resume(returning: settings.authorizationStatus)
            }
        }

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true

        case .denied:
            return false

        case .notDetermined:
            // 2) Request authorization, again via completion-handler bridging
            do {
                return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                    let c = center
                    c.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume(returning: granted)
                        }
                    }
                }
            } catch {
                return false
            }

        @unknown default:
            return false
        }
    }

    // MARK: - Public scheduling APIs (examples)

    /// Schedule a one-off reminder at a given date.
    /// Returns the request identifier if scheduled.
    func scheduleReminder(id: String = UUID().uuidString,
                          title: String,
                          body: String? = nil,
                          at date: Date) async -> String? {
        let allowed = await ensureAuthorization()
        guard allowed else { return nil }

        // Build content
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        content.sound = .default

        // Trigger (calendar-based)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                    from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        // Use continuation to avoid carrying `center` across an await
        let success: Bool = await withCheckedContinuation { cont in
            let c = center
            c.add(request) { error in
                cont.resume(returning: error == nil)
            }
        }

        return success ? id : nil
    }

    /// Cancel specific reminders by identifiers.
    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Cancel all pending reminders (does not clear delivered notifications).
    func cancelAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    /// Fetch pending requests (useful for debugging/UI).
    /// A Sendable snapshot of a pending notification request.
    struct PendingRequestSummary: Sendable {
        let id: String
        let title: String
        let body: String?
        let nextFireDate: Date?
    }

    func pendingRequests() async -> [PendingRequestSummary] {
        await withCheckedContinuation { cont in
            let c = center
            c.getPendingNotificationRequests { reqs in
                // Snapshot into Sendable data *before* crossing the await boundary.
                let summaries: [PendingRequestSummary] = reqs.map { r in
                    let title = r.content.title
                    let body = r.content.body.isEmpty ? nil : r.content.body

                    // Compute the next fire date locally; don't pass triggers across.
                    let nextDate: Date? = {
                        if let t = r.trigger as? UNCalendarNotificationTrigger {
                            return t.nextTriggerDate()
                        } else if let t = r.trigger as? UNTimeIntervalNotificationTrigger {
                            // For non-repeating time-interval triggers, estimate from now.
                            return t.repeats ? nil : Date().addingTimeInterval(t.timeInterval)
                        } else {
                            return nil
                        }
                    }()

                    return PendingRequestSummary(id: r.identifier,
                                                 title: title,
                                                 body: body,
                                                 nextFireDate: nextDate)
                }
                cont.resume(returning: summaries)
            }
        }
    }

}
