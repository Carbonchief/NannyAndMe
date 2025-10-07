import SwiftUI

struct AllLogsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @State private var editingAction: BabyAction?

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .navigationTitle(L10n.Logs.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $editingAction) { action in
            ActionEditSheet(action: action) { updatedAction in
                actionStore.updateAction(for: profileStore.activeProfile.id, action: updatedAction)
                editingAction = nil
            }
        }
    }

    @ViewBuilder
    private func content(asOf referenceDate: Date) -> some View {
        let grouped = groupedActions()

        if grouped.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(L10n.Logs.emptyTitle)
                    .font(.headline)
                Text(L10n.Logs.emptySubtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(grouped, id: \.date) { entry in
                    Section(header: Text(dateFormatter.string(from: entry.date))) {
                        ForEach(entry.actions) { action in
                            logRow(for: action, asOf: referenceDate)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }

    private func groupedActions() -> [(date: Date, actions: [BabyAction])] {
        let actions = actionStore.state(for: profileStore.activeProfile.id).history
        var grouped: [Date: [BabyAction]] = [:]
        var orderedDates: [Date] = []

        for action in actions.sorted(by: { $0.startDate > $1.startDate }) {
            let day = calendar.startOfDay(for: action.startDate)

            if grouped[day] != nil {
                grouped[day]?.append(action)
            } else {
                grouped[day] = [action]
                orderedDates.append(day)
            }
        }

        return orderedDates.map { date in
            let actionsForDate = grouped[date] ?? []
            return (date: date, actions: actionsForDate)
        }
    }

    private func logRow(for action: BabyAction, asOf referenceDate: Date) -> some View {
        Button {
            editingAction = action
        } label: {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(action.category.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)

                    Image(systemName: action.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(action.category.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Logs.entryTitle(timeFormatter.string(from: action.startDate),
                                               durationDescription(for: action, asOf: referenceDate),
                                               actionSummary(for: action)))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let detail = detailedDescription(for: action) {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func durationDescription(for action: BabyAction, asOf referenceDate: Date) -> String {
        action.durationDescription(asOf: referenceDate)
    }

    private func actionSummary(for action: BabyAction) -> String {
        switch action.category {
        case .sleep:
            return L10n.Logs.summarySleep()
        case .diaper:
            if let type = action.diaperType {
                return L10n.Logs.summaryDiaper(withType: type.title.localizedLowercase)
            }
            return L10n.Logs.summaryDiaper()
        case .feeding:
            if let type = action.feedingType {
                if type == .bottle, let volume = action.bottleVolume {
                    return L10n.Logs.summaryFeedingBottle(volume: volume)
                }
                return L10n.Logs.summaryFeeding(withType: type.title.localizedLowercase)
            }
            return L10n.Logs.summaryFeeding()
        }
    }

    private func detailedDescription(for action: BabyAction) -> String? {
        if action.endDate == nil {
            return L10n.Logs.active
        }
        return nil
    }
}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    var state = ProfileActionState()
    state.history = [
        BabyAction(
            category: .sleep,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-1800)
        ),
        BabyAction(
            category: .feeding,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-6600),
            feedingType: .bottle,
            bottleVolume: 120
        ),
        BabyAction(
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
