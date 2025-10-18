import SwiftData
import Testing
@testable import babynanny

@MainActor
private final class MockSyncCoordinatorObserver: SyncCoordinator.Observer {
    private(set) var receivedReasons: [SyncCoordinator.SyncReason] = []

    func syncCoordinator(_ coordinator: SyncCoordinator,
                         didMergeChangesFor reason: SyncCoordinator.SyncReason) {
        receivedReasons.append(reason)
    }
}

@Test
@MainActor
func notifiesObserversAfterRemoteSync() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: [ProfileActionStateModel.self, BabyActionModel.self],
        configurations: configuration
    )
    let coordinator = SyncCoordinator(sharedContext: container.mainContext)
    let observer = MockSyncCoordinatorObserver()
    coordinator.addObserver(observer)

    coordinator.requestSyncIfNeeded(reason: .remoteNotification)
    try await Task.sleep(nanoseconds: 400_000_000)

    #expect(observer.receivedReasons.contains(.remoteNotification))
}
