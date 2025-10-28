import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum ShareDataCloudKitConfiguration {
    static let container = CKContainer(identifier: "iCloud.com.prioritybit.babynanny")
}

struct ShareDataView: View {
    @EnvironmentObject private var appDataStack: AppDataStack
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator

    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?
    @State private var shareState: CloudShareState = .loading
    @State private var sharePresentation: CloudSharePresentation?
    @State private var isPreparingShare = false

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
                    title: L10n.ShareData.CloudKit.inviteButton,
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .blue,
                    action: startCloudShare,
                    analyticsLabel: "shareData_invite_button_shareView",
                    isLoading: isPreparingShare
                )
                .disabled(isShareButtonDisabled)

                if case .shared = shareState {
                    ShareDataActionButton(
                        title: L10n.ShareData.CloudKit.stopButton,
                        systemImage: "person.crop.circle.badge.xmark",
                        tint: .red,
                        action: stopCloudShare,
                        analyticsLabel: "shareData_stopShare_button_shareView",
                        isLoading: isPreparingShare
                    )
                    .disabled(isPreparingShare)
                }

                if shareState == .loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(L10n.ShareData.CloudKit.sectionTitle)
            } footer: {
                shareFooter
            }

            Section {
                ShareDataActionButton(
                    title: L10n.ShareData.importButton,
                    systemImage: "square.and.arrow.down",
                    tint: .mint,
                    action: { isImporting = true },
                    analyticsLabel: "shareData_import_button_shareView"
                )
            } header: {
                Text(L10n.ShareData.importSectionTitle)
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
            Task { @MainActor in
                handleImportResult(result)
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.Common.done))
            )
        }
        .sheet(item: $sharePresentation) { presentation in
            CloudShareSheet(share: presentation.share, profileName: presentation.profileName) { outcome in
                sharePresentation = nil
                handleCloudShareOutcome(outcome)
            }
        }
        .onAppear {
            refreshShareStatus()
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: profileStore.activeProfile.id) { _, _ in
            refreshShareStatus()
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onDisappear {
            shareDataCoordinator.dismissShareData()
        }
    }

    private var isShareButtonDisabled: Bool {
        isPreparingShare || shareState == .loading || shareState == .unsupported
    }

    @ViewBuilder
    private var shareFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.CloudKit.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if case let .shared(participantCount) = shareState {
                Text(L10n.ShareData.CloudKit.sharedFooter(participantCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if shareState == .unsupported {
                Text(L10n.ShareData.CloudKit.unsupportedFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func startCloudShare() {
        guard isPreparingShare == false else { return }

        isPreparingShare = true

        Task { @MainActor in
            defer { isPreparingShare = false }

            do {
                guard let profileModel = try fetchActiveProfileModel() else {
                    alert = ShareDataAlert(
                        title: L10n.ShareData.Alert.cloudShareFailureTitle,
                        message: L10n.ShareData.Alert.cloudShareFailureMessage()
                    )
                    return
                }

                let share = try prepareShare(for: profileModel)
                sharePresentation = CloudSharePresentation(share: share, profileName: profileStore.activeProfile.displayName)
                refreshShareStatus()
            } catch let error as SwiftDataCloudSharing.ShareError {
                alert = ShareDataAlert(
                    title: L10n.ShareData.CloudKit.unsupportedAlertTitle,
                    message: error.localizedDescription
                )
                shareState = .unsupported
            } catch {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.cloudShareFailureTitle,
                    message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription)
                )
                refreshShareStatus()
            }
        }
    }

    private func stopCloudShare() {
        guard case .shared = shareState, isPreparingShare == false else { return }

        isPreparingShare = true

        Task { @MainActor in
            defer { isPreparingShare = false }

            do {
                guard let profileModel = try fetchActiveProfileModel() else {
                    shareState = .notShared
                    return
                }

                try SwiftDataCloudSharing.stopSharing(profileModel, in: appDataStack.mainContext)
                shareState = .notShared
            } catch let error as SwiftDataCloudSharing.ShareError {
                alert = ShareDataAlert(
                    title: L10n.ShareData.CloudKit.unsupportedAlertTitle,
                    message: error.localizedDescription
                )
                shareState = .unsupported
            } catch {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Alert.cloudShareStopFailureTitle,
                    message: L10n.ShareData.Alert.cloudShareStopFailureMessage(error.localizedDescription)
                )
                refreshShareStatus()
            }
        }
    }

    private func refreshShareStatus() {
        Task { @MainActor in
            shareState = .loading

            do {
                guard let profileModel = try fetchActiveProfileModel() else {
                    shareState = .notShared
                    return
                }

                if let share = try SwiftDataCloudSharing.fetchShare(for: profileModel, in: appDataStack.mainContext) {
                    let participants = nonOwnerParticipantCount(from: share)
                    shareState = .shared(participantCount: participants)
                } else {
                    shareState = .notShared
                }
            } catch is SwiftDataCloudSharing.ShareError {
                shareState = .unsupported
            } catch {
                shareState = .notShared
            }
        }
    }

    @MainActor
    private func fetchActiveProfileModel() throws -> ProfileActionStateModel? {
        let activeID = profileStore.activeProfile.id
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == activeID
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try appDataStack.mainContext.fetch(descriptor)
        return results.first
    }

    @MainActor
    private func prepareShare(for profile: ProfileActionStateModel) throws -> CKShare {
        if let existing = try SwiftDataCloudSharing.fetchShare(for: profile, in: appDataStack.mainContext) {
            return existing
        }
        return try SwiftDataCloudSharing.share(profile, in: appDataStack.mainContext, to: [])
    }

    private func nonOwnerParticipantCount(from share: CKShare) -> Int {
        share.participants.filter { $0.role != .owner }.count
    }

    private func handleCloudShareOutcome(_ outcome: CloudShareOutcome) {
        switch outcome {
        case .failed(let error):
            alert = ShareDataAlert(
                title: L10n.ShareData.Alert.cloudShareFailureTitle,
                message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription)
            )
        case .saved, .stopped, .dismissed:
            break
        }

        refreshShareStatus()
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    private func processPendingExternalImportIfNeeded() {
        guard let request = shareDataCoordinator.externalImportRequest else { return }
        guard processedExternalImportID != request.id else { return }
        processedExternalImportID = request.id
        importData(from: request.url)
        shareDataCoordinator.clearExternalImportRequest(request)
    }
}

private enum CloudShareState: Equatable {
    case loading
    case notShared
    case shared(participantCount: Int)
    case unsupported
}

private struct CloudSharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let profileName: String
}

private enum CloudShareOutcome {
    case saved
    case stopped
    case failed(Error)
    case dismissed
}

private struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let profileName: String
    let completion: (CloudShareOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(profileName: profileName, completion: completion)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: ShareDataCloudKitConfiguration.container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let profileName: String
        let completion: (CloudShareOutcome) -> Void

        init(profileName: String, completion: @escaping (CloudShareOutcome) -> Void) {
            self.profileName = profileName
            self.completion = completion
        }

        func cloudSharingController(_ c: UICloudSharingController, failedToSaveShareWithError error: Error) {
            completion(.failed(error))
        }

        func cloudSharingControllerDidSaveShare(_ c: UICloudSharingController) {
            completion(.saved)
        }

        func cloudSharingControllerDidStopSharing(_ c: UICloudSharingController) {
            completion(.stopped)
        }

        func cloudSharingControllerDidFinish(_ c: UICloudSharingController) {
            completion(.dismissed)
        }

        func itemTitle(for c: UICloudSharingController) -> String? {
            profileName
        }
    }
}

private struct ShareDataActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    let analyticsLabel: String
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
        .postHogLabel(analyticsLabel)
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
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(category: .feeding, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-6900))
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return NavigationStack {
        ShareDataView()
            .environmentObject(AppDataStack.preview())
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator())
    }
}
