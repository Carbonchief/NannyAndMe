//
//  SettingsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUpdatingReminders = false
    @State private var profilePendingDeletion: ChildProfile?

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
                                await profileStore.setRemindersEnabled(newValue)
                                await MainActor.run {
                                    isUpdatingReminders = false
                                }
                            }
                        }
                    )
                ) {
                    Text(L10n.Settings.enableReminders)
                }
                .disabled(isUpdatingReminders)
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
    }

    private func deleteProfile(_ profile: ChildProfile) {
        profileStore.deleteProfile(profile)
        actionStore.removeProfileData(for: profile.id)
        profilePendingDeletion = nil
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ProfileStore.preview)
            .environmentObject(ActionLogStore.previewStore(profiles: [:]))

    }
}
