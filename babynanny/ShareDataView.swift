import SwiftUI
import UniformTypeIdentifiers

struct ShareDataView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore

    @State private var isExporting = false
    @State private var exportDocument: ShareDataDocument?
    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @StateObject private var nearbyShareController = NearbyShareController()
    @State private var isPresentingNearbyBrowser = false
    @State private var pendingNearbyAlert: ShareDataAlert?

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

    private func startNearbyShare() {
        do {
            let data = try makeExportData()
            let filename = "\(defaultExportFilename).json"
            nearbyShareController.prepareShare(data: data, filename: filename)
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

private struct ShareDataActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
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
    }
}
