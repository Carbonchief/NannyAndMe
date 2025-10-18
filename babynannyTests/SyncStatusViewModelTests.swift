import XCTest
@testable import babynanny

final class SyncStatusViewModelTests: XCTestCase {
    func testIdleEventCompletesInitialImport() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let event = MockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.idle"),
            error: nil,
            work: .init(models: [
                .init(description: "Model(modelName: Profile)"),
                .init(description: "Model(modelName: BabyAction)")
            ])
        )
        let stream = AsyncStream<Any> { continuation in
            continuation.yield(event)
            continuation.finish()
        }

        let viewModel = await MainActor.run {
            SyncStatusViewModel(modelContainer: container,
                                 eventStream: stream)
        }

        try? await Task.sleep(for: .milliseconds(50))

        let isComplete = await MainActor.run { viewModel.isInitialImportComplete }
        XCTAssertTrue(isComplete)

        let state = await MainActor.run { viewModel.state }
        if case .finished = state {
            // expected path
        } else {
            XCTFail("Expected finished state, got \(state)")
        }
    }

    func testImportEventParsingExtractsProgressAndModels() {
        let event = MockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.import(fractionCompleted: 0.5)"),
            error: nil,
            work: .init(models: [.init(description: "Model(modelName: Profile)")])
        )

        let summary = SyncMonitorEventSummary(event: event)

        XCTAssertTrue(summary.isImporting)
        XCTAssertFalse(summary.isExporting)
        XCTAssertEqual(summary.progress, 0.5)
        XCTAssertEqual(summary.modelNames, ["Profile"])
    }

    func testExportEventParsingDetectsExportPhase() {
        let event = MockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.export(fractionCompleted: 0.75)"),
            error: nil,
            work: .init(models: [])
        )

        let summary = SyncMonitorEventSummary(event: event)

        XCTAssertTrue(summary.isExporting)
        XCTAssertEqual(summary.progress, 0.75)
        XCTAssertFalse(summary.isImporting)
    }

    func testErrorPropagation() {
        let event = MockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.idle"),
            error: MockError.failed,
            work: .init(models: [])
        )

        let summary = SyncMonitorEventSummary(event: event)

        XCTAssertEqual(summary.errorDescription, MockError.failed.localizedDescription)
        XCTAssertTrue(summary.isIdle)
    }

    func testWaitingPhaseIsDetected() {
        let event = MockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.waiting"),
            error: nil,
            work: .init(models: [])
        )

        let summary = SyncMonitorEventSummary(event: event)

        XCTAssertTrue(summary.isWaiting)
        XCTAssertNil(summary.progress)
    }

    func testModelParsingFallsBackToEventDescription() {
        let event = AlternateMockEvent(
            phase: .init(description: "CloudKitSyncMonitor.Phase.idle"),
            error: nil,
            work: .init(payload: "Model(modelName: \"Profile\"), Model(modelName: \"BabyAction\")")
        )

        let summary = SyncMonitorEventSummary(event: event)

        XCTAssertTrue(summary.isIdle)
        XCTAssertEqual(Set(summary.modelNames), Set(["Profile", "BabyAction"]))
    }

    func testTimeoutCompletesInitialImport() async throws {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stream = AsyncStream<Any> { continuation in
            continuation.finish()
        }

        let viewModel = await MainActor.run {
            SyncStatusViewModel(modelContainer: container,
                                 timeoutInterval: 0.05,
                                 eventStream: stream)
        }

        try? await Task.sleep(for: .milliseconds(100))

        let state = await MainActor.run { viewModel.state }
        guard case .finished = state else {
            XCTFail("Expected finished state after timeout, got \(state)")
            return
        }

        let names = await MainActor.run { viewModel.observedModelNames }
        XCTAssertEqual(names, Set([String(describing: ProfileActionStateModel.self), String(describing: BabyActionModel.self)]))

        let error = await MainActor.run { viewModel.lastError }
        XCTAssertEqual(error, "Timed out waiting for initial CloudKit import.")
    }
}

private extension SyncStatusViewModelTests {
    enum MockError: Error {
        case failed
    }

    struct MockPhase: CustomStringConvertible {
        var description: String
    }

    struct MockModel: CustomStringConvertible {
        var description: String
    }

    struct MockWork {
        var models: [MockModel]
    }

    struct MockEvent {
        var phase: MockPhase
        var error: Error?
        var work: MockWork
    }

    struct AlternateMockWork {
        var payload: String
    }

    struct AlternateMockEvent {
        var phase: MockPhase
        var error: Error?
        var work: AlternateMockWork
    }
}
