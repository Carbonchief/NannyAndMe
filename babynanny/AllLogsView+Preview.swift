import SwiftUI

#Preview {
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile
    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(
            category: .sleep,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-1800)
        ),
        BabyActionSnapshot(
            category: .feeding,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-6600),
            feedingType: .bottle,
            bottleType: .formula,
            bottleVolume: 120
        ),
        BabyActionSnapshot(
            category: .diaper,
            startDate: Date().addingTimeInterval(-86000),
            endDate: Date().addingTimeInterval(-85800),
            diaperType: .pee
        )
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return NavigationStack {
        AllLogsView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
    }
}
