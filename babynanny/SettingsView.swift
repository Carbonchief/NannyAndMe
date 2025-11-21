//
//  SettingsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import PhotosUI
import UIKit
import RevenueCatUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var subscriptionService: RevenueCatSubscriptionService
    @EnvironmentObject private var analyticsConsentManager: AnalyticsConsentManager
    @Environment(\.openURL) private var openURL
    @AppStorage("trackActionLocations") private var trackActionLocations = false
    @AppStorage(UserDefaultsKey.hideActionMap) private var hideActionMap = false
    @AppStorage(UserDefaultsKey.actionHapticsEnabled) private var actionHapticsEnabled = true
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
    @State private var isPaywallPresented = false
    @State private var pendingLocationUnlock = false
    @State private var pendingAddProfileUnlock = false
    @State private var isCustomerCenterPresented = false
    @State private var activeProfileName = ""
    @FocusState private var isProfileNameFocused: Bool

    var body: some View {
        Form {
            profilesSection
            activeProfileSection
            subscriptionSection
            homeSection
            privacySection
            notificationsSection
            aboutSection
        }
        .navigationTitle(L10n.Settings.title)
        .alert(item: $activeAlert, content: makeAlert)
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: deletionConfirmationBinding,
            titleVisibility: .visible,
            presenting: profilePendingDeletion
        ) { profile in
            Button(L10n.Profiles.deleteAction, role: .destructive) {
                deleteProfile(profile)
            }
            Button(L10n.Common.cancel, role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: { profile in
            Text(L10n.Profiles.deleteConfirmationMessage(profile.displayName))
        }
        .onAppear {
            refreshActionReminderSummaries()
            activeProfileName = profileStore.activeProfile.name
        }
        .onChange(of: profileStore.activeProfileID) { _, _ in
            refreshActionReminderSummaries()
            activeProfileName = profileStore.activeProfile.name
        }
        .onChange(of: profileStore.activeProfile.remindersEnabled) { _, _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.birthDate) { _, _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.name) { _, _ in
            refreshActionReminderSummaries()
            if isProfileNameFocused == false {
                activeProfileName = profileStore.activeProfile.name
            }
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
            AddProfilePromptView { name, birthDate, imageData in
                profileStore.addProfile(name: name, birthDate: birthDate, imageData: imageData)
            }
        }
        .sheet(isPresented: $isCustomerCenterPresented) {
            CustomerCenterView()
        }
        .fullScreenCover(item: $pendingCrop) { crop in
            ImageCropperView(image: crop.image) {
                pendingCrop = nil
            } onCrop: { croppedImage in
                if let data = croppedImage.compressedData() {
                    profileStore.updateActiveProfile {
                        $0.imageData = data
                        $0.avatarURL = nil
                    }
                }
                pendingCrop = nil
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isPaywallPresented, onDismiss: {
            if subscriptionService.hasProAccess == false {
                pendingLocationUnlock = false
                pendingAddProfileUnlock = false
            }
        }) {
            NavigationStack {
                RevenueCatPaywallContainer()
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .background(Color(.systemBackground).ignoresSafeArea())
            }
        }
        .alert(L10n.Settings.Subscription.errorTitle,
               isPresented: Binding(
                get: { subscriptionService.lastError != nil && isPaywallPresented == false },
                set: { presented in
                    if presented == false {
                        subscriptionService.clearError()
                    }
                }
               )) {
            Button(L10n.Common.done, role: .cancel) {
                subscriptionService.clearError()
            }
        } message: {
            Text(subscriptionService.lastError?.localizedDescription ?? "")
        }
        .onChange(of: subscriptionService.hasProAccess) { _, newValue in
            if newValue {
                if pendingLocationUnlock {
                    if trackActionLocations == false {
                        withAnimation {
                            trackActionLocations = true
                        }
                    }
                    locationManager.requestPermissionIfNeeded()
                    locationManager.ensurePreciseAccuracyIfNeeded()
                    pendingLocationUnlock = false
                }
                if pendingAddProfileUnlock {
                    pendingAddProfileUnlock = false
                    isAddProfilePromptPresented = true
                }
                isPaywallPresented = false
            } else {
                if trackActionLocations {
                    trackActionLocations = false
                }
                pendingLocationUnlock = false
                pendingAddProfileUnlock = false
            }
        }
    }

    private var privacySection: some View {
        Section(header: Text(L10n.Settings.Privacy.sectionTitle)) {
            Toggle(isOn: $trackActionLocations) {
                Label(L10n.Settings.Privacy.trackActionLocations, systemImage: "location.fill")
            }
            .onChange(of: trackActionLocations) { _, newValue in
                if newValue {
                    guard subscriptionService.hasProAccess else {
                        pendingLocationUnlock = true
                        withAnimation {
                            trackActionLocations = false
                        }
                        isPaywallPresented = true
                        return
                    }

                    locationManager.requestPermissionIfNeeded()
                    locationManager.ensurePreciseAccuracyIfNeeded()
                } else if subscriptionService.hasProAccess {
                    pendingLocationUnlock = false
                }
            }

            if subscriptionService.hasProAccess {
                Text(L10n.Settings.Privacy.trackActionLocationsDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.Settings.Privacy.trackActionLocationsPremium)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if trackActionLocations,
               locationManager.authorizationStatus == .denied ||
               locationManager.authorizationStatus == .restricted {
                Button {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                } label: {
                    Label(L10n.Settings.Privacy.permissionDenied, systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
            }

            if trackActionLocations == false {
                Toggle(isOn: $hideActionMap) {
                    Label(L10n.Settings.Privacy.hideActionMap, systemImage: "map")
                }

                Text(L10n.Settings.Privacy.hideActionMapDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                AnalyticsPrivacyDisclosureView(consentStatus: analyticsConsentManager.consentStatus)
            } label: {
                Label(L10n.Settings.Privacy.analyticsDisclosureTitle, systemImage: "hand.raised.fill")
            }

            Text(L10n.Settings.Privacy.analyticsDisclosureSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var profilesSection: some View {
        Section(header: Text(L10n.Profiles.title)) {
            ForEach(profileStore.profiles) { profile in
                profileRow(for: profile)
            }

            Button {
                if subscriptionService.hasProAccess || profileStore.profiles.isEmpty {
                    isAddProfilePromptPresented = true
                } else {
                    pendingAddProfileUnlock = true
                    isPaywallPresented = true
                }
            } label: {
                Label(L10n.Profiles.addProfile, systemImage: "plus")
            }
        }
    }

    private var subscriptionSection: some View {
        Section(header: Text(L10n.Settings.Subscription.sectionTitle)) {
            if subscriptionService.hasProAccess {
                Button {
                    isCustomerCenterPresented = true
                } label: {
                    Label(L10n.Settings.Subscription.manageButton, systemImage: "person.crop.circle.badge.checkmark")
                }

                Button {
                    Task { await subscriptionService.restorePurchases() }
                } label: {
                    if subscriptionService.isRestoringPurchases {
                        HStack {
                            ProgressView()
                            Text(L10n.Settings.Subscription.restoring)
                        }
                    } else {
                        Label(L10n.Settings.Subscription.restoreButton, systemImage: "arrow.clockwise")
                    }
                }
                .disabled(subscriptionService.isRestoringPurchases)

                Text(L10n.Settings.Subscription.activeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    isPaywallPresented = true
                } label: {
                    Label(L10n.Settings.Subscription.unlockButton, systemImage: "sparkles")
                }

                Text(L10n.Settings.Subscription.unlockDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func profileRow(for profile: ChildProfile) -> some View {
        let isReadOnly = profile.sharePermission == .view

        HStack(spacing: 16) {
            ProfileAvatarView(imageData: profile.imageData,
                              size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                Text(profile.birthDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.ageDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if profile.isShared || isReadOnly {
                    ProfileAccessBadges(isShared: profile.isShared,
                                        isReadOnly: isReadOnly)
                }
            }

            Spacer()

            if profile.id == profileStore.activeProfileID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            profileStore.setActiveProfile(profile)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                profilePendingDeletion = profile
            } label: {
                Label(L10n.Profiles.deleteAction, systemImage: "trash")
            }
        }
    }

    private var activeProfileSection: some View {
        Section(header: Text(L10n.Profiles.activeProfileSection)) {
            activeProfileHeader
            processingPhotoIndicator
        }
    }

    private var activeProfileHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            profilePhotoSelector

            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.Profiles.childName, text: $activeProfileName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .focused($isProfileNameFocused)
                .onSubmit(commitActiveProfileName)
                .onChange(of: isProfileNameFocused) { _, focused in
                    if focused == false {
                        commitActiveProfileName()
                    }
                }

                DatePicker(
                    selection: Binding(
                        get: { profileStore.activeProfile.birthDate },
                        set: { newValue in
                        profileStore.updateActiveProfile { $0.setBirthDate(newValue) }
                        }
                    ),
                    in: Date.distantPast...Date(),
                    displayedComponents: .date
                ) {
                    Text(L10n.Profiles.birthDate)
                }
            }
        }
    }

    private func commitActiveProfileName() {
        let nameToSave = activeProfileName

        guard nameToSave != profileStore.activeProfile.name else { return }

        profileStore.updateActiveProfile { $0.name = nameToSave }
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

    @MainActor
    private var profilePhotoSelector: some View {
        let activeImageData = profileStore.activeProfile.imageData
        let activeAvatarURL = profileStore.activeProfile.avatarURL
        let hasAvatarImage = activeImageData != nil || activeAvatarURL != nil
        let avatarPreview = ProfileAvatarView(imageData: activeImageData,
                                              size: 72)

        return ZStack(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                avatarPreview
                    .overlay(alignment: .bottomTrailing) {
                        if hasAvatarImage == false {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                                .shadow(radius: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Profiles.choosePhoto)
            .onChange(of: selectedPhoto) { _, newValue in
                handlePhotoSelectionChange(newValue)
            }

            if hasAvatarImage {
                Button {
                    profileStore.updateActiveProfile {
                        $0.imageData = nil
                        $0.avatarURL = nil
                    }
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
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
            .onChange(of: profileStore.showRecentActivityOnHome) { _, newValue in
            }

            Toggle(isOn: $actionHapticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Settings.actionHapticsToggle)
                    Text(L10n.Settings.actionHapticsDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        .disabled(isUpdatingReminders)
        .onChange(of: profileStore.activeProfile.remindersEnabled) { _, newValue in
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

    private func handlePhotoSelectionChange(_ newValue: PhotosPickerItem?) {
        photoLoadingTask?.cancel()
        guard let newValue else { return }


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
        Task { @MainActor in
            let result = await profileStore.setRemindersEnabled(newValue)
            isUpdatingReminders = false
            refreshActionReminderSummaries()
            if result == .authorizationDenied {
                activeAlert = .notificationsSettings
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
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                },
                secondaryButton: .cancel(Text(L10n.Settings.notificationsPermissionCancel)) {
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

        reminderLoadTask = Task { @MainActor in
            let summaries = await profileStore.nextActionReminderSummaries(for: profileID)

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

    @MainActor
    private func updateActionReminderSummary(for category: BabyActionCategory) {
        guard profileStore.activeProfile.remindersEnabled else {
            actionReminderSummaries[category] = nil
            loadingReminderCategories.remove(category)
            return
        }

        let profileID = profileStore.activeProfile.id
        loadingReminderCategories.insert(category)

        Task { @MainActor in
            let summary = await profileStore.nextActionReminderSummary(for: profileID, category: category)

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
            .disabled(remindersEnabled == false)
            .tint(category.accentColor)

            Stepper(value: intervalBinding, in: 1...12) {
                Text(L10n.Settings.actionReminderFrequencyDescription(reminderHours(for: category)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

private struct AnalyticsPrivacyDisclosureView: View {
    let consentStatus: AnalyticsConsentManager.ConsentStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.Settings.Privacy.analyticsDisclosureHeadline)
                    .font(.title2)
                    .bold()

                Text(L10n.Settings.Privacy.analyticsDisclosureBody)

                Text(consentStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.Settings.Privacy.analyticsDisclosureTitle)
    }

    private var consentStatusMessage: String {
        switch consentStatus {
        case .authorized:
            return L10n.Settings.Privacy.analyticsConsentStatusAllowed
        case .denied:
            return L10n.Settings.Privacy.analyticsConsentStatusDenied
        case .notDetermined:
            return L10n.Settings.Privacy.analyticsConsentStatusPending
        }
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
            .environmentObject(RevenueCatSubscriptionService())
            .environmentObject(AnalyticsConsentManager.shared)

    }
}
