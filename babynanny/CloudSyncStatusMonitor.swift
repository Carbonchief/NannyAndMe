import CloudKit
import Foundation
import os

@MainActor
final class CloudSyncStatusMonitor: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastSyncDate: Date?

    private let container: CKContainer
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "cloud-status")

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
        lastSyncDate = UserDefaults.standard.object(forKey: AppDataStack.lastCloudSyncDefaultsKey) as? Date
        registerObservers()
        Task { await refreshStatus() }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refreshStatus() async {
        status = .checking
        do {
            let accountStatus = try await container.accountStatus()
            status = Status(accountStatus)
        } catch {
            logger.error("CloudKit account status failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    func updateLastSyncDate(to date: Date) {
        lastSyncDate = date
    }

    private func registerObservers() {
        let accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshStatus() }
        }
        observers.append(accountObserver)

        let syncObserver = NotificationCenter.default.addObserver(
            forName: AppDataStack.cloudSyncDidSaveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let date = notification.object as? Date {
                self.lastSyncDate = date
            } else if let stored = UserDefaults.standard.object(forKey: AppDataStack.lastCloudSyncDefaultsKey) as? Date {
                self.lastSyncDate = stored
            }
        }
        observers.append(syncObserver)
    }
}

private extension CloudSyncStatusMonitor.Status {
    init(_ accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        @unknown default:
            self = .error("Unknown status")
        }
    }
}
