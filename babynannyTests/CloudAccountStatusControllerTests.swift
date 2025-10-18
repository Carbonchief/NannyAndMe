import CloudKit
import XCTest
@testable import babynanny

@MainActor
final class CloudAccountStatusControllerTests: XCTestCase {
    func testAccountStatusAvailable() async {
        let provider = MockAccountStatusProvider(statuses: [.available])
        let defaults = UserDefaults(suiteName: "CloudAccountStatusControllerTests.available")!
        defaults.removePersistentDomain(forName: "CloudAccountStatusControllerTests.available")
        let controller = CloudAccountStatusController(provider: provider,
                                                      notificationCenter: NotificationCenter(),
                                                      userDefaults: defaults)
        await Task.yield()
        XCTAssertEqual(controller.status, .available)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testSelectingLocalOnlyPreventsFutureChecksUntilEnabled() async {
        let provider = MockAccountStatusProvider(statuses: [.needsAccount])
        let defaults = UserDefaults(suiteName: "CloudAccountStatusControllerTests.localOnly")!
        defaults.removePersistentDomain(forName: "CloudAccountStatusControllerTests.localOnly")
        let controller = CloudAccountStatusController(provider: provider,
                                                      notificationCenter: NotificationCenter(),
                                                      userDefaults: defaults)
        await Task.yield()
        controller.selectLocalOnly()
        XCTAssertEqual(controller.status, .localOnly)
        controller.refreshAccountStatus()
        await Task.yield()
        XCTAssertEqual(controller.status, .localOnly)
        XCTAssertEqual(provider.callCount, 1)

        provider.statuses = [.available]
        controller.enableCloudSync()
        await Task.yield()
        XCTAssertEqual(controller.status, .available)
        XCTAssertTrue(provider.callCount >= 2)
    }

    func testNotificationTriggersRefresh() async {
        let notificationCenter = NotificationCenter()
        let provider = MockAccountStatusProvider(statuses: [.available, .noAccount])
        let defaults = UserDefaults(suiteName: "CloudAccountStatusControllerTests.notification")!
        defaults.removePersistentDomain(forName: "CloudAccountStatusControllerTests.notification")
        let controller = CloudAccountStatusController(provider: provider,
                                                      notificationCenter: notificationCenter,
                                                      userDefaults: defaults)
        await Task.yield()
        XCTAssertEqual(controller.status, .available)
        notificationCenter.post(name: .CKAccountChanged, object: nil)
        await Task.yield()
        XCTAssertEqual(controller.status, .needsAccount)
    }
}

@MainActor
private final class MockAccountStatusProvider: CloudAccountStatusProviding {
    var statuses: [CKAccountStatus]
    private(set) var callCount = 0

    init(statuses: [CKAccountStatus]) {
        self.statuses = statuses
    }

    func accountStatus() async throws -> CKAccountStatus {
        callCount += 1
        if statuses.isEmpty {
            return .noAccount
        }
        return statuses.removeFirst()
    }
}
