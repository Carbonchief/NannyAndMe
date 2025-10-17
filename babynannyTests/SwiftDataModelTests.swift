import XCTest
import SwiftData
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
}
