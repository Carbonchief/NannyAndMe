import SwiftUI

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
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
    let profileStore = ProfileStore(initialProfiles: [profile], activeProfileID: profile.id, directory: FileManager.default.temporaryDirectory, filename: "previewProfiles.json")

    return NavigationStack {
        AllLogsView()
            .environmentObject(profileStore)
            .environmentObject(actionStore)
    }
}
