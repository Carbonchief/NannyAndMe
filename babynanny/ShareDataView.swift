import CloudKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareDataView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator

    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @State private var exportShareItem: JSONExportItem?
    @State private var isPreparingExport = false
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?

    private var activeShareState: ShareDataCoordinator.ShareState? {
        guard let state = shareDataCoordinator.shareState,
              state.profileID == profileStore.activeProfile.id else {
            return nil
        }
        return state
    }

    var body: some View {
        Form {
            Section(header: Text(L10n.ShareData.profileSectionTitle)) {
                let profile = profileStore.activeProfile
                let historyCount = actionStore.state(for: profile.id).history.count

                HStack(spacing: 16) {
                    ProfileAvatarView(imageData: profile.imageData, size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.ShareData.profileName(profile.displayName))

                        Text(L10n.ShareData.logCount(historyCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ShareDataActionButton(
                    title: activeShareButtonTitle,
                    systemImage: "person.2.circle.fill",
                    tint: .indigo,
                    action: presentShareInterface,
                    analyticsLabel: activeShareState == nil
                        ? "shareData_startShare_button"
                        : "shareData_manageShare_button"
                )
                .disabled(shareDataCoordinator.isPerformingShareMutation)

                if let shareState = activeShareState {
                    statusView(for: shareState)

                    if shareState.isCurrentUserOwner {
                        ShareDataActionButton(
                            title: L10n.ShareData.stopSharingButton,
                            systemImage: "person.fill.xmark",
                            tint: .red,
                            action: stopSharing,
                            isLoading: shareDataCoordinator.isPerformingShareMutation,
                            analyticsLabel: "shareData_stopSharing_button"
                        )
                        .disabled(shareDataCoordinator.isPerformingShareMutation)
                    } else {
                        ShareDataActionButton(
                            title: L10n.ShareData.leaveShareButton,
                            systemImage: "rectangle.portrait.and.arrow.right",
                            tint: .orange,
                            action: leaveShare,
                            isLoading: shareDataCoordinator.isPerformingShareMutation,
                            analyticsLabel: "shareData_leaveShare_button"
                        )
                        .disabled(shareDataCoordinator.isPerformingShareMutation)
                    }
                } else {
                    Text(L10n.ShareData.collaborationDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.ShareData.collaborationSectionTitle)
            }

            if let shareState = activeShareState {
                Section(header: Text(L10n.ShareData.participantsSectionTitle)) {
                    ForEach(shareState.participants) { participant in
                        participantRow(for: participant)
                    }
                }
            }

            Section {
                ShareDataActionButton(
                    title: L10n.ShareData.exportButton,
                    systemImage: "arrow.up.doc",
                    tint: .gray,
                    action: startJSONExport,
                    isLoading: isPreparingExport,
                    analyticsLabel: "shareData_troubleshooting_export_button"
                )
                .disabled(isPreparingExport)

                ShareDataActionButton(
                    title: L10n.ShareData.importButton,
                    systemImage: "square.and.arrow.down",
                    tint: .mint,
                    action: { isImporting = true },
                    analyticsLabel: "shareData_troubleshooting_import_button"
                )
            } header: {
                Text(L10n.ShareData.troubleshootingSectionTitle)
            } footer: {
                importFooter
            }
        }
        .shareDataFormStyling()
        .navigationTitle(L10n.ShareData.title)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.Common.done))
            )
        }
        .sheet(item: $exportShareItem) { item in
            JSONExportSheet(item: item) { outcome in
                let exportItem = item
                exportShareItem = nil
                exportItem.cleanup()

                withAnimation {
                    isPreparingExport = false
                }

                if case let .failed(error) = outcome {
                    alert = ShareDataAlert(
                        title: L10n.ShareData.Alert.exportFailureTitle,
                        message: L10n.ShareData.Alert.exportFailureMessage(error.localizedDescription)
                    )
                }
            }
            .onAppear {
                withAnimation {
                    isPreparingExport = false
                }
            }
        }
        .sheet(item: $shareDataCoordinator.activeSharePresentation) { presentation in
            CloudShareController(
                presentation: presentation,
                onSave: { share in
                    shareDataCoordinator.handleShareSaved(share, profileID: presentation.profileID)
                    shareDataCoordinator.refreshActiveShareState()
                },
                onStop: {
                    shareDataCoordinator.handleShareStopped(for: presentation.profileID)
                },
                onFailure: { error in
                    shareDataCoordinator.handleShareFailure(error)
                    alert = ShareDataAlert(
                        title: L10n.ShareData.Alert.shareFailureTitle,
                        message: error.localizedDescription
                    )
                }
            )
        }
        .onAppear {
            shareDataCoordinator.loadShareState(for: profileStore.activeProfile.id)
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: profileStore.activeProfile) { _, profile in
            shareDataCoordinator.loadShareState(for: profile.id)
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onDisappear {
            shareDataCoordinator.dismissShareData()
        }
    }

    private var activeShareButtonTitle: String {
        if activeShareState == nil {
            return L10n.ShareData.startSharingButton
        }
        return L10n.ShareData.manageShareButton
    }

    @ViewBuilder
    private func statusView(for shareState: ShareDataCoordinator.ShareState) -> some View {
        let statusDescription = shareStatusDescription(for: shareState.status)
        HStack {
            Label(statusDescription, systemImage: "checkmark.seal")
                .font(.subheadline)
            Spacer()
            if shareDataCoordinator.isPerformingShareMutation {
                ProgressView()
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func participantRow(for participant: ShareDataCoordinator.ShareParticipant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(participant.name)
                    .font(.headline)

                if participant.isCurrentUser {
                    TagView(text: L10n.ShareData.youTag, tint: .accentColor)
                } else if participant.role == .owner {
                    TagView(text: L10n.ShareData.ownerTag, tint: .purple)
                }
            }

            if let detail = participant.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(participantStatusDescription(for: participant))
                .font(.caption)
                .foregroundStyle(participantStatusColor(for: participant))
        }
        .padding(.vertical, 4)
    }

    private func shareStatusDescription(for status: ShareDataCoordinator.ShareStatus) -> String {
        switch status {
        case .pending:
            return L10n.ShareData.Status.pending
        case .accepted:
            return L10n.ShareData.Status.accepted
        case .stopped:
            return L10n.ShareData.Status.stopped
        }
    }

    private func participantStatusDescription(for participant: ShareDataCoordinator.ShareParticipant) -> String {
        switch participant.acceptanceStatus {
        case .pending, .unknown:
            return L10n.ShareData.ParticipantStatus.pending
        case .accepted:
            return L10n.ShareData.ParticipantStatus.accepted
        case .removed, .revoked, .declined:
            return L10n.ShareData.ParticipantStatus.revoked
        @unknown default:
            return L10n.ShareData.ParticipantStatus.pending
        }
    }

    private func participantStatusColor(for participant: ShareDataCoordinator.ShareParticipant) -> Color {
        switch participant.acceptanceStatus {
        case .pending, .unknown:
            return .orange
        case .accepted:
            return .green
        case .removed, .revoked, .declined:
            return .red
        @unknown default:
            return .secondary
        }
    }

    private func presentShareInterface() {
        do {
            try shareDataCoordinator.presentShareInterface(for: profileStore.activeProfile.id)
        } catch {
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.shareFailureTitle,
                message: error.localizedDescription
            )
        }
    }

    private func stopSharing() {
        Task {
            do {
                try await shareDataCoordinator.stopSharingActiveShare()
            } catch {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.stopShareFailureTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func leaveShare() {
        Task {
            do {
                try await shareDataCoordinator.leaveActiveShare()
            } catch {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.leaveShareFailureTitle,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func startJSONExport() {
        guard isPreparingExport == false else { return }

        withAnimation {
            isPreparingExport = true
        }

        do {
            exportShareItem?.cleanup()
            exportShareItem = nil

            let data = try makeExportData()
            let filename = "\(defaultExportFilename).json"
            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL, options: .atomic)
            exportShareItem = JSONExportItem(url: destinationURL)
        } catch {
            withAnimation {
                isPreparingExport = false
            }
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.exportFailureTitle,
                message: L10n.ShareData.Alert.exportFailureMessage(error.localizedDescription)
            )
        }
    }

    private var defaultExportFilename: String {
        let name = profileStore.activeProfile.displayName
        let sanitized = sanitizeFilename(name)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "\(sanitized)-backup-\(dateString)"
    }

    @ViewBuilder
    private var importFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.troubleshootingFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let summary = lastImportSummary {
                Text(L10n.ShareData.importSummary(summary.added, summary.updated))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if didUpdateProfile {
                    Text(L10n.ShareData.profileUpdatedNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func makeExportData() throws -> Data {
        let profile = profileStore.activeProfile
        let state = actionStore.state(for: profile.id)
        let payload = SharedProfileData(profile: profile, actions: state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.importFailureTitle,
                    message: L10n.ShareData.Error.readFailed
                )
                return
            }
            importData(from: url)
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.importFailureTitle,
                message: L10n.ShareData.Error.readFailed
            )
        }
    }

    private func importData(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(SharedProfileData.self, from: data)

            let profileUpdated = try profileStore.mergeActiveProfile(with: payload.profile)
            let summary = actionStore.mergeProfileState(payload.actions, for: payload.profile.id)

            lastImportSummary = summary
            didUpdateProfile = profileUpdated

            var messages = [L10n.ShareData.importSummary(summary.added, summary.updated)]
            if profileUpdated {
                messages.append(L10n.ShareData.profileUpdatedNote)
            }

            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.importSuccessTitle,
                message: messages.joined(separator: "\n")
            )
        } catch let error as ProfileStore.ShareDataError {
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.importFailureTitle,
                message: error.localizedDescription
            )
        } catch {
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.importFailureTitle,
                message: L10n.ShareData.Error.readFailed
            )
        }
    }

    private func processPendingExternalImportIfNeeded() {
        guard let request = shareDataCoordinator.externalImportRequest else { return }
        guard processedExternalImportID != request.id else { return }
        processedExternalImportID = request.id
        importData(from: request.url)
        shareDataCoordinator.clearExternalImportRequest(request)
    }

    private func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = name.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let sanitized = String(sanitizedScalars)
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let base = trimmed.isEmpty ? "Profile" : trimmed
        return base
    }
}

private struct JSONExportItem: Identifiable {
    let id = UUID()
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum JSONExportOutcome {
    case completed
    case cancelled
    case failed(Error)
}

private struct JSONExportSheet: UIViewControllerRepresentable {
    let item: JSONExportItem
    let completion: (JSONExportOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            DispatchQueue.main.async {
                if let error {
                    context.coordinator.completion(.failed(error))
                } else if completed {
                    context.coordinator.completion(.completed)
                } else {
                    context.coordinator.completion(.cancelled)
                }
            }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
                .first
            if let sourceView = popover.sourceView {
                popover.sourceRect = CGRect(
                    x: sourceView.bounds.midX,
                    y: sourceView.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        let completion: (JSONExportOutcome) -> Void

        init(completion: @escaping (JSONExportOutcome) -> Void) {
            self.completion = completion
        }
    }
}

private struct ShareDataActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    var isLoading: Bool = false
    let analyticsLabel: String

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .animation(.default, value: isLoading)
        .postHogLabel(analyticsLabel)
    }
}

private struct TagView: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct ShareDataAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SharedProfileData: Codable {
    var version: Int
    var exportedAt: Date
    var profile: ChildProfile
    var actions: ProfileActionState

    init(profile: ChildProfile, actions: ProfileActionState, version: Int = 1, exportedAt: Date = Date()) {
        self.version = version
        self.exportedAt = exportedAt
        self.profile = profile
        self.actions = actions
    }
}

private struct CloudShareController: UIViewControllerRepresentable {
    let presentation: ShareDataCoordinator.SharePresentation
    let onSave: (CKShare) -> Void
    let onStop: () -> Void
    let onFailure: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: presentation.share, container: presentation.container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: CloudShareController

        init(parent: CloudShareController) {
            self.parent = parent
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.presentation.title
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    didSave share: CKShare,
                                    for container: CKContainer) {
            Task { @MainActor in
                parent.onSave(share)
            }
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            Task { @MainActor in
                parent.onFailure(error)
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in
                parent.onStop()
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func shareDataFormStyling() -> some View {
        if #available(iOS 16.0, *) {
            self
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
        } else {
            self
                .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(category: .feeding,
                           startDate: Date().addingTimeInterval(-7200),
                           endDate: Date().addingTimeInterval(-6900))
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return NavigationStack {
        ShareDataView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator(modelContext: AppDataStack.preview().mainContext))
    }
}
