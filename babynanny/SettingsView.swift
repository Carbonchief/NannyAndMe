//
//  SettingsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var cloudStatusController: CloudAccountStatusController
    @EnvironmentObject private var appDataStack: AppDataStack
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var locationManager: LocationManager
#if DEBUG
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @EnvironmentObject private var syncStatusViewModel: SyncStatusViewModel
    private let cloudKitContainerIdentifier = CKConfig.containerID
#endif
    @Environment(\.openURL) private var openURL
    @AppStorage("trackActionLocations") private var trackActionLocations = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCrop: PendingCropImage?
    @State private var isProcessingPhoto = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoRequestID: UUID?
    @State private var isUpdatingReminders = false
    @State private var actionReminderSummaries: [BabyActionCategory: ProfileStore.ActionReminderSummary] = [:]
    @State private var isLoadingActionReminders = false
    @State private var loadingReminderCategories: Set<BabyActionCategory> = []
    @State private var reminderLoadTask: Task<Void, Never>?
    @State private var activeAlert: ActiveAlert?
    @State private var profilePendingDeletion: ChildProfile?
    @State private var isAddProfilePromptPresented = false

    var body: some View {
        Form {
            profilesSection
            activeProfileSection
            homeSection
            privacySection
            cloudSection
            notificationsSection
            aboutSection
#if DEBUG
            debugSection
#endif
        }
        .navigationTitle(L10n.Settings.title)
        .phScreen("settings_screen_settingsView")
        .alert(item: $activeAlert, content: makeAlert)
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: deletionConfirmationBinding,
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button(L10n.Profiles.deleteAction, role: .destructive) {
                Analytics.capture(
                    "settings_confirm_delete_profile_dialog",
                    properties: ["profile_id": profile.id.uuidString]
                )
                deleteProfile(profile)
            }
            Button(L10n.Common.cancel, role: .cancel) {
                Analytics.capture(
                    "settings_cancel_delete_profile_dialog",
                    properties: ["profile_id": profile.id.uuidString]
                )
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text(L10n.Profiles.deleteConfirmationMessage(profile.displayName))
        }
        .onAppear {
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfileID) { _, _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.remindersEnabled) { _, _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.birthDate) { _, _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.name) { _, _ in
            refreshActionReminderSummaries()
        }
        .onDisappear {
            reminderLoadTask?.cancel()
            reminderLoadTask = nil
            isLoadingActionReminders = false
            photoLoadingTask?.cancel()
            photoLoadingTask = nil
            activePhotoRequestID = nil
            selectedPhoto = nil
            isProcessingPhoto = false
        }
        .sheet(isPresented: $isAddProfilePromptPresented) {
            AddProfilePromptView(analyticsSource: "settings_addProfilePrompt") { name, imageData in
                Analytics.capture(
                    "settings_add_profile_confirm",
                    properties: [
                        "profile_count": "\(profileStore.profiles.count)",
                        "name_length": "\(name.count)",
                        "has_photo": imageData == nil ? "false" : "true"
                    ]
                )
                profileStore.addProfile(name: name, imageData: imageData)
            } onCancel: {
                Analytics.capture("settings_add_profile_cancel")
            }
        }
        .fullScreenCover(item: $pendingCrop) { crop in
            ImageCropperView(image: crop.image) {
                pendingCrop = nil
            } onCrop: { croppedImage in
                if let data = croppedImage.compressedData() {
                    profileStore.updateActiveProfile { $0.imageData = data }
                }
                pendingCrop = nil
            }
            .preferredColorScheme(.dark)
        }
    }

    private var cloudSection: some View {
        Section(header: Text(L10n.Settings.Cloud.sectionTitle)) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(L10n.Settings.Cloud.statusLabel, systemImage: "icloud")
                Spacer()
                Text(cloudStatusDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button {
                    Analytics.capture("settings_cloud_refresh_button", properties: ["status": cloudStatusController.status.analyticsValue])
                    cloudStatusController.refreshAccountStatus(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Settings.Cloud.refresh)
                .postHogLabel("settings.cloud.refresh")
            }

            if appDataStack.cloudSyncEnabled == false {
                Button {
                    Analytics.capture("settings_cloud_enable_button", properties: ["status": cloudStatusController.status.analyticsValue])
                    cloudStatusController.enableCloudSync()
                } label: {
                    Text(L10n.Settings.Cloud.enable)
                }
                .postHogLabel("settings.cloud.enable")
            }
        }
    }

    private var privacySection: some View {
        Section(header: Text(L10n.Settings.Privacy.sectionTitle)) {
            Toggle(isOn: $trackActionLocations) {
                Label(L10n.Settings.Privacy.trackActionLocations, systemImage: "location.fill")
            }
            .postHogLabel("settings.privacy.trackLocations")
            .onChange(of: trackActionLocations) { _, newValue in
                Analytics.capture(
                    "settings_toggle_track_locations",
                    properties: ["is_enabled": newValue ? "true" : "false"]
                )
                if newValue {
                    locationManager.requestPermissionIfNeeded()
                    locationManager.ensurePreciseAccuracyIfNeeded()
                }
            }

            Text(L10n.Settings.Privacy.trackActionLocationsDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if trackActionLocations,
               locationManager.authorizationStatus == .denied ||
               locationManager.authorizationStatus == .restricted {
                Button {
                    Analytics.capture("settings_open_location_settings_button")
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                } label: {
                    Label(L10n.Settings.Privacy.permissionDenied, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .postHogLabel("settings.privacy.openSystemSettings")
            }
        }
    }

    private var profilesSection: some View {
        Section(header: Text(L10n.Profiles.title)) {
            ForEach(profileStore.profiles) { profile in
                profileRow(for: profile)
            }

            Button {
                Analytics.capture(
                    "settings_add_profile_button",
                    properties: [
                        "profile_count": "\(profileStore.profiles.count)"
                    ]
                )
                isAddProfilePromptPresented = true
            } label: {
                Label(L10n.Profiles.addProfile, systemImage: "plus")
            }
            .postHogLabel("settings.profiles.add")
        }
    }

    private func profileRow(for profile: ChildProfile) -> some View {
        HStack(spacing: 16) {
            ProfileAvatarView(imageData: profile.imageData, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                Text(profile.birthDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.ageDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if profile.id == profileStore.activeProfileID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .postHogLabel("settings.profiles.select.\(profile.id.uuidString)")
        .onTapGesture {
            Analytics.capture(
                "settings_select_profile_row",
                properties: ["profile_id": profile.id.uuidString]
            )
            profileStore.setActiveProfile(profile)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                profilePendingDeletion = profile
            } label: {
                Label(L10n.Profiles.deleteAction, systemImage: "trash")
            }
            .postHogLabel("settings.profiles.delete.\(profile.id.uuidString)")
            .phCaptureTap(
                event: "settings_delete_profile_swipe",
                properties: ["profile_id": profile.id.uuidString]
            )
        }
    }

    private var activeProfileSection: some View {
        Section(header: Text(L10n.Profiles.activeProfileSection)) {
            activeProfileHeader
            processingPhotoIndicator
        }
    }

    private var cloudStatusDescription: String {
        switch cloudStatusController.status {
        case .available:
            return L10n.Settings.Cloud.statusAvailable
        case .needsAccount:
            return L10n.Settings.Cloud.statusNeedsAccount
        case .localOnly:
            return L10n.Settings.Cloud.statusLocalOnly
        case .loading:
            return L10n.Settings.Cloud.statusLoading
        }
    }

    private var activeProfileHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            profilePhotoSelector

            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.Profiles.childName, text: Binding(
                    get: { profileStore.activeProfile.name },
                    set: { newValue in
                        profileStore.updateActiveProfile { $0.name = newValue }
                    }
                ))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .postHogLabel("settings.profile.name")

                DatePicker(
                    selection: Binding(
                        get: { profileStore.activeProfile.birthDate },
                        set: { newValue in
                            profileStore.updateActiveProfile { $0.birthDate = newValue }
                        }
                    ),
                    in: Date.distantPast...Date(),
                    displayedComponents: .date
                ) {
                    Text(L10n.Profiles.birthDate)
                }
                .postHogLabel("settings.profile.birthDate")
            }
        }
    }

    private var processingPhotoIndicator: some View {
        Group {
            if isProcessingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.Profiles.photoProcessing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var profilePhotoSelector: some View {
        let activeImageData = profileStore.activeProfile.imageData

        return ZStack(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                ProfileAvatarView(imageData: activeImageData, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        if activeImageData == nil {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                                .shadow(radius: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .postHogLabel("settings.profile.photoPicker")
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Profiles.choosePhoto)
            .onChange(of: selectedPhoto) { _, newValue in
                handlePhotoSelectionChange(newValue)
            }

            if activeImageData != nil {
                Button {
                    profileStore.updateActiveProfile { $0.imageData = nil }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .postHogLabel("settings.profile.removePhoto")
                .buttonStyle(.plain)
                .phCaptureTap(
                    event: "settings_remove_profile_photo_button",
                    properties: ["profile_id": profileStore.activeProfile.id.uuidString]
                )
                .accessibilityLabel(L10n.Profiles.removePhoto)
                .padding(4)
            }
        }
    }

    private var notificationsSection: some View {
        Section(header: Text(L10n.Settings.notificationsSection)) {
            remindersToggle

            if profileStore.activeProfile.remindersEnabled {
                ForEach(BabyActionCategory.allCases) { category in
                    actionReminderRow(for: category)
                }
            } else {
                Text(L10n.Settings.nextReminderDisabled)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private var homeSection: some View {
        Section(header: Text(L10n.Settings.homeSection)) {
            Toggle(
                isOn: Binding(
                    get: { profileStore.showRecentActivityOnHome },
                    set: { profileStore.setShowRecentActivityOnHome($0) }
                )
            ) {
                Text(L10n.Settings.showRecentActivity)
            }
            .postHogLabel("settings.home.showRecentActivity")
            .onChange(of: profileStore.showRecentActivityOnHome) { _, newValue in
                Analytics.capture(
                    "settings_toggle_recent_activity_home",
                    properties: ["is_on": newValue ? "true" : "false"]
                )
            }
        }
    }

    private var remindersToggle: some View {
        Toggle(
            isOn: Binding(
                get: { profileStore.activeProfile.remindersEnabled },
                set: { newValue in
                    handleReminderToggleChange(newValue)
                }
            )
        ) {
            Text(L10n.Settings.enableReminders)
        }
        .postHogLabel("settings.reminders.enable")
        .disabled(isUpdatingReminders)
        .onChange(of: profileStore.activeProfile.remindersEnabled) { _, newValue in
            Analytics.capture(
                "settings_toggle_global_reminders",
                properties: [
                    "profile_id": profileStore.activeProfile.id.uuidString,
                    "is_on": newValue ? "true" : "false"
                ]
            )
        }
    }

    private var aboutSection: some View {
        Section(header: Text(L10n.Settings.aboutSection)) {
            HStack {
                Text(L10n.Settings.appVersion)
                Spacer()
                Text("1.0")
                    .foregroundStyle(.secondary)
            }
        }
    }

#if DEBUG
    private var debugSection: some View {
        Section(header: Text("Debug")) {
            NavigationLink {
                SyncDiagnosticsView(coordinator: syncCoordinator,
                                    statusViewModel: syncStatusViewModel,
                                    containerIdentifier: cloudKitContainerIdentifier,
                                    sharedManager: appDataStack.sharedSubscriptionManager,
                                    sharedTokenStore: appDataStack.sharedZoneTokenStore,
                                    metadataStore: appDataStack.shareMetadataStore)
            } label: {
                Label("Sync Diagnostics", systemImage: "antenna.radiowaves.left.and.right")
            }
            .postHogLabel("settings.debug.syncDiagnostics")
        }
    }
#endif

    private func handlePhotoSelectionChange(_ newValue: PhotosPickerItem?) {
        photoLoadingTask?.cancel()
        guard let newValue else { return }

        Analytics.capture(
            "settings_select_profile_photo_picker",
            properties: ["profile_id": profileStore.activeProfile.id.uuidString]
        )

        isProcessingPhoto = true
        let requestID = UUID()
        activePhotoRequestID = requestID
        photoLoadingTask = Task {
            var loadedImage: UIImage?

            do {
                if let data = try await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loadedImage = image
                }
            } catch {
                // Ignore errors for now
            }

            if Task.isCancelled == false, let image = loadedImage {
                await MainActor.run {
                    guard activePhotoRequestID == requestID else { return }
                    pendingCrop = PendingCropImage(image: image)
                }
            }

            await MainActor.run {
                guard activePhotoRequestID == requestID else { return }
                selectedPhoto = nil
                isProcessingPhoto = false
                activePhotoRequestID = nil
                photoLoadingTask = nil
            }
        }
    }

    private func handleReminderToggleChange(_ newValue: Bool) {
        isUpdatingReminders = true
        Task {
            let result = await profileStore.setRemindersEnabled(newValue)
            await MainActor.run {
                isUpdatingReminders = false
                refreshActionReminderSummaries()
                if result == .authorizationDenied {
                    activeAlert = .notificationsSettings
                }
            }
        }
    }

    private func deleteProfile(_ profile: ChildProfile) {
        profileStore.deleteProfile(profile)
        profilePendingDeletion = nil
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case .notificationsSettings:
            return Alert(
                title: Text(L10n.Settings.notificationsPermissionTitle),
                message: Text(L10n.Settings.notificationsPermissionMessage),
                primaryButton: .default(Text(L10n.Settings.notificationsPermissionAction)) {
                    Analytics.capture(
                        "settings_open_notification_settings_alert",
                        properties: ["profile_id": profileStore.activeProfile.id.uuidString]
                    )
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                },
                secondaryButton: .cancel(Text(L10n.Settings.notificationsPermissionCancel)) {
                    Analytics.capture(
                        "settings_dismiss_notification_settings_alert",
                        properties: ["profile_id": profileStore.activeProfile.id.uuidString]
                    )
                }
            )
        }
    }

    @MainActor
    private func refreshActionReminderSummaries() {
        reminderLoadTask?.cancel()

        guard profileStore.activeProfile.remindersEnabled else {
            actionReminderSummaries = [:]
            isLoadingActionReminders = false
            loadingReminderCategories = []
            reminderLoadTask = nil
            return
        }

        let profileID = profileStore.activeProfile.id
        isLoadingActionReminders = true
        actionReminderSummaries = [:]
        loadingReminderCategories = []

        reminderLoadTask = Task {
            let summaries = await profileStore.nextActionReminderSummaries(for: profileID)

            await MainActor.run {
                defer { reminderLoadTask = nil }

                guard profileStore.activeProfile.id == profileID else {
                    isLoadingActionReminders = false
                    return
                }

                if Task.isCancelled {
                    isLoadingActionReminders = false
                    return
                }

                actionReminderSummaries = summaries
                isLoadingActionReminders = false
            }
        }
    }

    @MainActor
    private func updateActionReminderSummary(for category: BabyActionCategory) {
        guard profileStore.activeProfile.remindersEnabled else {
            actionReminderSummaries[category] = nil
            loadingReminderCategories.remove(category)
            return
        }

        let profileID = profileStore.activeProfile.id
        loadingReminderCategories.insert(category)

        Task {
            let summary = await profileStore.nextActionReminderSummary(for: profileID, category: category)

            await MainActor.run {
                defer { loadingReminderCategories.remove(category) }

                guard profileStore.activeProfile.id == profileID else { return }

                guard profileStore.activeProfile.remindersEnabled,
                      profileStore.activeProfile.isActionReminderEnabled(for: category) else {
                    actionReminderSummaries[category] = nil
                    return
                }

                actionReminderSummaries[category] = summary
            }
        }
    }
}

private extension SettingsView {
    struct PendingCropImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    enum ActiveAlert: Identifiable {
        case notificationsSettings

        var id: String {
            switch self {
            case .notificationsSettings:
                return "notifications-settings"
            }
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { isPresented in
                if isPresented == false {
                    profilePendingDeletion = nil
                }
            }
        )
    }

    private var deletionConfirmationTitle: String {
        guard let profile = profilePendingDeletion else { return "" }
        return L10n.Profiles.deleteConfirmationTitle(profile.displayName)
    }

    private func reminderHours(for category: BabyActionCategory) -> Int {
        let interval = profileStore.activeProfile.reminderInterval(for: category)
        return max(1, Int(round(interval / 3600)))
    }

    private func reminderIntervalBinding(for category: BabyActionCategory) -> Binding<Int> {
        Binding(
            get: { reminderHours(for: category) },
            set: { newValue in
                let clamped = max(1, min(12, newValue))
                let interval = TimeInterval(clamped) * 3600
                Analytics.capture(
                    "settings_adjust_reminder_frequency",
                    properties: [
                        "profile_id": profileStore.activeProfile.id.uuidString,
                        "category": category.rawValue,
                        "hours": "\(clamped)"
                    ]
                )
                profileStore.updateActiveProfile { profile in
                    profile.setReminderInterval(interval, for: category)
                }
                updateActionReminderSummary(for: category)
            }
        )
    }

    private func reminderEnabledBinding(for category: BabyActionCategory) -> Binding<Bool> {
        Binding(
            get: { profileStore.activeProfile.isActionReminderEnabled(for: category) },
            set: { newValue in
                Analytics.capture(
                    "settings_toggle_category_reminder",
                    properties: [
                        "profile_id": profileStore.activeProfile.id.uuidString,
                        "category": category.rawValue,
                        "is_on": newValue ? "true" : "false"
                    ]
                )
                profileStore.updateActiveProfile { profile in
                    profile.setReminderEnabled(newValue, for: category)
                }

                if newValue {
                    updateActionReminderSummary(for: category)
                } else {
                    actionReminderSummaries[category] = nil
                    loadingReminderCategories.remove(category)
                }
            }
        )
    }

    @ViewBuilder
    private func actionReminderRow(for category: BabyActionCategory) -> some View {
        let intervalBinding = reminderIntervalBinding(for: category)
        let enabledBinding = reminderEnabledBinding(for: category)
        let isCategoryEnabled = profileStore.activeProfile.isActionReminderEnabled(for: category)
        let remindersEnabled = profileStore.activeProfile.remindersEnabled

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: enabledBinding) {
                Label(L10n.Settings.actionReminderTitle(category.title), systemImage: category.icon)
            }
            .postHogLabel("settings.reminders.category.\(category.rawValue).toggle")
            .disabled(remindersEnabled == false)
            .tint(category.accentColor)

            Stepper(value: intervalBinding, in: 1...12) {
                Text(L10n.Settings.actionReminderFrequencyDescription(reminderHours(for: category)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .postHogLabel("settings.reminders.category.\(category.rawValue).frequency")
            .disabled(remindersEnabled == false || isCategoryEnabled == false)

            actionReminderStatus(for: category, isEnabled: remindersEnabled && isCategoryEnabled)
        }
        .padding(.vertical, 4)
        .frame(minHeight: Layout.actionReminderRowMinHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func actionReminderStatus(for category: BabyActionCategory, isEnabled: Bool) -> some View {
        let isCategoryLoading = isLoadingActionReminders || loadingReminderCategories.contains(category)

        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.Settings.nextReminderLabel)
                .font(.footnote)
                .fontWeight(.semibold)

            Group {
                if isEnabled == false {
                    Text(L10n.Settings.nextReminderDisabled)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isCategoryLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text(L10n.Settings.nextReminderLoading)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let summary = actionReminderSummaries[category] {
                    Text(
                        L10n.Settings.nextReminderScheduled(
                            summary.fireDate.formatted(date: .abbreviated, time: .shortened),
                            summary.message
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.Settings.nextReminderUnavailable)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Layout.actionReminderStatusHeight, alignment: .topLeading)
        .padding(.vertical, 4)
    }

}

private enum Layout {
    static let actionReminderRowMinHeight: CGFloat = 148
    static let actionReminderStatusHeight: CGFloat = 60
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ProfileStore.preview)
            .environmentObject(ActionLogStore.previewStore(profiles: [:]))
            .environmentObject(LocationManager.shared)

    }
}
