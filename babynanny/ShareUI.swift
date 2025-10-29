import CloudKit
import SwiftUI

struct ShareProfileSection: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var sharingCoordinator: SharingCoordinator

    @State private var isPresentingShareController = false
    @State private var isProcessingShare = false
    @State private var presentedError: SharingCoordinator.SharingError?

    private var profileID: UUID { profileStore.activeProfile.id }

    var body: some View {
        Section {
            shareButton
            shareStatus
            participantList
            managementActions
        } header: {
            Text(L10n.ShareUI.sectionTitle)
        } footer: {
            Text(L10n.ShareUI.sectionFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text(L10n.ShareUI.errorTitle), message: Text(error.message), dismissButton: .default(Text(L10n.Common.done)))
        }
        .sheet(isPresented: $isPresentingShareController, onDismiss: dismissShareSheet) {
            if let controller = sharingCoordinator.activeShareController {
                CloudSharingControllerRepresentable(controller: controller)
            }
        }
        .onChange(of: sharingCoordinator.isPresentingShareSheet) { _, isPresented in
            isPresentingShareController = isPresented
        }
        .onChange(of: sharingCoordinator.activeShareController) { _, controller in
            if controller == nil {
                isPresentingShareController = false
            }
        }
        .onChange(of: sharingCoordinator.sharingError) { _, newValue in
            presentedError = newValue
            isProcessingShare = false
            if newValue != nil {
                sharingCoordinator.sharingError = nil
            }
        }
    }

    private var shareButton: some View {
        Button {
            guard isProcessingShare == false else { return }
            isProcessingShare = true
            Task {
                await sharingCoordinator.startSharing(profileID: profileID)
                isProcessingShare = false
                if sharingCoordinator.isPresentingShareSheet {
                    isPresentingShareController = true
                }
            }
        } label: {
            Label(L10n.ShareUI.shareButtonTitle, systemImage: "person.2.badge.plus")
        }
        .postHogLabel("sharing_start_button_shareData")
        .disabled(isProcessingShare)
    }

    private var shareStatus: some View {
        Text(shareStatusText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var shareStatusText: String {
        guard let context = sharingCoordinator.shareContext(for: profileID) else {
            return L10n.ShareUI.notSharedDescription
        }
        return context.isOwner ? L10n.ShareUI.ownerStatus : L10n.ShareUI.participantStatus
    }

    @ViewBuilder
    private var participantList: some View {
        if let context = sharingCoordinator.shareContext(for: profileID), context.participants.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.ShareUI.participantHeader)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(Array(context.participants.enumerated()), id: \.offset) { _, participant in
                    let removeAction: (() -> Void)?
                    if context.isOwner, let share = context.share, participant != share.owner {
                        removeAction = {
                            Task { await sharingCoordinator.removeParticipant(participant, from: profileID) }
                        }
                    } else {
                        removeAction = nil
                    }
                    ParticipantRow(participant: participant, onRemove: removeAction)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var managementActions: some View {
        if let context = sharingCoordinator.shareContext(for: profileID) {
            if context.isOwner {
                Button(role: .destructive) {
                    Task { await sharingCoordinator.stopSharing(profileID: profileID) }
                } label: {
                    Label(L10n.ShareUI.stopSharingButton, systemImage: "person.2.slash")
                }
                .postHogLabel("sharing_stop_button_shareData")
            } else {
                Button(role: .destructive) {
                    Task { await sharingCoordinator.leaveShare(for: profileID) }
                } label: {
                    Label(L10n.ShareUI.leaveShareButton, systemImage: "rectangle.portrait.and.arrow.right")
                }
                .postHogLabel("sharing_leave_button_shareData")
            }
        }
    }

    private func dismissShareSheet() {
        sharingCoordinator.activeShareController = nil
        sharingCoordinator.isPresentingShareSheet = false
    }
}

private struct ParticipantRow: View {
    let participant: CKShare.Participant
    let onRemove: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                Text(detailDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: participant.permission == .readWrite ? "square.and.pencil" : "eye")
                .foregroundStyle(participant.permission == .readWrite ? Color.accentColor : Color.secondary)
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .postHogLabel("sharing_removeParticipant_button_shareData")
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        if let components = participant.userIdentity.nameComponents {
            return components.formatted(.name(style: .medium))
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress {
            return email
        }
        return L10n.ShareUI.unknownParticipant
    }

    private var detailDescription: String {
        let role: String
        switch participant.role {
        case .owner:
            role = L10n.ShareUI.ownerRole
        case .privateUser:
            role = L10n.ShareUI.memberRole
        case .publicUser:
            role = L10n.ShareUI.publicRole
        @unknown default:
            role = L10n.ShareUI.memberRole
        }

        let permission: String
        switch participant.permission {
        case .readOnly:
            permission = L10n.ShareUI.readOnlyPermission
        case .readWrite:
            permission = L10n.ShareUI.readWritePermission
        case .unknown:
            permission = L10n.ShareUI.unknownPermission
        @unknown default:
            permission = L10n.ShareUI.unknownPermission
        }

        return "\(role) · \(permission)"
    }
}

private struct CloudSharingControllerRepresentable: UIViewControllerRepresentable {
    let controller: UICloudSharingController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
}
