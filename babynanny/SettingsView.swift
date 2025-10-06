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
    @State private var selectedPhoto: PhotosPickerItem?

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
                Toggle(isOn: .constant(true)) {
                    Text(L10n.Settings.enableReminders)
                }
                .disabled(true)
                .foregroundStyle(.secondary)
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
    }

}

#Preview {
    NavigationStack {
        SettingsView().environmentObject(ProfileStore.preview)

    }
}
