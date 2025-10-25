import SwiftData
import SwiftUI

struct ProfileListView: View {
    @Query(sort: [
        SortDescriptor(\ProfileActionStateModel.name),
        SortDescriptor(\ProfileActionStateModel.birthDate, order: .reverse)
    ]) private var profiles: [ProfileActionStateModel]

    var onSelect: ((ProfileActionStateModel) -> Void)?

    var body: some View {
        List {
            ForEach(profiles) { profile in
                Button {
                    onSelect?(profile)
                } label: {
                    HStack(spacing: 12) {
                        ProfileAvatarView(imageData: profile.imageData, size: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name?.isEmpty == false ? profile.name! : L10n.Profile.newProfile)
                                .font(.headline)
                            if let birthDate = profile.birthDate {
                                Text(birthDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.Profiles.title)
    }
}

#Preview {
    NavigationStack {
        ProfileListView()
    }
    .modelContainer(AppDataStack.preview().modelContainer)
}
