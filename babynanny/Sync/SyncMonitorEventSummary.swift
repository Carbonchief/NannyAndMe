import Foundation

/// Lightweight reflection-based helper that extracts high-level sync state details
/// from `CloudKitSyncMonitor` events. The type is `internal` so it can be exercised
/// by unit tests without duplicating the brittle parsing logic.
struct SyncMonitorEventSummary {
    let isIdle: Bool
    let isImporting: Bool
    let isExporting: Bool
    let isWaiting: Bool
    let progress: Double?
    let modelNames: [String]
    let errorDescription: String?

    init(event: Any) {
        var idle = false
        var importing = false
        var exporting = false
        var waiting = false
        var capturedProgress: Double?
        var capturedModels: [String] = []
        var capturedError: String?
        let eventDescription = String(describing: event)

        let mirror = Mirror(reflecting: event)
        for child in mirror.children {
            guard let label = child.label else { continue }
            switch label {
            case "phase":
                let description = String(describing: child.value).lowercased()
                if description.contains("import") {
                    importing = true
                    capturedProgress = Self.extractProgress(from: description)
                } else if description.contains("export") {
                    exporting = true
                    capturedProgress = Self.extractProgress(from: description)
                } else if description.contains("wait") {
                    waiting = true
                } else if description.contains("idle") {
                    idle = true
                }
            case "error":
                if let error = child.value as? Error {
                    capturedError = error.localizedDescription
                }
            case "work":
                capturedModels.append(contentsOf: Self.models(from: child.value))
            default:
                continue
            }
        }

        if capturedModels.isEmpty {
            capturedModels = Self.modelNames(in: eventDescription)
        }

        isIdle = idle
        isImporting = importing
        isExporting = exporting
        isWaiting = waiting
        progress = capturedProgress
        modelNames = Self.deduplicatedModelNames(from: capturedModels)
        errorDescription = capturedError
    }
}

private extension SyncMonitorEventSummary {
    static func extractProgress(from description: String) -> Double? {
        guard let range = description.range(of: "fractioncompleted:") else { return nil }
        let substring = description[range.upperBound...]
        let components = substring.split(separator: ")", maxSplits: 1, omittingEmptySubsequences: true)
        guard let rawValue = components.first else { return nil }
        return Double(rawValue.trimmingCharacters(in: .whitespaces))
    }

    static func models(from work: Any) -> [String] {
        let mirror = Mirror(reflecting: work)
        for child in mirror.children where child.label == "models" {
            let modelsMirror = Mirror(reflecting: child.value)
            return modelsMirror.children.compactMap { element -> String? in
                let description = String(describing: element.value)
                if let nameRange = description.range(of: "modelname:") {
                    let suffix = description[nameRange.upperBound...]
                    let cleaned = suffix.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first
                    return cleaned.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                return description
            }
        }
        return []
    }

    static func modelNames(in description: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "modelName\\s*[:=]\\s*\"?([A-Za-z0-9_]+)\"?",
                                                   options: .caseInsensitive) else {
            return []
        }
        let range = NSRange(description.startIndex..<description.endIndex, in: description)
        let matches = regex.matches(in: description, options: [], range: range)
        return matches.compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: description) else { return nil }
            return String(description[nameRange])
        }
    }

    static func deduplicatedModelNames(from names: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for name in names where seen.contains(name) == false {
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }
}
