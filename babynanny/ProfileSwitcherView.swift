import SwiftUI

struct ProfileSwitcherView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Active Profiles")) {
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
                    }
                }

                Section {
                    Button {
                        profileStore.addProfile()
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ProfileSwitcherView()
        .environmentObject(ProfileStore.preview)
}
