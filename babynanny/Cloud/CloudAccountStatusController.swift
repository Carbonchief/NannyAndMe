import CloudKit
import Combine
import Foundation
import os

@MainActor
protocol CloudAccountStatusProviding {
    func accountStatus() async throws -> CKAccountStatus
}

extension CloudAccountStatusController.Status {
    var analyticsValue: String {
        switch self {
        case .available:
            return "available"
        case .needsAccount:
            return "needs_account"
        case .localOnly:
            return "local_only"
        case .loading:
            return "loading"
        }
    }
}

@MainActor
final class CloudKitAccountStatusProvider: CloudAccountStatusProviding {
    private let container: CKContainer

    init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

@MainActor
final class CloudAccountStatusController: ObservableObject {
    enum Status: Equatable {
        case loading
        case available
        case needsAccount
        case localOnly
    }

    @Published private(set) var status: Status

    private let provider: CloudAccountStatusProviding
    private let notificationCenter: NotificationCenter
    private let userDefaults: UserDefaults
    private let stayLocalKey = "com.prioritybit.babynanny.cloud.localOnly"
    private var notificationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "cloud.accountStatus")

    init(containerIdentifier: String = "iCloud.com.prioritybit.babynanny",
         provider: CloudAccountStatusProviding? = nil,
         notificationCenter: NotificationCenter = .default,
         userDefaults: UserDefaults = .standard) {
        let resolvedProvider = provider ?? CloudKitAccountStatusProvider(containerIdentifier: containerIdentifier)
        self.provider = resolvedProvider
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        if userDefaults.bool(forKey: stayLocalKey) {
            status = .localOnly
        } else {
            status = .loading
        }
        observeAccountChanges()
        if status != .localOnly {
            refreshAccountStatus()
        }
    }

    deinit {
        notificationTask?.cancel()
        refreshTask?.cancel()
    }

    func refreshAccountStatus(force: Bool = false) {
        guard force || userDefaults.bool(forKey: stayLocalKey) == false else {
            status = .localOnly
            return
        }
        status = .loading
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let accountStatus = try await provider.accountStatus()
                await applyStatus(for: accountStatus)
            } catch {
                logger.error("Failed to determine CloudKit account status: \(error.localizedDescription, privacy: .public)")
                status = .needsAccount
            }
        }
    }

    func selectLocalOnly() {
        userDefaults.set(true, forKey: stayLocalKey)
        status = .localOnly
    }

    func enableCloudSync() {
        userDefaults.set(false, forKey: stayLocalKey)
        refreshAccountStatus(force: true)
    }

    private func observeAccountChanges() {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in notificationCenter.notifications(named: .CKAccountChanged) {
                guard self.userDefaults.bool(forKey: self.stayLocalKey) == false else { continue }
                self.refreshAccountStatus(force: true)
            }
        }
    }

    private func applyStatus(for accountStatus: CKAccountStatus) {
        switch accountStatus {
        case .available:
            status = .available
        case .noAccount, .restricted:
            status = .needsAccount
        case .couldNotDetermine, .temporarilyUnavailable:
            status = .needsAccount
        @unknown default:
            status = .needsAccount
        }
    }
}

#if DEBUG
extension CloudAccountStatusController {
    static func previewController(status: Status = .available) -> CloudAccountStatusController {
        final class PreviewProvider: CloudAccountStatusProviding {
            let status: CKAccountStatus

            init(status: CKAccountStatus) {
                self.status = status
            }

            func accountStatus() async throws -> CKAccountStatus {
                status
            }
        }

        let defaults = UserDefaults(suiteName: "com.prioritybit.babynanny.preview.cloudStatus")!
        defaults.removePersistentDomain(forName: "com.prioritybit.babynanny.preview.cloudStatus")

        let ckStatus: CKAccountStatus
        switch status {
        case .available:
            ckStatus = .available
        case .needsAccount:
            ckStatus = .noAccount
        case .localOnly:
            ckStatus = .available
        case .loading:
            ckStatus = .available
        }

        let controller = CloudAccountStatusController(provider: PreviewProvider(status: ckStatus),
                                                      notificationCenter: .init(),
                                                      userDefaults: defaults)

        switch status {
        case .localOnly:
            controller.selectLocalOnly()
        case .needsAccount:
            controller.refreshAccountStatus(force: true)
        case .available, .loading:
            break
        }

        return controller
    }
}
#endif
