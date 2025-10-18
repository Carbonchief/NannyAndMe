import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareDataView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var viewModel = ShareDataViewModel(manager: MPCManager())

    @State private var isExporting = false
    @State private var exportDocument: ShareDataDocument?
    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @State private var airDropShareItem: AirDropShareItem?
    @State private var isPreparingAirDropShare = false
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?
    @State private var advertisingEnabled = true
    @State private var browsingEnabled = true
    @State private var showingInvitationDialog = false
    @State private var didConfigureViewModel = false

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let remainingFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        Form {
            profileSection
            nearbyDevicesSection
            currentConnectionSection
            sendSection
            receiveSection
            advancedSection
        }
        .shareDataFormStyling()
        .navigationTitle(L10n.ShareData.title)
        .phScreen("shareData_screen_shareDataView")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: defaultExportFilename
        ) { result in
            handleExportResult(result)
        }
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
        .sheet(item: $airDropShareItem) { item in
            AirDropShareSheet(item: item) { outcome in
                let shareItem = item
                airDropShareItem = nil
                shareItem.cleanup()

                withAnimation {
                    isPreparingAirDropShare = false
                }

                if case let .failed(error) = outcome {
                    alert = ShareDataAlert(
                        title: L10n.ShareData.Alert.airDropFailureTitle,
                        message: L10n.ShareData.Alert.airDropFailureMessage(error.localizedDescription)
                    )
                }
            }
            .onAppear {
                withAnimation {
                    isPreparingAirDropShare = false
                }
            }
        }
        .confirmationDialog(
            L10n.ShareData.Nearby.invitationTitle,
            isPresented: $showingInvitationDialog,
            presenting: viewModel.pendingInvitation
        ) { peer in
            Button(L10n.ShareData.Nearby.acceptInvite(peer.displayName)) {
                viewModel.acceptInvitation()
            }
            .postHogLabel("shareData.acceptInvite")
            .phCaptureTap(
                event: "shareData_acceptInvite_button",
                properties: ["peer": peer.displayName]
            )

            Button(L10n.ShareData.Nearby.declineInvite, role: .cancel) {
                viewModel.declineInvitation()
            }
            .postHogLabel("shareData.declineInvite")
            .phCaptureTap(
                event: "shareData_declineInvite_button",
                properties: ["peer": peer.displayName]
            )
        } message: { peer in
            Text(L10n.ShareData.Nearby.invitationMessage(peer.displayName))
        }
        .onAppear {
            configureViewModelIfNeeded()
            processPendingExternalImportIfNeeded()
            startDefaultBrowsing()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhase(newPhase)
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: viewModel.pendingInvitation) { _, newValue in
            showingInvitationDialog = newValue != nil
        }
        .onReceive(viewModel.$toastMessage.compactMap { $0 }) { message in
            alert = ShareDataAlert(title: L10n.ShareData.Alert.toastTitle, message: message)
            viewModel.clearToast()
        }
        .onReceive(viewModel.$sessionState) { _ in
            syncStateToggles()
        }
        .onDisappear {
            viewModel.stopAll()
            shareDataCoordinator.dismissShareData()
        }
    }

    private var profileSection: some View {
        Section(header: Text(L10n.ShareData.profileSectionTitle)) {
            Text(L10n.ShareData.profileName(profileStore.activeProfile.displayName))
            let historyCount = actionStore.state(for: profileStore.activeProfile.id).history.count
            Text(L10n.ShareData.logCount(historyCount))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var nearbyDevicesSection: some View {
        Section(header: Text(L10n.ShareData.Nearby.devicesSectionTitle)) {
            if viewModel.nearbyPeers.isEmpty {
                Text(L10n.ShareData.Nearby.noPeers)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.nearbyPeers) { peer in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(peer.displayName)
                                .font(.headline)
                            if let version = peer.appVersion {
                                Text(L10n.ShareData.Nearby.appVersion(version))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            viewModel.invite(peer)
                        } label: {
                            Text(L10n.ShareData.Nearby.connect)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.sessionState == .inviting(peer) || viewModel.connectedPeer?.peerID == peer.peerID)
                        .postHogLabel("shareData.connectPeer")
                        .phCaptureTap(
                            event: "shareData_connectPeer_button",
                            properties: ["peer": peer.displayName]
                        )
                    }
                    .accessibilityLabel(Text(L10n.ShareData.Nearby.peerAccessibility(peer.displayName)))
                }
            }
        }
    }

    private var currentConnectionSection: some View {
        Section(header: Text(L10n.ShareData.Nearby.currentConnectionTitle)) {
            if let connected = viewModel.connectedPeer {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.ShareData.Nearby.connectedTo(connected.displayName))
                    if let version = connected.appVersion {
                        Text(L10n.ShareData.Nearby.appVersion(version))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        viewModel.disconnect()
                    } label: {
                        Text(L10n.ShareData.Nearby.disconnect)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .postHogLabel("shareData.disconnect")
                    .phCaptureTap(
                        event: "shareData_disconnect_button",
                        properties: ["peer": connected.displayName]
                    )
                }
            } else {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sendSection: some View {
        Section(header: Text(L10n.ShareData.Nearby.sendSectionTitle)) {
            ShareDataActionButton(
                title: L10n.ShareData.Nearby.sendSnapshot,
                systemImage: "person.crop.circle.badge.checkmark",
                tint: .accentColor
            ) {
                viewModel.sendProfileSnapshot()
            }
            .disabled(viewModel.connectedPeer == nil)
            .postHogLabel("shareData.sendSnapshot")
            .phCaptureTap(
                event: "shareData_sendSnapshot_button",
                properties: ["peer_connected": viewModel.connectedPeer?.displayName ?? "none"]
            )

            ShareDataActionButton(
                title: L10n.ShareData.Nearby.sendChanges,
                systemImage: "arrow.triangle.2.circlepath",
                tint: .indigo
            ) {
                viewModel.sendLatestChanges()
            }
            .disabled(viewModel.connectedPeer == nil)
            .postHogLabel("shareData.sendDelta")
            .phCaptureTap(
                event: "shareData_sendDelta_button",
                properties: ["peer_connected": viewModel.connectedPeer?.displayName ?? "none"]
            )

            ShareDataActionButton(
                title: L10n.ShareData.Nearby.sendExport,
                systemImage: "tray.and.arrow.up.fill",
                tint: .mint
            ) {
                sendFullExportOverMPC()
            }
            .disabled(viewModel.connectedPeer == nil || isPreparingAirDropShare)
            .postHogLabel("shareData.sendExport")
            .phCaptureTap(
                event: "shareData_sendExport_button",
                properties: ["peer_connected": viewModel.connectedPeer?.displayName ?? "none"]
            )

            if viewModel.transferProgress.isEmpty == false {
                ForEach(viewModel.transferProgress) { progress in
                    let detailText = transferDetail(for: progress)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(progressTitle(for: progress))
                                .font(.subheadline)
                            Spacer()
                            Text(progressPercentage(for: progress))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if viewModel.isTransferCancellable(progress) {
                                Button(L10n.ShareData.Nearby.cancelTransfer) {
                                    viewModel.cancelTransfer(progress)
                                }
                                .buttonStyle(.borderless)
                                .tint(.red)
                                .postHogLabel("shareData.cancelTransfer")
                                .phCaptureTap(
                                    event: "shareData_cancelTransfer_button",
                                    properties: cancelAnalyticsProperties(for: progress)
                                )
                                .accessibilityLabel(Text(L10n.ShareData.Nearby.cancelTransfer))
                            }
                        }
                        ProgressView(value: progress.progress)
                            .progressViewStyle(.linear)
                            .accessibilityLabel(Text(progressTitle(for: progress)))
                            .accessibilityValue(Text(progressPercentage(for: progress)))
                        Text(detailText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text(detailText))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var receiveSection: some View {
        Section(header: Text(L10n.ShareData.Nearby.receiveSectionTitle)) {
            if let timestamp = viewModel.lastReceivedAt {
                Text(L10n.ShareData.Nearby.lastReceived(relativeString(from: timestamp)))
            } else {
                Text(L10n.ShareData.Nearby.awaitingData)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        Section(header: Text(L10n.ShareData.advancedSectionTitle)) {
            Toggle(L10n.ShareData.Nearby.browsingToggle, isOn: $browsingEnabled)
                .onChange(of: browsingEnabled) { _, isOn in
                    if isOn {
                        viewModel.startBrowsing()
                    } else {
                        viewModel.stopBrowsing()
                    }
                }
                .postHogLabel("shareData.toggleBrowsing")
                .phCaptureTap(
                    event: "shareData_toggleBrowsing_toggle",
                    properties: ["enabled": browsingEnabled ? "true" : "false"]
                )

            Toggle(L10n.ShareData.Nearby.advertisingToggle, isOn: $advertisingEnabled)
                .onChange(of: advertisingEnabled) { _, isOn in
                    viewModel.advertise(on: isOn)
                }
                .postHogLabel("shareData.toggleAdvertising")
                .phCaptureTap(
                    event: "shareData_toggleAdvertising_toggle",
                    properties: ["enabled": advertisingEnabled ? "true" : "false"]
                )

            ShareDataActionButton(
                title: L10n.ShareData.AirDrop.shareButton,
                systemImage: "airplane.circle",
                tint: .blue,
                action: startAirDropShare,
                isLoading: isPreparingAirDropShare
            )
            .postHogLabel("shareData.airDrop")
            .phCaptureTap(
                event: "shareData_airdrop_button",
                properties: ["profile_id": profileStore.activeProfile.id.uuidString]
            )
            .disabled(isPreparingAirDropShare)

            ShareDataActionButton(
                title: L10n.ShareData.exportButton,
                systemImage: "square.and.arrow.up",
                tint: .accentColor,
                action: startExport
            )
            .postHogLabel("shareData.export")
            .phCaptureTap(
                event: "shareData_export_button",
                properties: ["profile_id": profileStore.activeProfile.id.uuidString]
            )

            ShareDataActionButton(
                title: L10n.ShareData.importButton,
                systemImage: "square.and.arrow.down",
                tint: .mint
            ) {
                isImporting = true
            }
            .postHogLabel("shareData.import")
            .phCaptureTap(
                event: "shareData_import_button",
                properties: ["profile_id": profileStore.activeProfile.id.uuidString]
            )

            importFooter
        }
    }

    private func configureViewModelIfNeeded() {
        guard didConfigureViewModel == false else { return }
        viewModel.configure(
            profileProvider: { profileStore.activeProfile },
            actionStateProvider: { actionStore.state(for: $0) }
        )
        didConfigureViewModel = true
    }

    private func startDefaultBrowsing() {
        if browsingEnabled {
            viewModel.startBrowsing()
        }
        if advertisingEnabled {
            viewModel.advertise(on: true)
        }
    }

    private func syncStateToggles() {
        switch viewModel.sessionState {
        case .browsing:
            browsingEnabled = true
        case .advertising:
            advertisingEnabled = true
        default:
            break
        }
    }

    private func sendFullExportOverMPC() {
        do {
            let data = try makeExportData()
            let filename = "\(defaultExportFilename).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: .atomic)
            viewModel.sendExportFile(at: url)
        } catch {
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.nearbyFailureTitle,
                message: L10n.ShareData.Alert.nearbyFailureMessage(error.localizedDescription)
            )
        }
    }

    private var defaultExportFilename: String {
        let name = profileStore.activeProfile.displayName
        let sanitized = sanitizeFilename(name)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        return "\(sanitized)-\(dateString)"
    }

    @ViewBuilder
    private var importFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.importFooter)
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

    private func startExport() {
        let profile = profileStore.activeProfile
        let state = actionStore.state(for: profile.id)
        let payload = SharedProfileData(profile: profile, actions: state)
        exportDocument = ShareDataDocument(payload: payload)
        isExporting = true
    }

    private func startAirDropShare() {
        guard isPreparingAirDropShare == false else { return }

        withAnimation {
            isPreparingAirDropShare = true
        }

        do {
            airDropShareItem?.cleanup()
            airDropShareItem = nil

            let data = try makeExportData()
            let filename = "\(defaultExportFilename).json"
            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL, options: .atomic)
            airDropShareItem = AirDropShareItem(url: destinationURL)
        } catch {
            withAnimation {
                isPreparingAirDropShare = false
            }
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.airDropFailureTitle,
                message: L10n.ShareData.Alert.airDropFailureMessage(error.localizedDescription)
            )
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

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.exportSuccessTitle,
                message: L10n.ShareData.Alert.exportSuccessMessage(url.lastPathComponent)
            )
        case let .failure(error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.exportFailureTitle,
                message: L10n.ShareData.Alert.exportFailureMessage
            )
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.importFailureTitle,
                    message: L10n.ShareData.Error.readFailed
                )
                return
            }
            importData(from: url)
        case let .failure(error):
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

            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.importSuccessTitle,
                message: importSuccessMessage(summary: summary)
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

    private func importSuccessMessage(summary: ActionLogStore.MergeSummary) -> String {
        var messages = [L10n.ShareData.importSummary(summary.added, summary.updated)]
        if didUpdateProfile {
            messages.append(L10n.ShareData.profileUpdatedNote)
        }
        return messages.joined(separator: "\n")
    }

    private func relativeString(from date: Date) -> String {
        DateFormatter.relative.localizedString(for: date, relativeTo: Date())
    }

    private func processPendingExternalImportIfNeeded() {
        guard let request = shareDataCoordinator.externalImportRequest else { return }
        guard processedExternalImportID != request.id else { return }
        processedExternalImportID = request.id
        importData(from: request.url)
        shareDataCoordinator.clearExternalImportRequest(request)
    }

    private func sanitizeFilename(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_") )
        let sanitizedScalars = name.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let sanitized = String(sanitizedScalars)
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_") )
        let base = trimmed.isEmpty ? "Profile" : trimmed
        return "\(base)-share"
    }

    private var statusText: String {
        switch viewModel.sessionState {
        case .idle:
            return L10n.ShareData.Nearby.statusIdle
        case .browsing:
            return L10n.ShareData.Nearby.statusBrowsing
        case .advertising:
            return L10n.ShareData.Nearby.statusAdvertising
        case let .inviting(peer):
            return L10n.ShareData.Nearby.statusInviting(peer.displayName)
        case let .connected(peer):
            return L10n.ShareData.Nearby.connectedTo(peer.displayName)
        case .disconnecting:
            return L10n.ShareData.Nearby.statusDisconnecting
        }
    }

    private func progressTitle(for progress: MPCTransferProgress) -> String {
        switch progress.kind {
        case let .message(type):
            return L10n.ShareData.Nearby.transferMessage(type.localizedDescription)
        case let .resource(name):
            return L10n.ShareData.Nearby.transferResource(name)
        }
    }

    private func progressPercentage(for progress: MPCTransferProgress) -> String {
        String(format: "%.0f%%", progress.progress * 100)
    }

    private func transferDetail(for progress: MPCTransferProgress) -> String {
        let transferred = ShareDataView.byteCountFormatter.string(fromByteCount: progress.bytesTransferred)
        let total = ShareDataView.byteCountFormatter.string(fromByteCount: max(progress.totalBytes, progress.bytesTransferred))
        var components = [L10n.ShareData.Nearby.transferDetail(transferred, total)]
        if let speed = transferSpeedDescription(for: progress) {
            components.append(L10n.ShareData.Nearby.transferSpeed(speed))
        }
        if let remaining = transferRemainingDescription(for: progress) {
            components.append(L10n.ShareData.Nearby.transferRemaining(remaining))
        }
        return components.joined(separator: " • ")
    }

    private func transferSpeedDescription(for progress: MPCTransferProgress) -> String? {
        let elapsed = progress.updatedAt.timeIntervalSince(progress.startedAt)
        guard elapsed > 0 else { return nil }
        let bytesPerSecond = Double(progress.bytesTransferred) / elapsed
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
        let formatted = ShareDataView.speedFormatter.string(fromByteCount: Int64(bytesPerSecond))
        return formatted
    }

    private func transferRemainingDescription(for progress: MPCTransferProgress) -> String? {
        guard let remaining = progress.estimatedRemainingTime, remaining.isFinite, remaining > 1 else {
            return nil
        }
        return ShareDataView.remainingFormatter.string(from: remaining)
    }

    private func cancelAnalyticsProperties(for progress: MPCTransferProgress) -> [String: Any] {
        var properties: [String: Any] = ["peer": progress.peerID.displayName]
        switch progress.kind {
        case let .resource(name):
            properties["resource"] = name
        case let .message(type):
            properties["messageType"] = type.rawValue
        }
        return properties
    }
}

private struct ShareDataActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    var isLoading: Bool = false

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

struct ShareDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var payload: SharedProfileData

    init(payload: SharedProfileData) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.payload = try decoder.decode(SharedProfileData.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return FileWrapper(regularFileWithContents: data)
    }
}

private struct AirDropShareItem: Identifiable {
    let id = UUID()
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private enum AirDropShareOutcome {
    case completed
    case cancelled
    case failed(Error)
}

private struct AirDropShareSheet: UIViewControllerRepresentable {
    let item: AirDropShareItem
    let completion: (AirDropShareOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item.url], applicationActivities: nil)
        controller.excludedActivityTypes = Self.nonAirDropActivities
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

    static var nonAirDropActivities: [UIActivity.ActivityType] {
        [
            .postToFacebook,
            .postToTwitter,
            .postToWeibo,
            .message,
            .mail,
            .print,
            .copyToPasteboard,
            .assignToContact,
            .saveToCameraRoll,
            .addToReadingList,
            .postToFlickr,
            .postToVimeo,
            .postToTencentWeibo,
            .openInIBooks,
            .markupAsPDF
        ]
    }

    final class Coordinator {
        let completion: (AirDropShareOutcome) -> Void

        init(completion: @escaping (AirDropShareOutcome) -> Void) {
            self.completion = completion
        }
    }
}

private extension DateFormatter {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private extension MPCMessageType {
    var localizedDescription: String {
        switch self {
        case .hello:
            return L10n.ShareData.Nearby.messageHello
        case .capabilities:
            return L10n.ShareData.Nearby.messageCapabilities
        case .profileSnapshot:
            return L10n.ShareData.Nearby.messageSnapshot
        case .actionsDelta:
            return L10n.ShareData.Nearby.messageDelta
        case .ack:
            return L10n.ShareData.Nearby.messageAck
        case .error:
            return L10n.ShareData.Nearby.messageError
        }
    }
}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(
        initialProfiles: [profile],
        activeProfileID: profile.id,
        directory: FileManager.default.temporaryDirectory,
        filename: "shareDataPreviewProfiles.json"
    )

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(category: .feeding, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-6900))
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return NavigationStack {
        ShareDataView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator())
    }
}
