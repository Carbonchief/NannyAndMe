#if DEBUG
import CloudKit
import SwiftUI

struct SyncDiagnosticsView: View {
    @ObservedObject var coordinator: SyncCoordinator
    @ObservedObject var statusViewModel: SyncStatusViewModel
    let containerIdentifier: String

    @State private var accountStatusDescription = "—"
    @State private var countsOutput: String?
    @State private var isDumpingCounts = false
    @State private var forceSyncInFlight = false

    private var diagnostics: SyncCoordinator.Diagnostics { coordinator.diagnostics }

    var body: some View {
        List {
            accountSection
            statusSection
            coordinatorSection
            if let countsOutput { countsSection(countsOutput) }
            actionsSection
        }
        .navigationTitle("Sync Diagnostics")
        .task { await loadAccountStatus() }
    }
}

private extension SyncDiagnosticsView {
    var accountSection: some View {
        Section(header: Text("Account")) {
            HStack {
                Text("Status")
                Spacer()
                Text(accountStatusDescription)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var statusSection: some View {
        Section(header: Text("CloudKit Mirroring")) {
            HStack {
                Text("State")
                Spacer()
                Text(statusDescription)
                    .foregroundStyle(statusColor)
            }
            if let error = statusViewModel.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
            if case .finished(let date) = statusViewModel.state {
                HStack {
                    Text("Last Import")
                    Spacer()
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Text("Models")
                Spacer()
                Text(modelsDescription)
                    .font(.footnote)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var coordinatorSection: some View {
        Section(header: Text("Coordinator")) {
            HStack {
                Text("Subscription")
                Spacer()
                Text(subscriptionDescription)
                    .foregroundStyle(subscriptionColor)
            }
            diagnosticsRow(title: "Last Push", value: formatted(date: diagnostics.lastPushReceivedAt))
            diagnosticsRow(title: "Last Sync", value: formatted(date: diagnostics.lastSyncFinishedAt))
            diagnosticsRow(title: "Pending Changes", value: pendingChangeDescription)
            if let error = diagnostics.lastSyncError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }
        }
    }

    func countsSection(_ counts: String) -> some View {
        Section(header: Text("Entity Counts")) {
            Text(counts)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    var actionsSection: some View {
        Section {
            Button {
                forceSync()
            } label: {
                Label("Force mirror refresh", systemImage: "arrow.clockwise")
            }
            .disabled(forceSyncInFlight)
            .postHogLabel("debug.sync.forceRefresh")

            Button {
                dumpCounts()
            } label: {
                if isDumpingCounts {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Dumping counts…")
                    }
                } else {
                    Label("Dump counts per scope", systemImage: "list.number")
                }
            }
            .disabled(isDumpingCounts)
            .postHogLabel("debug.sync.dumpCounts")
        }
    }

    func diagnosticsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    var subscriptionDescription: String {
        switch diagnostics.subscriptionState {
        case .unknown:
            return "Unknown"
        case .pending:
            return "Pending"
        case .active:
            return "Active"
        case .failed(let message):
            return "Failed — \(message)"
        }
    }

    var subscriptionColor: Color {
        switch diagnostics.subscriptionState {
        case .active:
            return .green
        case .failed:
            return .red
        case .pending:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    var pendingChangeDescription: String {
        diagnostics.pendingChangeCount == 0 ? "None" : "\(diagnostics.pendingChangeCount)"
    }

    var statusDescription: String {
        switch statusViewModel.state {
        case .idle:
            return "Idle"
        case .waiting:
            return "Waiting"
        case .importing(let progress):
            if let progress {
                return "Importing (\(Int(progress * 100))%)"
            }
            return "Importing"
        case .exporting(let progress):
            if let progress {
                return "Exporting (\(Int(progress * 100))%)"
            }
            return "Exporting"
        case .failed:
            return "Failed"
        case .finished:
            return "Finished"
        }
    }

    var statusColor: Color {
        switch statusViewModel.state {
        case .failed:
            return .red
        case .finished:
            return .green
        case .importing, .exporting:
            return .orange
        case .waiting:
            return .yellow
        case .idle:
            return .secondary
        }
    }

    var modelsDescription: String {
        let names = statusViewModel.observedModelNames.sorted()
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    func formatted(date: Date?) -> String {
        guard let date else { return "—" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    func forceSync() {
        guard forceSyncInFlight == false else { return }
        forceSyncInFlight = true
        statusViewModel.resetInitialImportTimeout()
        coordinator.requestSyncIfNeeded(reason: .userInitiated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            forceSyncInFlight = false
        }
    }

    func dumpCounts() {
        guard isDumpingCounts == false else { return }
        isDumpingCounts = true
        countsOutput = nil
        Task {
            defer { isDumpingCounts = false }
            do {
                let container = CKContainer(identifier: containerIdentifier)
                let privateCounts = try await counts(for: container.privateCloudDatabase)
                let sharedCounts = try await counts(for: container.sharedCloudDatabase)
                let formatted = [
                    "Private:\n" + format(counts: privateCounts),
                    "Shared:\n" + format(counts: sharedCounts)
                ].joined(separator: "\n\n")
                await MainActor.run {
                    countsOutput = formatted
                }
            } catch {
                await MainActor.run {
                    countsOutput = "Failed to fetch counts: \(error.localizedDescription)"
                }
            }
        }
    }

    func counts(for database: CKDatabase) async throws -> [String: Int] {
        var results: [String: Int] = [:]
        try await withThrowingTaskGroup(of: (String, Int).self) { group in
            for recordType in ["Profile", "BabyAction"] {
                group.addTask {
                    let count = try await countRecords(of: recordType, in: database)
                    return (recordType, count)
                }
            }
            for try await (type, count) in group {
                results[type] = count
            }
        }
        return results
    }

    func format(counts: [String: Int]) -> String {
        counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    func countRecords(of recordType: String, in database: CKDatabase) async throws -> Int {
        var total = 0
        var cursor: CKQueryOperation.Cursor?
        repeat {
            if let currentCursor = cursor {
                let (matchResults, newCursor) = try await database.records(continuingMatchFrom: currentCursor)
                let successes = matchResults.reduce(into: 0) { partialResult, element in
                    let (_, result) = element
                    if case .success = result { partialResult += 1 }
                }
                total += successes
                cursor = newCursor
            } else {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (matchResults, newCursor) = try await database.records(matching: query)
                let successes = matchResults.reduce(into: 0) { partialResult, element in
                    let (_, result) = element
                    if case .success = result { partialResult += 1 }
                }
                total += successes
                cursor = newCursor
            }
        } while cursor != nil
        return total
    }

    func loadAccountStatus() async {
        do {
            let container = CKContainer(identifier: containerIdentifier)
            let status = try await container.accountStatus()
            await MainActor.run {
                accountStatusDescription = status.localizedDescription
            }
        } catch {
            await MainActor.run {
                accountStatusDescription = "Error: \(error.localizedDescription)"
            }
        }
    }
}

private extension CKAccountStatus {
    var localizedDescription: String {
        switch self {
        case .available:
            return "Available"
        case .restricted:
            return "Restricted"
        case .noAccount:
            return "No account"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}

private extension SyncDiagnosticsView {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

#Preview("Sync Diagnostics") {
    NavigationStack {
        let previewStack = AppDataStack.preview()
        SyncDiagnosticsView(
            coordinator: previewStack.syncCoordinator,
            statusViewModel: previewStack.syncStatusViewModel,
            containerIdentifier: "iCloud.com.prioritybit.babynanny"
        )
    }
}
#endif
