import CloudKit
import Foundation
import SwiftData
import SwiftUI

@MainActor
/// Exposes a synthesized view of the CloudKit mirroring state so the UI can
/// block on the initial import and surface sync diagnostics.
final class SyncStatusViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case importing(progress: Double?)
        case exporting(progress: Double?)
        case waiting
        case failed(String)
        case finished(Date)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var observedModelNames: Set<String> = []
    @Published private(set) var lastError: String?

    var isInitialImportComplete: Bool {
        switch state {
        case .finished, .failed:
            return true
        default:
            return false
        }
    }

    private let monitor: CloudKitSyncMonitor
    private let requiredModelNames: Set<String>
    private var eventsTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let timeoutInterval: TimeInterval

    init(modelContainer: ModelContainer,
         requiredModels: [any PersistentModel.Type] = [ProfileActionStateModel.self, BabyActionModel.self],
         timeoutInterval: TimeInterval = 30) {
        self.monitor = CloudKitSyncMonitor(modelContext: modelContainer.mainContext)
        self.requiredModelNames = Set(requiredModels.map { String(describing: $0) })
        self.timeoutInterval = timeoutInterval
        observeMonitor()
        armTimeout()
    }

    deinit {
        eventsTask?.cancel()
        timeoutTask?.cancel()
    }

    func resetInitialImportTimeout() {
        armTimeout()
    }

    private func observeMonitor() {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in monitor.events {
                await self.handle(event: event)
            }
        }
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(timeoutInterval))
            guard Task.isCancelled == false else { return }
            if self.isInitialImportComplete == false {
                self.state = .failed("Timed out waiting for initial CloudKit import.")
            }
        }
    }

    private func handle(event: Any) async {
        let summary = SyncMonitorEventSummary(event: event)

        lastError = nil

        if let errorDescription = summary.errorDescription {
            lastError = errorDescription
            state = .failed(errorDescription)
            return
        }

        if summary.isImporting {
            if summary.modelNames.isEmpty == false {
                var names = observedModelNames
                names.formUnion(summary.modelNames)
                observedModelNames = names
            }
            state = .importing(progress: summary.progress)
            return
        }

        if summary.isExporting {
            state = .exporting(progress: summary.progress)
            return
        }

        if summary.isWaiting {
            state = .waiting
            return
        }

        if summary.isIdle {
            if requiredModelNames.isSubset(of: observedModelNames) {
                state = .finished(Date())
                timeoutTask?.cancel()
            } else {
                state = .idle
            }
        }
    }
}
