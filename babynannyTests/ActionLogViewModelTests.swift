import Foundation
import SwiftData
import Testing
@testable import babynanny

@Suite("Action Log View Model")
struct ActionLogViewModelTests {
    @Test
    func reloadsCachedStateAfterBackgroundContextSave() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let profileID = UUID()

        let profileModel = ProfileActionStateModel(profileID: profileID)
        stack.mainContext.insert(profileModel)
        try stack.mainContext.save()

        let actionStore = await ActionLogStore(modelContext: stack.mainContext,
                                               dataStack: stack)

        let initialState = await actionStore.state(for: profileID)
        #expect(initialState.history.isEmpty)

        let backgroundContext = stack.backgroundContext()
        let descriptor = FetchDescriptor<ProfileActionStateModel>()
        let backgroundModels = try backgroundContext.fetch(descriptor)
        let backgroundProfileModel = try #require(backgroundModels.first(where: { $0.resolvedProfileID == profileID }))

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(120)
        let actionModel = BabyActionModel(id: UUID(),
                                          category: .sleep,
                                          startDate: startDate,
                                          endDate: endDate,
                                          profile: backgroundProfileModel)
        backgroundContext.insert(actionModel)
        try backgroundContext.save()

        try await Task.sleep(nanoseconds: 200_000_000)

        let reloadedState = await actionStore.state(for: profileID)
        #expect(reloadedState.history.contains(where: { $0.id == actionModel.id }))
        #expect(reloadedState.history.count == 1)
    }

    @Test
    func reloadsCachedStateAfterSharedContextMutation() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = await AppDataStack(modelContainer: container)
        let profileID = UUID()
        let actionID = UUID()

        let profileModel = ProfileActionStateModel(profileID: profileID)
        stack.mainContext.insert(profileModel)

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(120)
        let initialAction = BabyActionModel(id: actionID,
                                            category: .diaper,
                                            startDate: startDate,
                                            endDate: endDate,
                                            diaperType: .both,
                                            updatedAt: startDate,
                                            profile: profileModel)
        stack.mainContext.insert(initialAction)
        try stack.mainContext.save()

        let actionStore = await ActionLogStore(modelContext: stack.mainContext,
                                               dataStack: stack)

        let initialState = await actionStore.state(for: profileID)
        let initialSnapshot = try #require(initialState.history.first(where: { $0.id == actionID }))
        #expect(initialSnapshot.diaperType == .both)

        let descriptor = FetchDescriptor<BabyActionModel>()
        let mainContextActions = try stack.mainContext.fetch(descriptor)
        let persistedAction = try #require(mainContextActions.first(where: { $0.id == actionID }))
        persistedAction.diaperType = .pee
        persistedAction.updatedAt = Date().addingTimeInterval(300)
        try stack.mainContext.save()

        try await Task.sleep(nanoseconds: 200_000_000)

        let refreshedState = await actionStore.state(for: profileID)
        let refreshedAction = try #require(refreshedState.history.first(where: { $0.id == actionID }))
        #expect(refreshedAction.diaperType == .pee)
    }
}
