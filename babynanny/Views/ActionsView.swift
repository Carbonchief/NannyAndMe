import SwiftData
import SwiftUI

struct ActionsView: View {
    private let profileID: UUID
    @Query private var actions: [BabyActionModel]

    init(profileID: UUID) {
        self.profileID = profileID
        _actions = Query(
            filter: #Predicate<BabyActionModel> { model in
                model.profile?.profileID == profileID
            },
            sort: [
                SortDescriptor(\BabyActionModel.startDateRawValue, order: .reverse)
            ],
            animation: .default
        )
    }

    var body: some View {
        List(actions) { model in
            let action = model.asBabyAction()
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.headline)
                Text(action.detailDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(action.startDateTimeDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text(L10n.Stats.activeActionsTitle))
    }
}

#Preview {
    NavigationStack {
        ActionsView(profileID: UUID())
    }
    .modelContainer(AppDataStack.preview().modelContainer)
}
