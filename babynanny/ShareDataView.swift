import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareDataView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator

    @State private var isExporting = false
    @State private var exportDocument: ShareDataDocument?
    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @StateObject private var nearbyShareController = NearbyShareController()
    @State private var isPresentingNearbyBrowser = false
    @State private var pendingNearbyAlert: ShareDataAlert?
    @State private var airDropShareItem: AirDropShareItem?
    @State private var isPreparingAirDropShare = false
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?

    var body: some View {
        Form {
            Section(header: Text(L10n.ShareData.profileSectionTitle)) {
                Text(L10n.ShareData.profileName(profileStore.activeProfile.displayName))
                let historyCount = actionStore.state(for: profileStore.activeProfile.id).history.count
                Text(L10n.ShareData.logCount(historyCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
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
                    properties: [
                        "profile_id": profileStore.activeProfile.id.uuidString
                    ]
                )
                .disabled(nearbyShareController.isBusy || isPreparingAirDropShare)
            } header: {
                Text(L10n.ShareData.AirDrop.sectionTitle)
            } footer: {
                Text(L10n.ShareData.AirDrop.footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
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
            } header: {
                Text(L10n.ShareData.exportSectionTitle)
            } footer: {
                Text(L10n.ShareData.exportFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ShareDataActionButton(
                    title: L10n.ShareData.importButton,
                    systemImage: "square.and.arrow.down",
                    tint: .mint,
                    action: { isImporting = true }
                )
                .postHogLabel("shareData.import")
                .phCaptureTap(
                    event: "shareData_import_button",
                    properties: ["profile_id": profileStore.activeProfile.id.uuidString]
                )
            } header: {
                Text(L10n.ShareData.importSectionTitle)
            } footer: {
                importFooter
            }

            Section {
                ShareDataActionButton(
                    title: L10n.ShareData.Nearby.shareButton,
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .indigo,
                    action: startNearbyShare
                )
                .postHogLabel("shareData.nearbyShare")
                .phCaptureTap(
                    event: "shareData_nearby_share_button",
                    properties: [
                        "profile_id": profileStore.activeProfile.id.uuidString,
                        "is_busy": nearbyShareController.isBusy ? "true" : "false"
                    ]
                )
                .disabled(nearbyShareController.isBusy)
            } header: {
                Text(L10n.ShareData.Nearby.sectionTitle)
            } footer: {
                nearbyFooter
            }
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
        .sheet(isPresented: $isPresentingNearbyBrowser, onDismiss: {
            nearbyShareController.cancelSharing()
            if let pendingAlert = pendingNearbyAlert {
                alert = pendingAlert
                pendingNearbyAlert = nil
            }
        }) {
            NearbyShareBrowserView(controller: nearbyShareController)
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
        .onReceive(nearbyShareController.resultPublisher) { result in
            let wasPresentingBrowser = isPresentingNearbyBrowser
            isPresentingNearbyBrowser = false

            let pendingAlert: ShareDataAlert?
            switch result.outcome {
            case let .success(peer, filename):
                pendingAlert = ShareDataAlert(
                    title: L10n.ShareData.Alert.nearbySuccessTitle,
                    message: L10n.ShareData.Alert.nearbySuccessMessage(filename, peer)
                )
            case let .failure(message):
                pendingAlert = ShareDataAlert(
                    title: L10n.ShareData.Alert.nearbyFailureTitle,
                    message: message
                )
            case .cancelled:
                pendingAlert = nil
            }

            if let pendingAlert {
                if wasPresentingBrowser {
                    pendingNearbyAlert = pendingAlert
                } else {
                    alert = pendingAlert
                }
            }

            nearbyShareController.clearLatestResult()
        }
        .onAppear {
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onDisappear {
            shareDataCoordinator.dismissShareData()
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

    @ViewBuilder
    private var nearbyFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.Nearby.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let status = nearbyStatusDescription {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        guard !isPreparingAirDropShare else { return }

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

    private func startNearbyShare() {
        do {
            let data = try makeExportData()
            let filename = "\(defaultExportFilename).json"
            nearbyShareController.prepareShare(data: data, filename: filename)
            nearbyShareController.beginPresentingBrowser()
            isPresentingNearbyBrowser = true
        } catch {
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.nearbyFailureTitle,
                message: L10n.ShareData.Alert.nearbyFailureMessage(error.localizedDescription)
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
        case .success(let url):
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.exportSuccessTitle,
                message: L10n.ShareData.Alert.exportSuccessMessage(url.lastPathComponent)
            )
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.exportFailureTitle,
                message: L10n.ShareData.Alert.exportFailureMessage
            )
        }
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
        return "\(base)-share"
    }

    private var nearbyStatusDescription: String? {
        switch nearbyShareController.phase {
        case .idle:
            return nil
        case .preparing:
            return L10n.ShareData.Nearby.statusPreparing
        case .presenting:
            return L10n.ShareData.Nearby.statusWaiting
        case let .sending(peer):
            return L10n.ShareData.Nearby.statusSending(peer)
        }
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
        BabyAction(category: .feeding, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-6900))
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return NavigationStack {
        ShareDataView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator())
    }
}
