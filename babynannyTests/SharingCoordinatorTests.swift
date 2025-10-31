import CloudKit
import SwiftData
import Testing
@testable import babynanny

@MainActor
private final class MockCloudKitManager: CloudKitManager {
    private(set) var savedActionChunks: [[BabyAction]] = []
    private(set) var deletedRecordCalls: [[CKRecord.ID]] = []

    init(dataStack: AppDataStack) {
        let bridge = SwiftDataBridge(dataStack: dataStack)
        super.init(containerIdentifier: "com.prioritybit.nannyandme.tests",
                   bridge: bridge,
                   userDefaults: UserDefaults())
    }

    override func saveActions(_ actions: [BabyAction],
                              for profile: Profile,
                              scope: CKDatabase.Scope = .private,
                              zoneID providedZoneID: CKRecordZone.ID? = nil) async throws {
        savedActionChunks.append(actions)
    }

    override func deleteRecords(_ recordIDs: [CKRecord.ID], scope: CKDatabase.Scope = .private) async throws {
        deletedRecordCalls.append(recordIDs)
    }
}

@Test
@MainActor
func synchronizesLargeActionBatchesInChunks() async throws {
    let modelContainer = AppDataStack.makeModelContainer(inMemory: true)
    let dataStack = AppDataStack(modelContainer: modelContainer)
    let cloudKitManager = MockCloudKitManager(dataStack: dataStack)
    let coordinator = SharingCoordinator(cloudKitManager: cloudKitManager, dataStack: dataStack, autoLoad: false)

    let profileID = UUID()
    let profile = Profile(profileID: profileID)
    dataStack.mainContext.insert(profile)

    let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
    let rootRecordID = CKRecord.ID(recordName: "root", zoneID: zoneID)
    let shareRecordID = CKRecord.ID(recordName: "share", zoneID: zoneID)
    let seedContext = SharingCoordinator.ShareContext(id: profileID,
                                                      zoneID: zoneID,
                                                      rootRecordID: rootRecordID,
                                                      shareRecordID: shareRecordID,
                                                      share: nil,
                                                      isOwner: true,
                                                      lastKnownTitle: nil,
                                                      lastSyncedActions: SharingCoordinator.ShareContext.makeActionMetadata(from: profile.actions))
    coordinator.debugSetShareContext(seedContext)

    let baseDate = Date()
    let actions: [BabyAction] = (0..<250).map { index in
        BabyAction(id: UUID(),
                   category: .sleep,
                   startDate: baseDate.addingTimeInterval(TimeInterval(index * 60)),
                   updatedAt: baseDate.addingTimeInterval(TimeInterval(index)),
                   profile: profile)
    }
    profile.actions = actions

    await coordinator.synchronizeActionsForTesting(profileID: profileID)

    #expect(cloudKitManager.deletedRecordCalls.isEmpty)
    #expect(cloudKitManager.savedActionChunks.count == 2)
    #expect(cloudKitManager.savedActionChunks.first?.count == 200)
    #expect(cloudKitManager.savedActionChunks.last?.count == 50)

    let syncedActionIDs = Set(cloudKitManager.savedActionChunks.flatMap { $0 }.map { $0.id })
    #expect(syncedActionIDs == Set(actions.map { $0.id }))

    let updatedContext = coordinator.shareContext(for: profileID)
    #expect(updatedContext?.lastSyncedActions.count == actions.count)
    for action in actions {
        #expect(updatedContext?.lastSyncedActions[action.id] == action.updatedAt)
    }
}
