#if DEBUG
import SwiftUI

struct SyncDiagnosticsView: View {
    @ObservedObject var coordinator: SyncCoordinator

    private var diagnostics: SyncCoordinator.Diagnostics { coordinator.diagnostics }

    var body: some View {
        List {
            Section(header: Text("Subscription")) {
                HStack {
                    Text("State")
                    Spacer()
                    Text(subscriptionDescription)
                        .foregroundStyle(subscriptionColor)
                }
            }

            Section(header: Text("Activity")) {
                diagnosticsRow(title: "Last Push", value: formatted(date: diagnostics.lastPushReceivedAt))
                diagnosticsRow(title: "Last Sync", value: formatted(date: diagnostics.lastSyncFinishedAt))
                diagnosticsRow(title: "Pending Changes", value: pendingChangeDescription)
            }

            if let error = diagnostics.lastSyncError {
                Section(header: Text("Last Error")) {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color.red)
                }
            }
        }
        .navigationTitle("Sync Diagnostics")
    }

    private var subscriptionDescription: String {
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

    private var subscriptionColor: Color {
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

    private var pendingChangeDescription: String {
        diagnostics.pendingChangeCount == 0 ? "None" : "\(diagnostics.pendingChangeCount)"
    }

    private func diagnosticsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func formatted(date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Sync Diagnostics") {
    NavigationStack {
        SyncDiagnosticsView(coordinator: AppDataStack.preview().syncCoordinator)
    }
}
#endif
