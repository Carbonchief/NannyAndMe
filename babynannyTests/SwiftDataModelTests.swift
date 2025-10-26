import CloudKit
import SwiftData
import XCTest
@testable import babynanny

final class SwiftDataModelTests: XCTestCase {
    func testProfileDeleteCascadesToActions() throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let profile = ProfileActionStateModel(profileID: UUID())
        context.insert(profile)
        let action = BabyActionModel(profile: profile)
        context.insert(action)
        try context.save()

        context.delete(profile)
        try context.save()

        let descriptor = FetchDescriptor<BabyActionModel>()
        let remainingActions = try context.fetch(descriptor)
        XCTAssertTrue(remainingActions.isEmpty)
    }

    @MainActor
    func testActionMergeDeduplicatesByIdentifier() throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = AppDataStack(modelContainer: container)
        let store = ActionLogStore(modelContext: container.mainContext, dataStack: stack)
        let profileID = UUID()
        let actionID = UUID()

        let older = BabyActionSnapshot(
            id: actionID,
            category: .sleep,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: nil,
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        let newer = BabyActionSnapshot(
            id: actionID,
            category: .sleep,
            startDate: Date(),
            endDate: nil,
            updatedAt: Date()
        )

        let state = ProfileActionState(history: [older, newer])
        store.persist(profileState: state, for: profileID)
        try container.mainContext.save()

        let descriptor = FetchDescriptor<BabyActionModel>()
        let storedActions = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(storedActions.count, 1)
        XCTAssertEqual(storedActions.first?.updatedAt, newer.updatedAt)
    }

    @MainActor
    func testMergingImportedStateAddsActions() throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = AppDataStack(modelContainer: container)
        let store = ActionLogStore(modelContext: container.mainContext, dataStack: stack)
        let profileID = UUID()

        let importedAction = BabyActionSnapshot(
            id: UUID(),
            category: .feeding,
            startDate: Date(),
            endDate: Date(),
            updatedAt: Date()
        )

        let importedState = ProfileActionState(history: [importedAction])
        let summary = store.mergeProfileState(importedState, for: profileID)
        XCTAssertEqual(summary.added, 1)

        let descriptor = FetchDescriptor<BabyActionModel>()
        let storedActions = try container.mainContext.fetch(descriptor)
        XCTAssertEqual(storedActions.count, 1)
        XCTAssertEqual(storedActions.first?.category, .feeding)
    }

    @MainActor
    func testShareCreationReturnsShare() async throws {
        guard #available(iOS 17.4, *) else {
            throw XCTSkip("Cloud sharing requires iOS 17.4 or newer")
        }

        let container = AppDataStack.makeModelContainer(inMemory: true)
        let context = container.mainContext
        let profile = ProfileActionStateModel(profileID: UUID())
        context.insert(profile)
        let action = BabyActionModel(profile: profile)
        context.insert(action)
        try context.save()

        do {
            let share = try context.share(profile, to: [])
            XCTAssertNotNil(share.recordID.recordName)
            XCTAssertEqual(profile.actions.count, 1)
        } catch {
            throw XCTSkip("CloudKit sharing unavailable in tests: \(error)")
        }
    }
}
