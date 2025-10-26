import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareDataView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator

    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @State private var airDropShareItem: AirDropShareItem?
    @State private var isPreparingAirDropShare = false
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?

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

            if supportsCloudSharing {
                Section {
                    NavigationLink {
                        ShareProfilePage()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(L10n.ShareData.CloudKit.manageButton, systemImage: "person.2.badge.checkmark")
                                .labelStyle(.titleAndIcon)
                            Text(L10n.ShareData.CloudKit.manageDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .postHogLabel("shareData_manage_button_shareDataView")
                } header: {
                    Text(L10n.ShareData.CloudKit.sectionTitle)
                } footer: {
                    Text(L10n.ShareData.CloudKit.footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ShareDataActionButton(
                        title: L10n.ShareData.AirDrop.shareButton,
                        systemImage: "airplane.circle",
                        tint: .blue,
                        action: startAirDropShare,
                        isLoading: isPreparingAirDropShare,
                        postHogLabel: "shareData_airDrop_button_shareDataView"
                    )
                    .disabled(isPreparingAirDropShare)

                    ShareDataActionButton(
                        title: L10n.ShareData.importButton,
                        systemImage: "square.and.arrow.down",
                        tint: .mint,
                        action: { isImporting = true },
                        postHogLabel: "shareData_import_button_shareDataView"
                    )
                } header: {
                    Text(L10n.ShareData.Legacy.sectionTitle)
                } footer: {
                    legacySectionFooter
                }
            } else {
                Section {
                    ShareDataActionButton(
                        title: L10n.ShareData.AirDrop.shareButton,
                        systemImage: "airplane.circle",
                        tint: .blue,
                        action: startAirDropShare,
                        isLoading: isPreparingAirDropShare,
                        postHogLabel: "shareData_airDrop_button_shareDataView"
                    )
                    .disabled(isPreparingAirDropShare)
                } header: {
                    Text(L10n.ShareData.AirDrop.sectionTitle)
                } footer: {
                    Text(L10n.ShareData.AirDrop.footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ShareDataActionButton(
                        title: L10n.ShareData.importButton,
                        systemImage: "square.and.arrow.down",
                        tint: .mint,
                        action: { isImporting = true },
                        postHogLabel: "shareData_import_button_shareDataView"
                    )
                } header: {
                    Text(L10n.ShareData.importSectionTitle)
                } footer: {
                    importSummaryDetails
                }
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

    private var supportsCloudSharing: Bool {
        if #available(iOS 17.4, *) {
            return true
        }
        return false
    }

    @ViewBuilder
    private var importSummaryDetails: some View {
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
    private var legacySectionFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.Legacy.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(L10n.ShareData.AirDrop.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)

            importSummaryDetails
        }
    }

    @MainActor
    private func fetchProfileModel(for profileID: UUID) throws -> ProfileActionStateModel? {
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == profileID
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
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
        return "\(base)-share"
    }

}

private struct AirDropShareItem: Identifiable {
    let id = UUID()
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class AirDropShareItemSource: NSObject, UIActivityItemSource {
    private let item: AirDropShareItem

    init(item: AirDropShareItem) {
        self.item = item
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        item.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        item.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        if #available(iOS 14.0, *) {
            return UTType.json.identifier
        }
        return "public.json"
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
        let activityItem = AirDropShareItemSource(item: item)
        let controller = UIActivityViewController(activityItems: [activityItem], applicationActivities: nil)
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
    let postHogLabel: String

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
        .postHogLabel(postHogLabel)
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

#Preview {
    let dataStack = AppDataStack.preview()
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(
        initialProfiles: [profile],
        activeProfileID: profile.id,
        directory: FileManager.default.temporaryDirectory,
        filename: "shareDataPreviewProfiles.json"
    )

    let actionStore = ActionLogStore(modelContext: dataStack.modelContainer.mainContext, dataStack: dataStack)
    profileStore.registerActionStore(actionStore)
    actionStore.registerProfileStore(profileStore)

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(category: .feeding, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-6900))
    ]
    _ = actionStore.mergeProfileState(state, for: profile.id)

    return NavigationStack {
        ShareDataView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator())
    }
    .modelContainer(dataStack.modelContainer)
}
