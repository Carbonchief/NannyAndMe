import SwiftUI

struct ProfileSwitcherView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var isAddProfilePromptPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L10n.Profiles.activeSection)) {
                    ForEach(profileStore.profiles) { profile in
                        Button {
                            profileStore.setActiveProfile(profile)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ProfileAvatarView(imageData: profile.imageData, size: 44)

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
                        }
                        .buttonStyle(.plain)
                        .postHogLabel("profile.select.\(profile.id.uuidString)")
                        .phCaptureTap(
                            event: "profileSwitcher_select_profile_row",
                            properties: ["profile_id": profile.id.uuidString]
                        )
                    }
                }

                Section {
                    Button {
                        Analytics.capture(
                            "profileSwitcher_add_profile_button",
                            properties: [
                                "profile_count": "\(profileStore.profiles.count)"
                            ]
                        )
                        isAddProfilePromptPresented = true
                    } label: {
                        Label(L10n.Profiles.addProfile, systemImage: "plus")
                    }
                    .postHogLabel("profile.add")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Profiles.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                    .postHogLabel("profileSwitcher.done")
                    .phCaptureTap(event: "profileSwitcher_done_toolbar")
                }
            }
        }
        .phScreen("profileSwitcher_sheet_profileSwitcherView")
        .sheet(isPresented: $isAddProfilePromptPresented) {
            AddProfilePromptView(analyticsSource: "profileSwitcher_addProfilePrompt") { name, imageData in
                Analytics.capture(
                    "profileSwitcher_add_profile_confirm",
                    properties: [
                        "profile_count": "\(profileStore.profiles.count)",
                        "name_length": "\(name.count)",
                        "has_photo": imageData == nil ? "false" : "true"
                    ]
                )
                profileStore.addProfile(name: name, imageData: imageData)
            } onCancel: {
                Analytics.capture("profileSwitcher_add_profile_cancel")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ProfileSwitcherView()
        .environmentObject(ProfileStore.preview)
}
