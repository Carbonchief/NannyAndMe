import SwiftData
import XCTest
@testable import babynanny

final class SyncStatusViewModelTests: XCTestCase {
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

    func testViewModelFinishesWhenOnlyProfileRecordsReported() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: [ProfileActionStateModel.self, BabyActionModel.self],
            configurations: configuration
        )

        let events = AsyncStream<Any> { continuation in
            continuation.yield(
                MockEvent(
                    phase: .init(description: "CloudKitSyncMonitor.Phase.import(fractionCompleted: 1.0)"),
                    error: nil,
                    work: .init(models: [
                        .init(description: "Model(modelName: CD_ProfileActionStateModel)")
                    ])
                )
            )
            continuation.yield(
                MockEvent(
                    phase: .init(description: "CloudKitSyncMonitor.Phase.idle"),
                    error: nil,
                    work: .init(models: [])
                )
            )
            continuation.finish()
        }

        let viewModel = await MainActor.run {
            SyncStatusViewModel(modelContainer: container, eventStream: events)
        }

        try await Task.sleep(for: .milliseconds(50))

        let state = await MainActor.run { viewModel.state }
        guard case .finished = state else {
            XCTFail("Expected finished state, got \(state)")
            return
        }

        let observedNames = await MainActor.run { viewModel.observedModelNames }
        XCTAssertEqual(observedNames, Set(["ProfileActionStateModel"]))
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
}
