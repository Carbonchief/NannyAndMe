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
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCrop: PendingCropImage?
    @State private var isProcessingPhoto = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoRequestID: UUID?
    @State private var isUpdatingReminders = false
    @State private var actionReminderSummaries: [BabyActionCategory: ProfileStore.ActionReminderSummary] = [:]
    @State private var isLoadingActionReminders = false
    @State private var reminderLoadTask: Task<Void, Never>?
    @State private var activeAlert: ActiveAlert?
    @State private var profilePendingDeletion: ChildProfile?

    var body: some View {
        Form {
            profilesSection
            activeProfileSection
            homeSection
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
        }
        .onChange(of: profileStore.activeProfileID) {
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.remindersEnabled) {
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.birthDate) {
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.name) {
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

    private var profilesSection: some View {
        Section(header: Text(L10n.Profiles.title)) {
            ForEach(profileStore.profiles) { profile in
                profileRow(for: profile)
            }

            Button {
                profileStore.addProfile()
            } label: {
                Label(L10n.Profiles.addProfile, systemImage: "plus")
            }
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
                TextField(L10n.Profiles.childName, text: Binding(
                    get: { profileStore.activeProfile.name },
                    set: { newValue in
                        profileStore.updateActiveProfile { $0.name = newValue }
                    }
                ))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

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
        ZStack(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                ProfileAvatarView(imageData: profileStore.activeProfile.imageData, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        if profileStore.activeProfile.imageData == nil {
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

            if profileStore.activeProfile.imageData != nil {
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
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                },
                secondaryButton: .cancel(Text(L10n.Settings.notificationsPermissionCancel))
            )
        }
    }

    private func refreshActionReminderSummaries() {
        reminderLoadTask?.cancel()

        guard profileStore.activeProfile.remindersEnabled else {
            actionReminderSummaries = [:]
            isLoadingActionReminders = false
            reminderLoadTask = nil
            return
        }

        let profileID = profileStore.activeProfile.id
        isLoadingActionReminders = true
        actionReminderSummaries = [:]

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
                refreshActionReminderSummaries()
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
                refreshActionReminderSummaries()
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
    }

    @ViewBuilder
    private func actionReminderStatus(for category: BabyActionCategory, isEnabled: Bool) -> some View {
        if isEnabled == false {
            Text(L10n.Settings.actionReminderDisabled)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else if isLoadingActionReminders {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                Text(L10n.Settings.nextReminderLoading)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if let summary = actionReminderSummaries[category] {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Settings.nextReminderLabel)
                    .font(.footnote)
                    .fontWeight(.semibold)

                Text(
                    L10n.Settings.nextReminderScheduled(
                        summary.fireDate.formatted(date: .abbreviated, time: .shortened),
                        summary.message
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ProfileStore.preview)
            .environmentObject(ActionLogStore.previewStore(profiles: [:]))

    }
}
