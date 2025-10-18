import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

struct ShareProfilePage: View {
    @EnvironmentObject private var cloudStatusController: CloudAccountStatusController
    @EnvironmentObject private var appDataStack: AppDataStack
    let profileID: UUID

    private var isCloudSharingAvailable: Bool {
        cloudStatusController.status == .available && appDataStack.cloudSyncEnabled
    }

    var body: some View {
        if isCloudSharingAvailable,
           let metadataStore = appDataStack.shareMetadataStore,
           let subscriptionManager = appDataStack.sharedSubscriptionManager {
            ShareProfilePageContent(
                profileID: profileID,
                modelContainer: appDataStack.modelContainer,
                metadataStore: metadataStore,
                subscriptionManager: subscriptionManager
            )
        } else {
            ShareProfileUnavailableView()
        }
    }
}

private struct ShareProfilePageContent: View {
    let profileID: UUID
    @StateObject private var viewModel: ShareProfilePageViewModel
    @State private var participantPendingRemoval: ShareParticipantItem?
    @State private var isConfirmingStopShare = false

    init(profileID: UUID,
         modelContainer: ModelContainer,
         metadataStore: ShareMetadataStore,
         subscriptionManager: SharedScopeSubscriptionManager,
         containerIdentifier: String = "iCloud.com.prioritybit.babynanny") {
        self.profileID = profileID
        _viewModel = StateObject(wrappedValue: ShareProfilePageViewModel(
            profileID: profileID,
            modelContainer: modelContainer,
            metadataStore: metadataStore,
            subscriptionManager: subscriptionManager,
            containerIdentifier: containerIdentifier
        ))
    }

    var body: some View {
        List {
            shareActionSection
            participantsSection
            if viewModel.shareExists {
                stopSharingSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.ShareData.title)
        .onAppear {
            viewModel.onAppear()
        }
        .sheet(item: $viewModel.shareSheetPayload) { payload in
            ShareProfileSheet(
                payload: payload,
                container: viewModel.container,
                onDidSaveShare: {
                    Task { await viewModel.refreshParticipants() }
                },
                onDidStopSharing: {
                    Task { await viewModel.handleShareStoppedBySystem() }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(item: $viewModel.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(L10n.Common.done)))
        }
        .confirmationDialog(
            LocalizedStringKey(ShareStrings.removeParticipantTitle),
            isPresented: Binding(
                get: { participantPendingRemoval != nil },
                set: { isPresented in
                    if isPresented == false {
                        participantPendingRemoval = nil
                    }
                }
            ),
            presenting: participantPendingRemoval
        ) { item in
            Button(role: .destructive) {
                participantPendingRemoval = nil
                Task { await viewModel.removeParticipant(item) }
            } label: {
                Text(ShareStrings.confirmRemoveParticipantButton)
            }
            .postHogLabel("shareData.confirmRemoveParticipantButton")
            .phCaptureTap(
                event: "shareData_confirmRemoveParticipant_button",
                properties: [
                    "profile_id": profileID.uuidString,
                    "participant_id": item.id
                ]
            )
            Button(L10n.Common.cancel, role: .cancel) {}
                .postHogLabel("shareData.cancelRemoveParticipantButton")
                .phCaptureTap(
                    event: "shareData_cancelRemoveParticipant_button",
                    properties: ["profile_id": profileID.uuidString]
                )
        } message: { item in
            Text(ShareStrings.removeParticipantMessage(item.displayName))
        }
        .confirmationDialog(
            LocalizedStringKey(ShareStrings.stopSharingConfirmTitle),
            isPresented: $isConfirmingStopShare
        ) {
            Button(role: .destructive) {
                Task { await viewModel.stopSharing() }
            } label: {
                Text(ShareStrings.stopSharingButton)
            }
            .disabled(viewModel.isStoppingShare)
            .postHogLabel("shareData.confirmStopSharingButton")
            .phCaptureTap(
                event: "shareData_confirmStopSharing_button",
                properties: ["profile_id": profileID.uuidString]
            )
            Button(L10n.Common.cancel, role: .cancel) {}
                .postHogLabel("shareData.cancelStopSharingButton")
                .phCaptureTap(
                    event: "shareData_cancelStopSharing_button",
                    properties: ["profile_id": profileID.uuidString]
                )
        } message: {
            Text(ShareStrings.stopSharingMessage)
        }
    }

    @ViewBuilder
    private var shareActionSection: some View {
        Section {
            Button {
                Task { await viewModel.prepareSharingInterface() }
            } label: {
                ManageShareButtonLabel(
                    title: viewModel.shareExists ? ShareStrings.manageShareButton : ShareStrings.shareProfileButton,
                    isLoading: viewModel.isPreparingShareUI
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPreparingShareUI)
            .postHogLabel("shareData.manageSharingButton")
            .phCaptureTap(
                event: "shareData_manageSharing_button",
                properties: ["profile_id": profileID.uuidString]
            )
        }
    }

    @ViewBuilder
    private var participantsSection: some View {
        Section(LocalizedStringKey(ShareStrings.participantsSectionTitle)) {
            if viewModel.isLoadingParticipants {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else if viewModel.participants.isEmpty {
                Text(viewModel.shareExists ? ShareStrings.noParticipantsMessage : ShareStrings.notSharedMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.participants) { item in
                    ShareParticipantRow(
                        item: item,
                        isProcessing: viewModel.processingParticipantID == item.id,
                        profileID: profileID,
                        onChangePermission: { newPermission in
                            Task { await viewModel.updatePermission(for: item, to: newPermission) }
                        },
                        onRemove: {
                            participantPendingRemoval = item
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var stopSharingSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingStopShare = true
            } label: {
                StopSharingButtonLabel(isLoading: viewModel.isStoppingShare)
            }
            .disabled(viewModel.isStoppingShare)
            .postHogLabel("shareData.stopSharingButton")
            .phCaptureTap(
                event: "shareData_stopSharing_button",
                properties: ["profile_id": profileID.uuidString]
            )
        } footer: {
            Text(ShareStrings.stopSharingFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShareProfileUnavailableView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var cloudStatusController: CloudAccountStatusController

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.ShareData.Unavailable.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(L10n.ShareData.Unavailable.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                Analytics.capture("shareProfile_open_settings_button", properties: ["status": cloudStatusController.status.analyticsValue])
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            } label: {
                Text(L10n.ShareData.Unavailable.openSettings)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .postHogLabel("shareData.unavailable.openSettings")
            Button {
                Analytics.capture("shareProfile_retry_cloud_button", properties: ["status": cloudStatusController.status.analyticsValue])
                cloudStatusController.refreshAccountStatus(force: true)
            } label: {
                Text(L10n.ShareData.Unavailable.retry)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .postHogLabel("shareData.unavailable.retry")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.ShareData.title)
    }
}

// MARK: - View model

@MainActor
private final class ShareProfilePageViewModel: ObservableObject {
    @Published var participants: [ShareParticipantItem] = []
    @Published var isLoadingParticipants = false
    @Published var isPreparingShareUI = false
    @Published var shareExists = false
    @Published var processingParticipantID: String?
    @Published var shareSheetPayload: ShareSheetPayload?
    @Published var alert: ShareAlert?
    @Published var isStoppingShare = false

    let profileID: UUID
    let container: CKContainer

    private let metadataStore: ShareMetadataStore
    private let sharingManager: CloudKitSharingManager
    private let subscriptionManager: SharedScopeSubscriptionManager
    private let modelContainer: ModelContainer
    private var cancellables: Set<AnyCancellable> = []
    private var hasLoaded = false
    private var cachedProfileSummary: ProfileSummary?
    private var currentUserDisplayName: String?
    private var currentUserNameTask: Task<String?, Never>?
    private let nameFormatter: PersonNameComponentsFormatter = {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter
    }()

    init(profileID: UUID,
         modelContainer: ModelContainer,
         metadataStore: ShareMetadataStore,
         subscriptionManager: SharedScopeSubscriptionManager,
         containerIdentifier: String) {
        self.profileID = profileID
        self.modelContainer = modelContainer
        self.metadataStore = metadataStore
        self.sharingManager = CloudKitSharingManager(modelContainer: modelContainer, metadataStore: metadataStore)
        self.subscriptionManager = subscriptionManager
        self.container = CKContainer(identifier: containerIdentifier)
        configurePushHandling()
    }

    deinit {
        currentUserNameTask?.cancel()
    }

    func onAppear() {
        guard hasLoaded == false else { return }
        hasLoaded = true
        subscriptionManager.ensureSubscriptions()
        Task { _ = await resolveCurrentUserDisplayName() }
        Task { await refreshParticipants() }
    }

    func prepareSharingInterface() async {
        guard isPreparingShareUI == false else { return }
        isPreparingShareUI = true
        defer { isPreparingShareUI = false }

        do {
            let summary = await loadProfileSummary()
            let share = try await sharingManager.ensureShare(for: profileID)
            shareExists = true
            await applyParticipants(from: share.participants)
            let fallbackTitle = share[CKShare.SystemFieldKey.title] as? String
            let fallbackImageData = share[CKShare.SystemFieldKey.thumbnailImageData] as? Data
            shareSheetPayload = ShareSheetPayload(
                share: share,
                displayName: summary?.name ?? fallbackTitle,
                thumbnailData: summary?.imageData ?? fallbackImageData
            )
        } catch {
            alert = ShareAlert(message: error.localizedDescription)
        }
    }

    func refreshParticipants() async {
        if await metadataStore.metadata(for: profileID) == nil {
            shareExists = false
            participants = []
            return
        }

        isLoadingParticipants = true
        defer { isLoadingParticipants = false }

        do {
            let participants = try await sharingManager.fetchParticipants(for: profileID)
            shareExists = true
            await applyParticipants(from: participants)
        } catch {
            alert = ShareAlert(message: error.localizedDescription)
        }
    }

    func updatePermission(for item: ShareParticipantItem,
                          to permission: CKShare.ParticipantPermission) async {
        guard item.participant.permission != permission else { return }
        guard processingParticipantID == nil else { return }
        processingParticipantID = item.id
        defer { processingParticipantID = nil }

        do {
            try await sharingManager.updateParticipant(for: profileID,
                                                       participant: item.participant,
                                                       role: nil,
                                                       permission: permission)
            await refreshParticipants()
        } catch {
            alert = ShareAlert(message: error.localizedDescription)
        }
    }

    func removeParticipant(_ item: ShareParticipantItem) async {
        guard processingParticipantID == nil else { return }
        processingParticipantID = item.id
        defer { processingParticipantID = nil }

        do {
            try await sharingManager.removeParticipant(for: profileID, participant: item.participant)
            await refreshParticipants()
        } catch {
            alert = ShareAlert(message: error.localizedDescription)
        }
    }

    func stopSharing() async {
        guard isStoppingShare == false else { return }
        isStoppingShare = true
        defer { isStoppingShare = false }

        do {
            try await sharingManager.stopSharing(profileID: profileID)
            shareExists = false
            participants = []
        } catch {
            alert = ShareAlert(message: error.localizedDescription)
        }
    }

    func handleShareStoppedBySystem() async {
        await metadataStore.remove(profileID: profileID)
        await refreshParticipants()
    }

    private func applyParticipants(from participants: [CKShare.Participant]) async {
        let ownerName = await resolveCurrentUserDisplayName()
        let items = participants
            .map { ShareParticipantItem(participant: $0, ownerFallbackName: ownerName) }
            .sorted(by: ShareParticipantItem.sortComparator)
        self.participants = items
    }

    private func resolveCurrentUserDisplayName() async -> String? {
        if let currentUserDisplayName {
            return currentUserDisplayName
        }

        if let currentUserNameTask {
            return await currentUserNameTask.value
        }

        let task = Task<String?, Never> {
            do {
                if let participant = try await fetchCurrentUserParticipant() {
                    if let components = participant.userIdentity.nameComponents {
                        let formatted = nameFormatter.string(from: components)
                        if formatted.isEmpty == false {
                            return formatted
                        }
                    }
                    if let email = participant.userIdentity.lookupInfo?.emailAddress, email.isEmpty == false {
                        return email
                    }
                    if let phone = participant.userIdentity.lookupInfo?.phoneNumber, phone.isEmpty == false {
                        return phone
                    }
                }
                let deviceName = UIDevice.current.name
                if deviceName.isEmpty == false {
                    return deviceName
                }
            } catch {
                return nil
            }
            return nil
        }
        currentUserNameTask = task
        let name = await task.value
        currentUserDisplayName = name
        currentUserNameTask = nil
        return name
    }

    private func configurePushHandling() {
        NotificationCenter.default.publisher(for: .sharedScopeNotification)
            .compactMap { $0.object as? CKNotification }
            .sink { [weak self] notification in
                guard let self else { return }
                Task {
                    _ = await self.subscriptionManager.handleRemoteNotification(notification)
                    await self.refreshParticipants()
                }
            }
            .store(in: &cancellables)
    }

    private func fetchCurrentUserParticipant() async throws -> CKShare.Participant? {
        let recordID = try await container.userRecordID()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Participant?, Error>) in
            let lookup = CKUserIdentity.LookupInfo(userRecordID: recordID)
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            var resultParticipant: CKShare.Participant?
            operation.shareParticipantFetchedBlock = { participant in
                resultParticipant = participant
            }
            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: resultParticipant)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    private func loadProfileSummary() async -> ProfileSummary? {
        if let cachedProfileSummary {
            return cachedProfileSummary
        }

        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        return await Task.detached(priority: .userInitiated) {
            let descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: #Predicate { $0.profileID == profileID })
            guard let model = try? context.fetch(descriptor).first else { return nil }
            let summary = ProfileSummary(name: model.name, imageData: model.imageData)
            await MainActor.run { [weak self] in
                self?.cachedProfileSummary = summary
            }
            return summary
        }.value
    }
}

