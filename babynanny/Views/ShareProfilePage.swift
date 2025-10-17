import CloudKit
import Combine
import SwiftData
import SwiftUI
import UIKit

struct ShareProfilePage: View {
    let profileID: UUID

    @StateObject private var viewModel: ShareProfilePageViewModel
    @State private var participantPendingRemoval: ShareParticipantItem?
    @State private var isConfirmingStopShare = false

    init(profileID: UUID) {
        self.profileID = profileID
        _viewModel = StateObject(wrappedValue: ShareProfilePageViewModel(profileID: profileID))
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
         modelContainer: ModelContainer? = nil,
         containerIdentifier: String = "iCloud.com.prioritybit.babynanny") {
        self.profileID = profileID
        let resolvedModelContainer = modelContainer ?? AppDataStack.shared.modelContainer
        let metadataStore = ShareMetadataStore()
        self.metadataStore = metadataStore
        self.sharingManager = CloudKitSharingManager(modelContainer: resolvedModelContainer, metadataStore: metadataStore)
        self.container = CKContainer(identifier: containerIdentifier)
        self.subscriptionManager = SharedScopeSubscriptionManager(shareMetadataStore: metadataStore, ingestor: nil)
        self.modelContainer = resolvedModelContainer
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
            try await sharingManager.updateParticipant(item.participant, role: nil, permission: permission)
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
            try await sharingManager.removeParticipant(item.participant)
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
                subscriptionManager.handleRemoteNotification(notification)
                Task { await self.refreshParticipants() }
            }
            .store(in: &cancellables)
    }

    private func fetchCurrentUserParticipant() async throws -> CKShare.Participant? {
        let recordID = try await container.userRecordID()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare.Participant?, Error>) in
            let lookup = CKUserIdentity.LookupInfo(userRecordID: recordID)
            let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: [lookup])
            operation.qualityOfService = .userInitiated

            var fetchedParticipant: CKShare.Participant?
            operation.shareParticipantFetchedBlock = { participant in
                if fetchedParticipant == nil {
                    fetchedParticipant = participant
                }
            }

            operation.fetchShareParticipantsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: fetchedParticipant)
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

        let targetProfileID = profileID
        let summary = await Task.detached(priority: .userInitiated) { [modelContainer] () -> ProfileSummary? in
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            let predicate = #Predicate<ProfileActionStateModel> { model in
                model.profileID == targetProfileID
            }
            var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let model = try? context.fetch(descriptor).first else { return nil }
            return ProfileSummary(name: model.name, imageData: model.imageData)
        }.value

        cachedProfileSummary = summary
        return summary
    }
}

// MARK: - Models

private struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let displayName: String?
    let thumbnailData: Data?
}

private struct ProfileSummary: Sendable {
    let name: String?
    let imageData: Data?
}

private struct ShareAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String = ShareStrings.errorTitle, message: String) {
        self.title = title
        self.message = message
    }
}

private struct ShareParticipantItem: Identifiable, Equatable {
    let id: String
    let participant: CKShare.Participant
    private let ownerFallbackName: String?

    init(participant: CKShare.Participant, ownerFallbackName: String?) {
        self.participant = participant
        self.ownerFallbackName = ownerFallbackName
        if let recordName = participant.userIdentity.userRecordID?.recordName {
            self.id = recordName
        } else if let email = participant.userIdentity.lookupInfo?.emailAddress {
            self.id = "email-" + email
        } else if let phone = participant.userIdentity.lookupInfo?.phoneNumber {
            self.id = "phone-" + phone
        } else {
            self.id = UUID().uuidString
        }
    }

    var isOwner: Bool {
        participant.role == .owner
    }

    var displayName: String {
        if let components = participant.userIdentity.nameComponents {
            let formatted = ShareParticipantItem.nameFormatter.string(from: components)
            if formatted.isEmpty == false {
                return formatted
            }
        }
        if participant.role == .owner,
           let ownerFallbackName,
           ownerFallbackName.isEmpty == false {
            return ownerFallbackName
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress {
            return email
        }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber {
            return phone
        }
        return ShareStrings.unknownParticipant
    }

    var roleDescription: String {
        isOwner ? ShareStrings.ownerRole : ShareStrings.invitedRole
    }

    var permissionDescription: String {
        switch participant.permission {
        case .readOnly:
            return ShareStrings.permissionReadOnly
        case .readWrite:
            return ShareStrings.permissionReadWrite
        default:
            return ShareStrings.permissionUnknown
        }
    }

    var permission: CKShare.ParticipantPermission {
        participant.permission
    }

    static func sortComparator(lhs: ShareParticipantItem, rhs: ShareParticipantItem) -> Bool {
        if lhs.isOwner { return true }
        if rhs.isOwner { return false }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static let nameFormatter: PersonNameComponentsFormatter = {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter
    }()

    static func == (lhs: ShareParticipantItem, rhs: ShareParticipantItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Views

private struct ShareParticipantRow: View {
    let item: ShareParticipantItem
    let isProcessing: Bool
    let profileID: UUID
    let onChangePermission: (CKShare.ParticipantPermission) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.body)
                Text(item.roleDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            PermissionBadge(title: item.permissionDescription)
            if item.isOwner == false {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Menu {
                        if item.permission != .readWrite {
                            Button(ShareStrings.makeReadWrite) {
                                onChangePermission(.readWrite)
                            }
                            .phCaptureTap(
                                event: "shareData_makeReadWrite_button",
                                properties: [
                                    "profile_id": profileID.uuidString,
                                    "participant_id": item.id
                                ]
                            )
                            .postHogLabel("shareData.makeReadWrite")
                        }
                        if item.permission != .readOnly {
                            Button(ShareStrings.makeReadOnly) {
                                onChangePermission(.readOnly)
                            }
                            .phCaptureTap(
                                event: "shareData_makeReadOnly_button",
                                properties: [
                                    "profile_id": profileID.uuidString,
                                    "participant_id": item.id
                                ]
                            )
                            .postHogLabel("shareData.makeReadOnly")
                        }
                        Divider()
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Text(ShareStrings.removeParticipantAction)
                        }
                        .phCaptureTap(
                            event: "shareData_removeParticipant_button",
                            properties: [
                                "profile_id": profileID.uuidString,
                                "participant_id": item.id
                            ]
                        )
                        .postHogLabel("shareData.removeParticipant")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .accessibilityLabel(ShareStrings.manageParticipantMenu)
                    }
                    .postHogLabel("shareData.participantMenu")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShareProfileSheet: View {
    let payload: ShareSheetPayload
    let container: CKContainer
    let onDidSaveShare: () -> Void
    let onDidStopSharing: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ProfileAvatarView(imageData: payload.thumbnailData, size: 88)
                Text(payload.displayName ?? ShareStrings.unnamedProfileTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            Divider()

            SharingUI(
                share: payload.share,
                container: container,
                itemTitle: payload.displayName,
                thumbnailData: payload.thumbnailData,
                onDidSaveShare: onDidSaveShare,
                onDidStopSharing: onDidStopSharing,
                showsItemPreview: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

private struct ManageShareButtonLabel: View {
    let title: String
    let isLoading: Bool

    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
            Text(title)
                .fontWeight(.semibold)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct StopSharingButtonLabel: View {
    let isLoading: Bool

    var body: some View {
        HStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            Text(ShareStrings.stopSharingButton)
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Strings

private enum ShareStrings {
    static let shareProfileButton = String(
        localized: "shareData.sharing.shareProfileButton",
        defaultValue: "Share profile"
    )
    static let manageShareButton = String(
        localized: "shareData.sharing.manageButton",
        defaultValue: "Manage sharing"
    )
    static let participantsSectionTitle = String(
        localized: "shareData.sharing.participantsSectionTitle",
        defaultValue: "Participants"
    )
    static let notSharedMessage = String(
        localized: "shareData.sharing.notSharedMessage",
        defaultValue: "This profile isn't shared yet. Tap Share profile to invite someone."
    )
    static let noParticipantsMessage = String(
        localized: "shareData.sharing.noParticipantsMessage",
        defaultValue: "Only you can access this profile right now."
    )
    static let ownerRole = String(
        localized: "shareData.sharing.ownerRole",
        defaultValue: "Owner"
    )
    static let invitedRole = String(
        localized: "shareData.sharing.invitedRole",
        defaultValue: "Invited"
    )
    static let permissionReadOnly = String(
        localized: "shareData.sharing.permissionReadOnly",
        defaultValue: "Read-Only"
    )
    static let permissionReadWrite = String(
        localized: "shareData.sharing.permissionReadWrite",
        defaultValue: "Read-Write"
    )
    static let permissionUnknown = String(
        localized: "shareData.sharing.permissionUnknown",
        defaultValue: "Unknown"
    )
    static let unknownParticipant = String(
        localized: "shareData.sharing.unknownParticipant",
        defaultValue: "Unknown participant"
    )
    static let unnamedProfileTitle = String(
        localized: "shareData.sharing.unnamedProfileTitle",
        defaultValue: "Profile"
    )
    static let makeReadOnly = String(
        localized: "shareData.sharing.makeReadOnly",
        defaultValue: "Make Read-Only"
    )
    static let makeReadWrite = String(
        localized: "shareData.sharing.makeReadWrite",
        defaultValue: "Make Read-Write"
    )
    static let removeParticipantTitle = String(
        localized: "shareData.sharing.removeParticipantTitle",
        defaultValue: "Remove access?"
    )
    static let removeParticipantAction = String(
        localized: "shareData.sharing.removeParticipantAction",
        defaultValue: "Remove Access…"
    )
    static let confirmRemoveParticipantButton = String(
        localized: "shareData.sharing.confirmRemoveParticipantButton",
        defaultValue: "Remove Access"
    )
    static func removeParticipantMessage(_ name: String) -> String {
        let format = String(
            localized: "shareData.sharing.removeParticipantMessage",
            defaultValue: "Remove %@'s access to this profile?"
        )
        return String(format: format, locale: .current, name)
    }
    static let manageParticipantMenu = String(
        localized: "shareData.sharing.manageParticipantMenu",
        defaultValue: "Manage participant"
    )
    static let stopSharingButton = String(
        localized: "shareData.sharing.stopSharingButton",
        defaultValue: "Stop sharing…"
    )
    static let stopSharingFooter = String(
        localized: "shareData.sharing.stopSharingFooter",
        defaultValue: "Stop sharing to revoke access for everyone."
    )
    static let stopSharingConfirmTitle = String(
        localized: "shareData.sharing.stopSharingConfirmTitle",
        defaultValue: "Stop sharing this profile?"
    )
    static let stopSharingMessage = String(
        localized: "shareData.sharing.stopSharingMessage",
        defaultValue: "All participants will immediately lose access."
    )
    static let errorTitle = String(
        localized: "shareData.sharing.errorTitle",
        defaultValue: "Sharing error"
    )
}

// MARK: - Notifications

private extension Notification.Name {
    static let sharedScopeNotification = Notification.Name("com.prioritybit.babynanny.sharedScopeNotification")
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ShareProfilePage(profileID: UUID())
    }
    .environmentObject(ProfileStore(initialProfiles: []))
}
