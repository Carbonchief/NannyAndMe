import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareDataView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator
    @EnvironmentObject private var authManager: SupabaseAuthManager

    @State private var isImporting = false
    @State private var lastImportSummary: ActionLogStore.MergeSummary?
    @State private var didUpdateProfile = false
    @State private var alert: ShareDataAlert?
    @State private var airDropShareItem: AirDropShareItem?
    @State private var isPreparingAirDropShare = false
    @State private var processedExternalImportID: ShareDataCoordinator.ExternalImportRequest.ID?
    @State private var supabaseShareEmail = ""
    @State private var sharePermissionSelection: SupabaseAuthManager.ProfileSharePermission = .view
    @State private var shareInvitations: [SupabaseAuthManager.ProfileShareInvitation] = []
    @State private var shareInvitationErrorMessage: String?
    @State private var shareInvitationsLoadedProfileID: UUID?
    @State private var isLoadingShareInvitations = false
    @State private var updatingShareInvitationID: UUID?
    @State private var pendingRevocation: SupabaseAuthManager.ProfileShareInvitation?
    @State private var isSharingProfile = false
    @FocusState private var isSupabaseEmailFocused: Bool
    @State private var isShowingAccountPrompt = false

    var body: some View {
        Form {
            Section(header: Text(L10n.ShareData.profileSectionTitle)) {
                let profile = profileStore.activeProfile
                let historyCount = actionStore.state(for: profile.id).history.count

                HStack(spacing: 16) {
                    ProfileAvatarView(imageData: profile.imageData,
                                      size: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.ShareData.profileName(profile.displayName))

                        Text(L10n.ShareData.logCount(historyCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            supabaseShareSection

            manualShareSection

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
        .confirmationDialog(
            L10n.ShareData.Supabase.accountPromptTitle,
            isPresented: $isShowingAccountPrompt,
            titleVisibility: .visible
        ) {
            Button(L10n.ShareData.Supabase.accountPromptConfirm) {
                shareDataCoordinator.requestAuthenticationPresentation()
            }
            Button(L10n.ShareData.Supabase.accountPromptDecline, role: .cancel) { }
        } message: {
            Text(L10n.ShareData.Supabase.accountPromptMessage)
        }
        .confirmationDialog(
            L10n.ShareData.Supabase.Invites.revokeTitle,
            item: $pendingRevocation,
            titleVisibility: .visible
        ) { invitation in
            Button(L10n.ShareData.Supabase.Invites.revokeAction, role: .destructive) {
                Task { await revokeShareInvitation(invitation) }
            }
            Button(L10n.Common.cancel, role: .cancel) { }
        } message: { invitation in
            Text(L10n.ShareData.Supabase.Invites.revokeMessage(invitation.recipientEmail))
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
            Task { await refreshShareInvitations() }
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: profileStore.activeProfile.id) { _, _ in
            Task { await refreshShareInvitations(force: true) }
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            Task { await refreshShareInvitations(force: true) }
        }
        .onChange(of: authManager.ownedProfileIdentifiers) { _, _ in
            Task { await refreshShareInvitations(force: true) }
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

    private var trimmedSupabaseEmail: String {
        supabaseShareEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canManageAutomaticSharing: Bool {
        authManager.isAuthenticated && authManager.isOwner(of: profileStore.activeProfile.id)
    }

    private var automaticShareFooter: String {
        if authManager.isAuthenticated == false {
            return L10n.ShareData.Supabase.footerSignedOut
        }
        if canManageAutomaticSharing == false {
            return L10n.ShareData.Supabase.ownerOnlyFooter
        }
        return L10n.ShareData.Supabase.footerAuthenticated
    }

    private var isAutomaticShareButtonDisabled: Bool {
        trimmedSupabaseEmail.isEmpty || isSharingProfile
    }

    @ViewBuilder
    private var supabaseShareSection: some View {
        Section {
            if canManageAutomaticSharing {
                TextField(L10n.ShareData.Supabase.emailPlaceholder, text: $supabaseShareEmail)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($isSupabaseEmailFocused)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.ShareData.Supabase.permissionPickerLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker(L10n.ShareData.Supabase.permissionPickerLabel, selection: $sharePermissionSelection) {
                        ForEach(SupabaseAuthManager.ProfileSharePermission.allCases) { permission in
                            Text(permissionDisplayName(for: permission)).tag(permission)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ShareDataActionButton(
                    title: L10n.ShareData.Supabase.shareButton,
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .purple,
                    action: {
                        Task { await shareProfileWithSupabase() }
                    },
                    isLoading: isSharingProfile
                )
                .disabled(isAutomaticShareButtonDisabled)

                shareInvitationsList
            } else {
                if authManager.isAuthenticated {
                    Text(L10n.ShareData.Supabase.ownerOnlyDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.ShareData.Supabase.signedOutDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ShareDataActionButton(
                        title: L10n.ShareData.Supabase.shareButton,
                        systemImage: "person.crop.circle.badge.plus",
                        tint: .purple,
                        action: { isShowingAccountPrompt = true }
                    )
                }
            }
        } header: {
            Text(L10n.ShareData.Supabase.sectionTitle)
        } footer: {
            Text(automaticShareFooter)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var manualShareSection: some View {
        Section {
            ShareDataActionButton(
                title: L10n.ShareData.AirDrop.shareButton,
                systemImage: "airplane.circle",
                tint: .indigo,
                action: startAirDropShare,
                isLoading: isPreparingAirDropShare
            )
            .disabled(isPreparingAirDropShare)

            ShareDataActionButton(
                title: L10n.ShareData.importButton,
                systemImage: "square.and.arrow.down",
                tint: .mint,
                action: { isImporting = true }
            )
        } header: {
            Text(L10n.ShareData.AirDrop.sectionTitle)
        } footer: {
            manualShareFooter
        }
    }

    @ViewBuilder
    private var shareInvitationsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.ShareData.Supabase.Invites.header)
                .font(.subheadline)
                .fontWeight(.semibold)

            if isLoadingShareInvitations {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.ShareData.Supabase.Invites.loading)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage = shareInvitationErrorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(L10n.ShareData.Supabase.Invites.retry) {
                        Task { await refreshShareInvitations(force: true) }
                    }
                    .buttonStyle(.borderless)
                }
            } else if shareInvitations.isEmpty {
                Text(L10n.ShareData.Supabase.Invites.empty)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shareInvitations) { invitation in
                    ShareInvitationRow(
                        invitation: invitation,
                        permissionLabel: permissionDisplayName(for:),
                        statusLabel: statusDisplayName(for:),
                        isUpdating: updatingShareInvitationID == invitation.id,
                        onPermissionChange: { permission in
                            Task { await handlePermissionChange(for: invitation, to: permission) }
                        },
                        onRevoke: {
                            pendingRevocation = invitation
                        }
                    )
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var manualShareFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.ShareData.AirDrop.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)

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

    private func permissionDisplayName(for permission: SupabaseAuthManager.ProfileSharePermission) -> String {
        switch permission {
        case .view:
            return L10n.ShareData.Supabase.Permission.view
        case .edit:
            return L10n.ShareData.Supabase.Permission.edit
        }
    }

    private func statusDisplayName(for status: SupabaseAuthManager.ProfileShareStatus) -> String {
        switch status {
        case .pending:
            return L10n.ShareData.Supabase.Invites.statusPending
        case .accepted:
            return L10n.ShareData.Supabase.Invites.statusAccepted
        case .revoked:
            return L10n.ShareData.Supabase.Invites.statusRevoked
        case .rejected:
            return L10n.ShareData.Supabase.Invites.statusRejected
        }
    }

    private func refreshShareInvitations(force: Bool = false) async {
        guard canManageAutomaticSharing else {
            await MainActor.run {
                shareInvitations = []
                shareInvitationErrorMessage = nil
                shareInvitationsLoadedProfileID = nil
                isLoadingShareInvitations = false
            }
            return
        }

        let profileID = profileStore.activeProfile.id
        if !force,
           shareInvitationsLoadedProfileID == profileID,
           shareInvitationErrorMessage == nil {
            return
        }

        shareInvitationsLoadedProfileID = profileID
        await loadShareInvitations(profileID: profileID)
    }

    private func loadShareInvitations(profileID: UUID) async {
        await MainActor.run {
            isLoadingShareInvitations = true
            shareInvitationErrorMessage = nil
        }

        let result = await authManager.fetchShareInvitations(for: profileID)

        await MainActor.run {
            isLoadingShareInvitations = false
            switch result {
            case .success(let invitations):
                shareInvitations = invitations
                shareInvitationErrorMessage = nil
            case .failure(let message):
                shareInvitationErrorMessage = message
            }
        }
    }

    private func handlePermissionChange(
        for invitation: SupabaseAuthManager.ProfileShareInvitation,
        to permission: SupabaseAuthManager.ProfileSharePermission
    ) async {
        guard invitation.permission != permission else { return }

        await MainActor.run {
            updatingShareInvitationID = invitation.id
        }

        let result = await authManager.updateShareInvitation(
            invitation.id,
            profileID: invitation.profileID,
            permission: permission
        )

        await MainActor.run {
            updatingShareInvitationID = nil
        }

        switch result {
        case .success:
            await refreshShareInvitations(force: true)
        case .failure(let message):
            await MainActor.run {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Supabase.failureTitle,
                    message: message
                )
            }
        }
    }

    private func revokeShareInvitation(_ invitation: SupabaseAuthManager.ProfileShareInvitation) async {
        await MainActor.run {
            pendingRevocation = nil
            updatingShareInvitationID = invitation.id
        }

        let result = await authManager.revokeShareInvitation(
            invitation.id,
            profileID: invitation.profileID
        )

        await MainActor.run {
            updatingShareInvitationID = nil
        }

        switch result {
        case .success:
            await refreshShareInvitations(force: true)
        case .failure(let message):
            await MainActor.run {
                alert = ShareDataAlert(
                    title: L10n.ShareData.Supabase.failureTitle,
                    message: message
                )
            }
        }
    }

    @MainActor
    private func shareProfileWithSupabase() async {
        guard !isSharingProfile else { return }

        let email = trimmedSupabaseEmail

        guard email.isEmpty == false else {
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.invalidEmailTitle,
                message: L10n.ShareData.Supabase.invalidEmailMessage
            )
            return
        }

        isSharingProfile = true
        defer { isSharingProfile = false }

        let profileID = profileStore.activeProfile.id
        let permission = sharePermissionSelection
        let result = await authManager.shareBabyProfile(
            profileID: profileID,
            recipientEmail: email,
            permission: permission
        )

        switch result {
        case .success:
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.successTitle,
                message: L10n.ShareData.Supabase.successMessage(email)
            )
            supabaseShareEmail = ""
            isSupabaseEmailFocused = false
            await refreshShareInvitations(force: true)
        case .recipientNotFound:
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.recipientMissingTitle,
                message: L10n.ShareData.Supabase.recipientMissingMessage(email)
            )
        case .alreadyShared:
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.alreadySharedTitle,
                message: L10n.ShareData.Supabase.alreadySharedMessage(email)
            )
        case .notOwner:
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.failureTitle,
                message: L10n.ShareData.Supabase.ownerRequired
            )
        case .failure(let message):
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.failureTitle,
                message: message
            )
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

private enum AirDropShareOutcome: Sendable {
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
            Task { @MainActor in
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

private struct ShareInvitationRow: View {
    let invitation: SupabaseAuthManager.ProfileShareInvitation
    let permissionLabel: (SupabaseAuthManager.ProfileSharePermission) -> String
    let statusLabel: (SupabaseAuthManager.ProfileShareStatus) -> String
    let isUpdating: Bool
    let onPermissionChange: (SupabaseAuthManager.ProfileSharePermission) -> Void
    let onRevoke: () -> Void

    @State private var selectedPermission: SupabaseAuthManager.ProfileSharePermission

    init(invitation: SupabaseAuthManager.ProfileShareInvitation,
         permissionLabel: @escaping (SupabaseAuthManager.ProfileSharePermission) -> String,
         statusLabel: @escaping (SupabaseAuthManager.ProfileShareStatus) -> String,
         isUpdating: Bool,
         onPermissionChange: @escaping (SupabaseAuthManager.ProfileSharePermission) -> Void,
         onRevoke: @escaping () -> Void) {
        self.invitation = invitation
        self.permissionLabel = permissionLabel
        self.statusLabel = statusLabel
        self.isUpdating = isUpdating
        self.onPermissionChange = onPermissionChange
        self.onRevoke = onRevoke
        _selectedPermission = State(initialValue: invitation.permission)
    }

    private var canModify: Bool {
        invitation.status != .revoked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.recipientEmail)
                        .fontWeight(.semibold)
                    Text(statusLabel(invitation.status))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isUpdating {
                    ProgressView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ShareData.Supabase.permissionPickerLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedPermission) {
                    ForEach(SupabaseAuthManager.ProfileSharePermission.allCases) { permission in
                        Text(permissionLabel(permission)).tag(permission)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!canModify || isUpdating)
            }

            if canModify {
                Button(L10n.ShareData.Supabase.Invites.revokeButton, role: .destructive) {
                    onRevoke()
                }
                .disabled(isUpdating)
            }
        }
        .padding(.vertical, 6)
        .onChange(of: invitation.permission) { _, newValue in
            selectedPermission = newValue
        }
        .onChange(of: selectedPermission) { _, newValue in
            guard newValue != invitation.permission, canModify, isUpdating == false else { return }
            onPermissionChange(newValue)
        }
    }
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
            .environmentObject(profileStore)
            .environmentObject(actionStore)
            .environmentObject(ShareDataCoordinator())
            .environmentObject(SupabaseAuthManager())
    }
}
