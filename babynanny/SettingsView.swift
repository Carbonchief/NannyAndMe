//
//  SettingsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        Form {
            Section(header: Text("Child Profile")) {
                HStack(alignment: .center, spacing: 16) {
                    profileImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(radius: 3)

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Child name", text: Binding(
                            get: { profileStore.profile.name },
                            set: { profileStore.profile.name = $0 }
                        ))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)

                        DatePicker(
                            "Birth date",
                            selection: Binding(
                                get: { profileStore.profile.birthDate },
                                set: { profileStore.profile.birthDate = $0 }
                            ),
                            in: Date.distantPast...Date(),
                            displayedComponents: .date
                        )
                    }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Label("Choose profile photo", systemImage: "photo.on.rectangle")
                }
                .onChange(of: selectedPhoto) { newValue in
                    guard let newValue else { return }

                    Task {
                        if let data = try? await newValue.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                profileStore.profile.imageData = data
                            }
                        }
                    }
                }

                if profileStore.profile.imageData != nil {
                    Button(role: .destructive) {
                        profileStore.profile.imageData = nil
                    } label: {
                        Label("Remove profile photo", systemImage: "trash")
                    }
                }
            }

            Section(header: Text("Notifications")) {
                Toggle(isOn: .constant(true)) {
                    Text("Enable reminders")
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            }

            Section(header: Text("About")) {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var profileImage: Image {
        #if canImport(UIKit)
        if let data = profileStore.profile.imageData,
           let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #endif

        return Image(systemName: "person.circle.fill")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(ProfileStore.preview)
    }
}
