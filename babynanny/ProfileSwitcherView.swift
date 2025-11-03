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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        isAddProfilePromptPresented = true
                    } label: {
                        Label(L10n.Profiles.addProfile, systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Profiles.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isAddProfilePromptPresented) {
            AddProfilePromptView { name, birthDate, imageData in
                profileStore.addProfile(name: name, birthDate: birthDate, imageData: imageData)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ProfileSwitcherView()
        .environmentObject(ProfileStore.preview)
}
