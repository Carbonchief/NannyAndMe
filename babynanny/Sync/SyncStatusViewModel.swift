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

    private let requiredModelNames: Set<String>
    private var eventsTask: Task<Void, Never>?
    private let events: AsyncStream<Any>

    init(modelContainer: ModelContainer,
         requiredModels: [any PersistentModel.Type] = [ProfileActionStateModel.self, BabyActionModel.self],
         eventStream: AsyncStream<Any>? = nil) {
        let names = Set(requiredModels.map { String(describing: $0) })
        self.requiredModelNames = names
        self.events = eventStream ?? CloudKitSyncMonitorCompat.events(
            modelContainer: modelContainer,
            requiredModelNames: names
        )
        observeMonitor()
    }

    deinit {
        eventsTask?.cancel()
    }

    private func observeMonitor() {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            for await event in events {
                await self.handle(event: event)
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

        if summary.modelNames.isEmpty == false {
            var names = observedModelNames
            names.formUnion(summary.modelNames)
            observedModelNames = names
        }

        if summary.isImporting {
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
            } else {
                state = .idle
            }
        }
    }
}
