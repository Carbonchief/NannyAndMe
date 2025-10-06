//
//  StatsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore

    var body: some View {
        let state = currentState
        let today = todayActions(for: state)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection(for: state, todayActions: today)

                statsGrid(for: state, todayActions: today)

                if let recent = state.mostRecentAction {
                    recentActivitySection(with: recent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Stats")
    }

    private func headerSection(for state: ProfileActionState, todayActions: [BabyAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Snapshot")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tracking \(todayActions.count) activities for \(profileStore.activeProfile.displayName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func statsGrid(for state: ProfileActionState, todayActions: [BabyAction]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(title: "Active Actions",
                         value: "\(state.activeActions.count)",
                         subtitle: "Running right now",
                         icon: "play.circle.fill",
                         tint: .blue)

                StatCard(title: "Today's Logs",
                         value: "\(todayActions.count)",
                         subtitle: "Completed entries",
                         icon: "calendar",
                         tint: .indigo)
            }

            HStack(spacing: 16) {
                StatCard(title: "Bottle Feed (ml)",
                         value: "\(todayBottleVolume(for: todayActions))",
                         subtitle: "Total today",
                         icon: "takeoutbag.and.cup.and.straw.fill",
                         tint: .orange)

                StatCard(title: "Sleep Sessions",
                         value: "\(todaySleepCount(for: todayActions))",
                         subtitle: "Today",
                         icon: "moon.zzz.fill",
                         tint: .purple)
            }
        }
    }

    private func recentActivitySection(with action: BabyAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Recent Activity")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: action.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(action.category.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(.headline)

                        Text(action.detailDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Started \(action.startDateTimeDescription())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let ended = action.endDateTimeDescription() {
                    Text("Ended \(ended) • Duration \(action.durationDescription())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Active for \(action.durationDescription(asOf: context.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
        }
    }

    private var currentState: ProfileActionState {
        actionStore.state(for: profileStore.activeProfile.id)
    }

    private func todayActions(for state: ProfileActionState) -> [BabyAction] {
        let calendar = Calendar.current
        return state.history.filter { calendar.isDate($0.startDate, inSameDayAs: Date()) }
    }

    private func todayBottleVolume(for actions: [BabyAction]) -> Int {
        actions.compactMap { action in
            guard action.category == .feeding, action.feedingType == .bottle else { return nil }
            return action.bottleVolume
        }.reduce(0, +)
    }

    private func todaySleepCount(for actions: [BabyAction]) -> Int {
        actions.filter { $0.category == .sleep }.count
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }
}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(initialProfiles: [profile], activeProfileID: profile.id, directory: FileManager.default.temporaryDirectory, filename: "previewStatsProfiles.json")

    var state = ProfileActionState()
    state.activeActions[.sleep] = BabyAction(category: .sleep, startDate: Date().addingTimeInterval(-1800))
    state.history = [
        BabyAction(category: .feeding, startDate: Date().addingTimeInterval(-7200), endDate: Date().addingTimeInterval(-6900), feedingType: .bottle, bottleVolume: 120),
        BabyAction(category: .diaper, startDate: Date().addingTimeInterval(-5400), endDate: Date().addingTimeInterval(-5300), diaperType: .both)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return StatsView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}
