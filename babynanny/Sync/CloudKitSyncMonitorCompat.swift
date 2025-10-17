import Foundation
import SwiftData

/// Provides a fallback event stream for builds where `CloudKitSyncMonitor` is not
/// available from SwiftData's SPI. The stream emits a synthesized idle event so
/// the rest of the sync pipeline can proceed without compile-time access to the
/// private monitor type.
enum CloudKitSyncMonitorCompat {
    private struct Phase: CustomStringConvertible {
        enum Kind {
            case idle
        }

        let kind: Kind

        var description: String {
            switch kind {
            case .idle:
                return "CloudKitSyncMonitor.Phase.idle"
            }
        }
    }

    private struct Model: CustomStringConvertible {
        let name: String

        var description: String {
            "Model(modelName: \(name))"
        }
    }

    private struct Work {
        let models: [Model]
    }

    private struct Event {
        let phase: Phase
        let error: Error?
        let work: Work
    }

    static func events(modelContainer _: ModelContainer,
                       requiredModelNames: Set<String>) -> AsyncStream<Any> {
        AsyncStream { continuation in
            let models = requiredModelNames.map { Model(name: $0) }
            let event = Event(phase: .init(kind: .idle), error: nil, work: .init(models: models))
            continuation.yield(event)
            continuation.finish()
        }
    }
}
