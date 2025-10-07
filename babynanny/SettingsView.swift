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
    @State private var isUpdatingReminders = false
    @State private var profilePendingDeletion: ChildProfile?
    @State private var actionReminderSummaries: [BabyActionCategory: ProfileStore.ActionReminderSummary] = [:]
    @State private var isLoadingActionReminders = false
    @State private var reminderLoadTask: Task<Void, Never>?
    @State private var showNotificationsSettingsPrompt = false

    var body: some View {
        Form {
            Section(header: Text(L10n.Profiles.title)) {
                ForEach(profileStore.profiles) { profile in
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

                Button {
                    profileStore.addProfile()
                } label: {
                    Label(L10n.Profiles.addProfile, systemImage: "plus")
                }
            }

            Section(header: Text(L10n.Profiles.activeProfileSection)) {
                HStack(alignment: .center, spacing: 16) {
                    ProfileAvatarView(imageData: profileStore.activeProfile.imageData, size: 72)

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

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Label(L10n.Profiles.choosePhoto, systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    guard let newValue else { return }

                    Task {
                        if let data = try? await newValue.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                profileStore.updateActiveProfile { $0.imageData = data }
                            }
                        }
                    }
                }

                if profileStore.activeProfile.imageData != nil {
                    Button(role: .destructive) {
                        profileStore.updateActiveProfile { $0.imageData = nil }
                    } label: {
                        Label(L10n.Profiles.removePhoto, systemImage: "trash")
                    }
                }
            }

            Section(header: Text(L10n.Settings.notificationsSection)) {
                Toggle(
                    isOn: Binding(
                        get: { profileStore.activeProfile.remindersEnabled },
                        set: { newValue in
                            isUpdatingReminders = true
                            Task {
                                let result = await profileStore.setRemindersEnabled(newValue)
                                await MainActor.run {
                                    isUpdatingReminders = false
                                    refreshActionReminderSummaries()
                                    if result == .authorizationDenied {
                                        showNotificationsSettingsPrompt = true
                                    }
                                }
                            }
                        }
                    )
                ) {
                    Text(L10n.Settings.enableReminders)
                }
                .disabled(isUpdatingReminders)

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

            Section(header: Text(L10n.Settings.aboutSection)) {
                HStack {
                    Text(L10n.Settings.appVersion)
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L10n.Settings.title)
        .alert(item: $profilePendingDeletion) { profile in
            Alert(
                title: Text(L10n.Profiles.deleteConfirmationTitle(profile.displayName)),
                message: Text(L10n.Profiles.deleteConfirmationMessage(profile.displayName)),
                primaryButton: .destructive(Text(L10n.Profiles.deleteAction)) {
                    deleteProfile(profile)
                },
                secondaryButton: .cancel {
                    profilePendingDeletion = nil
                }
            )
        }
        .alert(isPresented: $showNotificationsSettingsPrompt) {
            Alert(
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
        .onAppear {
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfileID) { _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.remindersEnabled) { _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.birthDate) { _ in
            refreshActionReminderSummaries()
        }
        .onChange(of: profileStore.activeProfile.name) { _ in
            refreshActionReminderSummaries()
        }
        .onDisappear {
            reminderLoadTask?.cancel()
            reminderLoadTask = nil
            isLoadingActionReminders = false
        }
    }

    private func deleteProfile(_ profile: ChildProfile) {
        profileStore.deleteProfile(profile)
        actionStore.removeProfileData(for: profile.id)
        profilePendingDeletion = nil
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
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.Settings.nextReminderLabel)
                .font(.footnote)
                .fontWeight(.semibold)

            if isEnabled == false {
                Text(L10n.Settings.actionReminderDisabled)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isLoadingActionReminders {
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
            } else {
                Text(L10n.Settings.nextReminderUnavailable)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ProfileStore.preview)
            .environmentObject(ActionLogStore.previewStore(profiles: [:]))

    }
}
