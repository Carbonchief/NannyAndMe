import CloudKit
import SwiftData
import SwiftUI
import UIKit

struct ShareProfilePage: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appDataStack: AppDataStack
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @StateObject private var sharingCoordinator = SharingCoordinator()

    @State private var sharePresentation: CloudSharePresentation?
    @State private var alert: ShareProfileAlert?
    @State private var isPerformingAction = false
    @State private var lastStatusMessage: String?

    var body: some View {
        List {
            profileSummarySection
            shareStatusSection
            participantsSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.ShareData.CloudKit.manageTitle)
        .toolbar { refreshToolbarItem }
        .sheet(item: $sharePresentation) { presentation in
            CloudSharingControllerView(presentation: presentation)
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text(L10n.Common.done)))
        }
        .overlay(statusOverlay)
        .task {
            sharingCoordinator.configureIfNeeded(with: appDataStack)
            await refreshShareState()
        }
        .onChange(of: profileStore.activeProfileID) { _, _ in
            Task { await refreshShareState() }
        }
    }
}

private extension ShareProfilePage {
    var profileSummarySection: some View {
        Section(header: Text(L10n.ShareData.profileSectionTitle)) {
            let profile = profileStore.activeProfile
            HStack(spacing: 16) {
                ProfileAvatarView(imageData: profile.imageData, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.ShareData.profileName(profile.displayName))
                    Text(profile.birthDate, style: .date)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var shareStatusSection: some View {
        Section(header: Text(L10n.ShareData.CloudKit.statusSectionTitle)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusHeadline)
                    .font(.headline)
                if let message = lastStatusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var participantsSection: some View {
        Section(header: Text(L10n.ShareData.CloudKit.participantsTitle)) {
            if sharingCoordinator.participants.isEmpty {
                Text(L10n.ShareData.CloudKit.noParticipants)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sharingCoordinator.participants) { participant in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(participant.displayName)
                                .font(.headline)
                            Text(participantDescription(for: participant))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if participant.role != .owner {
                            Button {
                                removeParticipant(participant.participant)
                            } label: {
                                Label(L10n.ShareData.CloudKit.removeParticipant, systemImage: "person.crop.circle.badge.minus")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.ShareData.CloudKit.removeParticipant)
                            .postHogLabel("shareData_removeParticipant_button_shareProfilePage")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    var actionsSection: some View {
        Section(header: Text(L10n.ShareData.CloudKit.actionsTitle)) {
            Button(action: presentShareSheet) {
                Label(L10n.ShareData.CloudKit.inviteButton, systemImage: "person.crop.circle.badge.plus")
            }
            .postHogLabel("shareData_invite_button_shareProfilePage")
            .disabled(isPerformingAction)

            Button(action: copyShareLink) {
                Label(L10n.ShareData.CloudKit.copyLink, systemImage: "link")
            }
            .postHogLabel("shareData_copyLink_button_shareProfilePage")
            .disabled(isPerformingAction || sharingCoordinator.activeShare == nil)

            Button(role: .destructive, action: stopSharing) {
                Label(L10n.ShareData.CloudKit.stopSharing, systemImage: "stop.circle")
            }
            .postHogLabel("shareData_stopSharing_button_shareProfilePage")
            .disabled(isPerformingAction || sharingCoordinator.activeShare == nil)
        }
    }

    var statusOverlay: some View {
        Group {
            switch sharingCoordinator.status {
            case .idle:
                EmptyView()
            case .loading:
                overlayContainer {
                    ProgressView(L10n.ShareData.CloudKit.syncInProgress)
                }
            case let .error(message):
                overlayContainer {
                    VStack(spacing: 8) {
                        Text(L10n.ShareData.CloudKit.syncError)
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    var refreshToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { Task { await refreshShareState() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .postHogLabel("shareData_refresh_button_shareProfilePage")
        }
    }

    var statusHeadline: String {
        if sharingCoordinator.activeShare != nil {
            return L10n.ShareData.CloudKit.shareActive
        }
        return L10n.ShareData.CloudKit.shareInactive
    }

    func participantDescription(for participant: SharingCoordinator.ParticipantSummary) -> String {
        switch participant.role {
        case .owner:
            return L10n.ShareData.CloudKit.ownerRole
        default:
            switch participant.permission {
            case .readWrite:
                return L10n.ShareData.CloudKit.editRole
            case .readOnly:
                return L10n.ShareData.CloudKit.viewRole
            default:
                return L10n.ShareData.CloudKit.pendingRole
            }
        }
    }

    @MainActor
    func presentShareSheet() {
        guard isPerformingAction == false else { return }
        guard let model = try? fetchProfileModel() else {
            alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                      message: L10n.ShareData.Alert.cloudShareFailureMessage(""))
            return
        }
        isPerformingAction = true
        actionStore.synchronizeProfileMetadata([profileStore.activeProfile])

        Task { @MainActor in
            do {
                let (share, container) = try await sharingCoordinator.createShare(for: model)
                sharePresentation = CloudSharePresentation(share: share, container: container)
                lastStatusMessage = L10n.ShareData.CloudKit.lastSyncedJustNow
            } catch {
                alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                          message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription))
            }
            isPerformingAction = false
        }
    }

    @MainActor
    func copyShareLink() {
        guard isPerformingAction == false else { return }
        guard let model = try? fetchProfileModel() else { return }
        isPerformingAction = true

        Task { @MainActor in
            do {
                if sharingCoordinator.activeShare == nil {
                    _ = try await sharingCoordinator.createShare(for: model)
                }
                guard let share = sharingCoordinator.activeShare, let url = share.url else {
                    throw ShareProfileError.missingShare
                }
                UIPasteboard.general.url = url
                lastStatusMessage = L10n.ShareData.CloudKit.linkCopied
            } catch {
                alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                          message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription))
            }
            isPerformingAction = false
        }
    }

    @MainActor
    func stopSharing() {
        guard isPerformingAction == false else { return }
        guard let model = try? fetchProfileModel() else { return }
        isPerformingAction = true

        Task { @MainActor in
            do {
                try await sharingCoordinator.stopSharing(profile: model)
                lastStatusMessage = L10n.ShareData.CloudKit.shareStopped
            } catch {
                alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                          message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription))
            }
            isPerformingAction = false
        }
    }

    @MainActor
    func removeParticipant(_ participant: CKShare.Participant) {
        guard isPerformingAction == false else { return }
        guard let model = try? fetchProfileModel() else { return }
        isPerformingAction = true

        Task { @MainActor in
            do {
                try await sharingCoordinator.remove(participant: participant, from: model)
                lastStatusMessage = L10n.ShareData.CloudKit.participantRemoved
            } catch {
                alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                          message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription))
            }
            isPerformingAction = false
        }
    }

    @MainActor
    func refreshShareState() async {
        guard let model = try? fetchProfileModel() else { return }
        isPerformingAction = true
        do {
            try await sharingCoordinator.refreshParticipants(for: model)
            lastStatusMessage = L10n.ShareData.CloudKit.statusRefreshed
        } catch {
            alert = ShareProfileAlert(title: L10n.ShareData.Alert.cloudShareFailureTitle,
                                      message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription))
        }
        isPerformingAction = false
    }

    @MainActor
    func fetchProfileModel() throws -> ProfileActionStateModel {
        guard let activeID = profileStore.activeProfileID else {
            throw ShareProfileError.missingShare
        }

        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == activeID
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.ensureActionOwnership()
            return existing
        }
        throw ShareProfileError.missingShare
    }

    func overlayContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 8)
    }
}

private struct ShareProfileAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ShareProfileError: LocalizedError {
    case missingShare

    var errorDescription: String? {
        switch self {
        case .missingShare:
            return L10n.ShareData.Error.missingShareableProfile
        }
    }
}

private struct CloudSharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

@available(iOS 17.0, *)
private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let presentation: CloudSharePresentation

    func makeUIViewController(context: Context) -> CloudSharingController {
        CloudSharingController(share: presentation.share, container: presentation.container)
    }

    func updateUIViewController(_ uiViewController: CloudSharingController, context: Context) {}
}

private actor PreviewReminderScheduler: ReminderScheduling {
    func ensureAuthorization() async -> Bool { true }

    func refreshReminders(for profiles: [ChildProfile],
                          actionStates: [UUID: ProfileActionState]) async {}

    func upcomingReminders(for profiles: [ChildProfile],
                           actionStates: [UUID: ProfileActionState],
                           reference: Date) async -> [ReminderOverview] { [] }

    func schedulePreviewReminder(for profile: ChildProfile,
                                 category: BabyActionCategory,
                                 delay: TimeInterval) async -> Bool { true }
}

#Preview("Share Profile Page") {
    ShareProfilePreview()
}

private struct ShareProfilePreview: View {
    private let container: ModelContainer
    @StateObject private var dataStack: AppDataStack
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()

    init() {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let stack = AppDataStack(modelContainer: container)
        let scheduler = PreviewReminderScheduler()

        let childProfile = ChildProfile(
            name: "Avery",
            birthDate: Date(timeIntervalSince1970: 1_689_868_800)
        )

        let profileModel = ProfileActionStateModel(
            profileID: childProfile.id,
            name: childProfile.name,
            birthDate: childProfile.birthDate
        )

        container.mainContext.insert(profileModel)
        container.mainContext.insert(BabyActionModel(
            category: .feeding,
            startDate: Date().addingTimeInterval(-1_800),
            endDate: Date(),
            updatedAt: Date(),
            profile: profileModel
        ))
        try? container.mainContext.save()

        let profileStore = ProfileStore(
            initialProfiles: [childProfile],
            activeProfileID: childProfile.id,
            reminderScheduler: scheduler
        )
        let actionStore = ActionLogStore(
            modelContext: container.mainContext,
            reminderScheduler: scheduler,
            dataStack: stack
        )
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)

        self.container = container
        _dataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
    }

    var body: some View {
        NavigationStack {
            ShareProfilePage()
        }
        .environmentObject(dataStack)
        .environmentObject(profileStore)
        .environmentObject(actionStore)
        .environmentObject(shareDataCoordinator)
        .modelContainer(container)
    }
}
