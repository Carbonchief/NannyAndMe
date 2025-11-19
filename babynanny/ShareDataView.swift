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
    @State private var isSharingProfile = false
    @State private var sharePermissionSelection: ProfileSharePermission = .view
    @State private var shareInvitations: [SupabaseAuthManager.ProfileShareEntry] = []
    @State private var isLoadingShareInvitations = false
    @State private var shareInvitationsError: String?
    @State private var isActiveProfileOwner: Bool?
    @State private var updatingShareIDs: Set<UUID> = []
    @State private var revokingShareIDs: Set<UUID> = []
    @State private var reinvitingShareIDs: Set<UUID> = []
    @FocusState private var isSupabaseEmailFocused: Bool
    @State private var isShowingAccountPrompt = false
    @State private var qrCodePayload: ShareDataQRCodePayload?
    @State private var isShowingQRScanner = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if authManager.isAuthenticated, let email = authManager.currentUserEmail {
                    Button {
                        qrCodePayload = ShareDataQRCodePayload(email: email)
                    } label: {
                        Image(systemName: "qrcode")
                    }
                    .accessibilityLabel(L10n.ShareData.QRCode.buttonLabel)
                }
            }
        }
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
        .sheet(item: $qrCodePayload) { payload in
            ShareDataQRCodeView(email: payload.email)
        }
        .sheet(isPresented: $isShowingQRScanner) {
            ShareDataQRScannerView { value in
                Task { await handleScannedQRCodeValue(value) }
            }
        }
        .onAppear {
            processPendingExternalImportIfNeeded()
            Task { await refreshShareInvitations(force: true) }
        }
        .onChange(of: shareDataCoordinator.externalImportRequest) { _, _ in
            processPendingExternalImportIfNeeded()
        }
        .onChange(of: profileStore.activeProfileID) { _, _ in
            Task { await refreshShareInvitations(force: true) }
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
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

    private var automaticShareFooter: String {
        if authManager.isAuthenticated == false {
            return L10n.ShareData.Supabase.footerSignedOut
        }
        if isActiveProfileOwner == false {
            return L10n.ShareData.Supabase.ownerOnlyFooter
        }
        return L10n.ShareData.Supabase.footerAuthenticated
    }

    private var isAutomaticShareButtonDisabled: Bool {
        if isSharingProfile { return true }
        guard authManager.isAuthenticated, isActiveProfileOwner == true else { return true }
        return trimmedSupabaseEmail.isEmpty
    }

    @ViewBuilder
    private var supabaseShareSection: some View {
        Section {
            if authManager.isAuthenticated == false {
                Text(L10n.ShareData.Supabase.signedOutDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ShareDataActionButton(
                    title: L10n.ShareData.Supabase.shareButton,
                    systemImage: "person.crop.circle.badge.plus",
                    tint: .purple,
                    action: { isShowingAccountPrompt = true }
                )
            } else if let error = shareInvitationsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.ShareData.Supabase.Invitations.loadFailed)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(L10n.Common.retry) {
                        Task { await refreshShareInvitations(force: true) }
                    }
                    .buttonStyle(.bordered)
                }
            } else if isActiveProfileOwner == nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.Splash.loading)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if isActiveProfileOwner == false {
                Text(L10n.ShareData.Supabase.ownerOnlyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.ShareData.Supabase.permissionLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker(L10n.ShareData.Supabase.permissionLabel, selection: $sharePermissionSelection) {
                        Text(L10n.ShareData.Supabase.permissionView)
                            .tag(ProfileSharePermission.view)
                        Text(L10n.ShareData.Supabase.permissionEdit)
                            .tag(ProfileSharePermission.edit)
                    }
                    .pickerStyle(.segmented)
                }

                TextField(L10n.ShareData.Supabase.emailPlaceholder, text: $supabaseShareEmail)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($isSupabaseEmailFocused)

                HStack(alignment: .top, spacing: 8) {
                    ShareDataActionButton(
                        title: L10n.ShareData.Supabase.shareButton,
                        systemImage: "person.crop.circle.badge.plus",
                        tint: .purple,
                        action: {
                            if authManager.isAuthenticated {
                                Task { await shareProfileWithSupabase() }
                            } else {
                                isShowingAccountPrompt = true
                            }
                        },
                        isLoading: isSharingProfile
                    )
                    .disabled(isAutomaticShareButtonDisabled)

                    Button {
                        isShowingQRScanner = true
                    } label: {
                        Label(L10n.ShareData.QRScanner.button, systemImage: "qrcode.viewfinder")
                            .labelStyle(.iconOnly)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .controlSize(.large)
                    .disabled(isAutomaticShareButtonDisabled)
                    .accessibilityLabel(L10n.ShareData.QRScanner.button)
                }

                shareInvitationsList
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
            HStack {
                Text(L10n.ShareData.Supabase.Invitations.title)
                    .font(.headline)
                Spacer()
                if isLoadingShareInvitations {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }

            if shareInvitations.isEmpty {
                if !isLoadingShareInvitations {
                    Text(L10n.ShareData.Supabase.Invitations.empty)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(shareInvitations) { entry in
                        shareInvitationRow(entry)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func shareInvitationRow(_ entry: SupabaseAuthManager.ProfileShareEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.email ?? L10n.ShareData.Supabase.Invitations.unknownEmail)
                    .font(.headline)
                Spacer()
                statusBadge(for: entry.status)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.ShareData.Supabase.permissionLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker(L10n.ShareData.Supabase.permissionLabel, selection: permissionBinding(for: entry)) {
                    Text(L10n.ShareData.Supabase.permissionView)
                        .tag(ProfileSharePermission.view)
                    Text(L10n.ShareData.Supabase.permissionEdit)
                        .tag(ProfileSharePermission.edit)
                }
                .pickerStyle(.segmented)
                .disabled(shouldDisablePermissionControls(for: entry))
            }

            if entry.status == .revoked {
                Button {
                    Task { await reinviteShare(entry) }
                } label: {
                    Text(L10n.ShareData.Supabase.Invitations.reinviteButton)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(shouldDisableReinvite(for: entry))
            } else {
                Button(role: .destructive) {
                    Task { await revokeShare(entry) }
                } label: {
                    Text(L10n.ShareData.Supabase.Invitations.revokeButton)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(shouldDisableRevoke(for: entry))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        let result = await authManager.shareBabyProfile(
            profileID: profileID,
            recipientEmail: email,
            permission: sharePermissionSelection
        )

        switch result {
        case .success:
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.successTitle,
                message: L10n.ShareData.Supabase.successMessage(email)
            )
            supabaseShareEmail = ""
            isSupabaseEmailFocused = false
            await refreshShareInvitations()
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
            isActiveProfileOwner = false
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.failureTitle,
                message: L10n.ShareData.Supabase.ownerOnlyDescription
            )
        case .failure(let message):
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.failureTitle,
                message: message
            )
        }
    }

    private func permissionBinding(for entry: SupabaseAuthManager.ProfileShareEntry) -> Binding<ProfileSharePermission> {
        Binding(
            get: {
                shareInvitations.first(where: { $0.id == entry.id })?.permission ?? entry.permission
            },
            set: { newValue in
                guard newValue != shareInvitations.first(where: { $0.id == entry.id })?.permission else { return }
                Task { await updateSharePermission(for: entry.id, permission: newValue) }
            }
        )
    }

    private func shouldDisablePermissionControls(for entry: SupabaseAuthManager.ProfileShareEntry) -> Bool {
        updatingShareIDs.contains(entry.id)
            || revokingShareIDs.contains(entry.id)
            || reinvitingShareIDs.contains(entry.id)
            || entry.status == .revoked
            || isLoadingShareInvitations
    }

    private func shouldDisableRevoke(for entry: SupabaseAuthManager.ProfileShareEntry) -> Bool {
        revokingShareIDs.contains(entry.id)
            || reinvitingShareIDs.contains(entry.id)
            || entry.status == .revoked
            || isLoadingShareInvitations
    }

    private func shouldDisableReinvite(for entry: SupabaseAuthManager.ProfileShareEntry) -> Bool {
        reinvitingShareIDs.contains(entry.id)
            || entry.status != .revoked
            || isLoadingShareInvitations
    }

    @ViewBuilder
    private func statusBadge(for status: ProfileShareStatus) -> some View {
        Text(statusText(for: status))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(for: status).opacity(0.15))
            .foregroundStyle(statusColor(for: status))
            .clipShape(Capsule())
    }

    private func statusText(for status: ProfileShareStatus) -> String {
        switch status {
        case .pending:
            return L10n.ShareData.Supabase.Invitations.statusPending
        case .accepted:
            return L10n.ShareData.Supabase.Invitations.statusAccepted
        case .revoked:
            return L10n.ShareData.Supabase.Invitations.statusRevoked
        case .rejected:
            return L10n.ShareData.Supabase.Invitations.statusRejected
        }
    }

    private func statusColor(for status: ProfileShareStatus) -> Color {
        switch status {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .revoked:
            return .gray
        case .rejected:
            return .red
        }
    }

    @MainActor
    private func refreshShareInvitations(force: Bool = false) async {
        guard authManager.isAuthenticated else {
            shareInvitations = []
            shareInvitationsError = nil
            isActiveProfileOwner = nil
            isLoadingShareInvitations = false
            return
        }

        guard isLoadingShareInvitations == false else { return }
        shareInvitationsError = nil
        if force {
            isActiveProfileOwner = nil
        }
        isLoadingShareInvitations = true
        defer { isLoadingShareInvitations = false }

        let profileID = profileStore.activeProfile.id
        let result = await authManager.fetchProfileShareDetails(profileID: profileID)

        switch result {
        case .success(let entries):
            shareInvitations = entries
            shareInvitationsError = nil
            isActiveProfileOwner = true
        case .notOwner:
            shareInvitations = []
            shareInvitationsError = nil
            isActiveProfileOwner = false
        case .failure(let message):
            shareInvitations = []
            shareInvitationsError = message
            isActiveProfileOwner = nil
        }
    }

    @MainActor
    private func updateSharePermission(for shareID: UUID,
                                       permission: ProfileSharePermission) async {
        guard updatingShareIDs.contains(shareID) == false else { return }
        updatingShareIDs.insert(shareID)
        defer { updatingShareIDs.remove(shareID) }

        let result = await authManager.updateProfileSharePermission(shareID: shareID, permission: permission)
        switch result {
        case .success:
            await refreshShareInvitations()
        case .failure(let error):
            alert = ShareDataAlert(title: L10n.ShareData.Supabase.failureTitle, message: error.message)
        }
    }

    @MainActor
    private func revokeShare(_ entry: SupabaseAuthManager.ProfileShareEntry) async {
        guard revokingShareIDs.contains(entry.id) == false else { return }
        revokingShareIDs.insert(entry.id)
        defer { revokingShareIDs.remove(entry.id) }

        let result = await authManager.revokeProfileShare(shareID: entry.id)
        switch result {
        case .success:
            await refreshShareInvitations()
        case .failure(let error):
            alert = ShareDataAlert(title: L10n.ShareData.Supabase.failureTitle, message: error.message)
        }
    }

    @MainActor
    private func reinviteShare(_ entry: SupabaseAuthManager.ProfileShareEntry) async {
        guard reinvitingShareIDs.contains(entry.id) == false else { return }
        reinvitingShareIDs.insert(entry.id)
        defer { reinvitingShareIDs.remove(entry.id) }

        let result = await authManager.reinviteProfileShare(shareID: entry.id)
        switch result {
        case .success:
            await refreshShareInvitations()
        case .failure(let error):
            alert = ShareDataAlert(title: L10n.ShareData.Supabase.failureTitle, message: error.message)
        }
    }

    @MainActor
    private func handleScannedQRCodeValue(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            alert = ShareDataAlert(
                title: L10n.ShareData.Supabase.failureTitle,
                message: L10n.ShareData.QRScanner.invalidPayload
            )
            return
        }

        supabaseShareEmail = trimmed
        await shareProfileWithSupabase()
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

private struct ShareDataQRCodePayload: Identifiable {
    let id = UUID()
    let email: String
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
