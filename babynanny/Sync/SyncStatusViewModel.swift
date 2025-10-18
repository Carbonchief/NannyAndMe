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
    private var normalizedObservedModelNames: Set<String> = []

    init(modelContainer: ModelContainer,
         requiredModels: [any PersistentModel.Type] = [ProfileActionStateModel.self, BabyActionModel.self],
         eventStream: AsyncStream<Any>? = nil) {
        let requiredNames = Set(requiredModels.map { Self.normalize(modelName: String(describing: $0)) })
        self.requiredModelNames = requiredNames
        self.events = eventStream ?? CloudKitSyncMonitorCompat.events(
            modelContainer: modelContainer,
            requiredModelNames: Set(requiredModels.map { String(describing: $0) })
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
            var normalizedNames = normalizedObservedModelNames
            names.formUnion(summary.modelNames)
            for name in summary.modelNames {
                normalizedNames.insert(Self.normalize(modelName: name))
            }
            observedModelNames = names
            normalizedObservedModelNames = normalizedNames
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
            if requiredModelNames.isSubset(of: normalizedObservedModelNames) {
                state = .finished(Date())
            } else {
                state = .idle
            }
        }
    }
}

private extension SyncStatusViewModel {
    static func normalize(modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.removingKnownPrefixes(["CD_", "SD_"])

        if let alias = modelNameAliases[withoutPrefix] {
            return alias
        }

        return withoutPrefix
    }

    static let modelNameAliases: [String: String] = [
        "ProfileActionStateModel": "Profile",
        "ProfileState": "Profile",
        "ProfileActionState": "Profile",
        "BabyActionModel": "BabyAction"
    ]
}

private extension String {
    func removingKnownPrefixes(_ prefixes: [String]) -> String {
        for prefix in prefixes where hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
