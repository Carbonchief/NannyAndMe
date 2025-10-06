//
//  StatsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @State private var selectedCategory: BabyActionCategory?

    var body: some View {
        let state = currentState
        let today = todayActions(for: state)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection(for: state, todayActions: today)

                statsGrid(for: state, todayActions: today)

                dailyTrendSection(for: state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.Stats.title)
        .onChange(of: profileStore.activeProfile.id) { _ in
            selectedCategory = nil
        }
    }

    private func headerSection(for state: ProfileActionState, todayActions: [BabyAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Stats.dailySnapshotTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.Stats.trackingActivities(todayActions.count, profileStore.activeProfile.displayName))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func statsGrid(for state: ProfileActionState, todayActions: [BabyAction]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(title: L10n.Stats.activeActionsTitle,
                         value: "\(state.activeActions.count)",
                         subtitle: L10n.Stats.activeActionsSubtitle,
                         icon: "play.circle.fill",
                         tint: .blue)

                StatCard(title: L10n.Stats.todaysLogsTitle,
                         value: "\(todayActions.count)",
                         subtitle: L10n.Stats.todaysLogsSubtitle,
                         icon: "calendar",
                         tint: .indigo)
            }

            HStack(spacing: 16) {
                StatCard(title: L10n.Stats.bottleFeedTitle,
                         value: "\(todayBottleVolume(for: todayActions))",
                         subtitle: L10n.Stats.bottleFeedSubtitle,
                         icon: "takeoutbag.and.cup.and.straw.fill",
                         tint: .orange)

                StatCard(title: L10n.Stats.sleepSessionsTitle,
                         value: "\(todaySleepCount(for: todayActions))",
                         subtitle: L10n.Stats.sleepSessionsSubtitle,
                         icon: "moon.zzz.fill",
                         tint: .purple)
            }
        }
    }

    @ViewBuilder
    private func dailyTrendSection(for state: ProfileActionState) -> some View {
        let hasAnyTrackedData = !state.history.isEmpty || !state.activeActions.isEmpty

        if hasAnyTrackedData {
            let focusCategory = resolvedCategory(for: state)
            let metrics = dailyMetrics(for: state, focusCategory: focusCategory)
            let hasData = metrics.contains { $0.value > 0 }
            let yAxisTitle = focusCategory == .diaper ? L10n.Stats.diapersYAxis : L10n.Stats.minutesYAxis

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.Stats.lastSevenDays)
                        .font(.headline)

                    Spacer()

                    categoryPicker(for: state)
                }

                if hasData {
                    Chart(metrics) { metric in
                        BarMark(
                            x: .value(L10n.Stats.dayAxisLabel, metric.date, unit: .day),
                            y: .value(yAxisTitle, metric.value)
                        )
                        .foregroundStyle(focusCategory.accentColor.gradient)
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXAxis {
                        AxisMarks(values: metrics.map { $0.date }) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let dateValue = value.as(Date.self) {
                                    Text(dateValue, format: .dateTime.weekday(.abbreviated))
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Stats.emptyStateTitle(focusCategory.title.localizedLowercase))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(L10n.Stats.emptyStateSubtitle(focusCategory.title.localizedLowercase))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Stats.activityTrendsTitle)
                    .font(.headline)

                Text(L10n.Stats.activityTrendsSubtitle)
                    .font(.subheadline)
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

    private func resolvedCategory(for state: ProfileActionState) -> BabyActionCategory {
        selectedCategory ?? state.mostRecentAction?.category ?? .sleep
    }

    private func categoryPicker(for state: ProfileActionState) -> some View {
        let selection = resolvedCategory(for: state)

        return Picker(
            selection: Binding(
                get: { resolvedCategory(for: state) },
                set: { newValue in
                    selectedCategory = newValue
                }
            ),
            label: {
                HStack(spacing: 6) {
                    Image(systemName: selection.icon)
                        .font(.system(size: 14, weight: .semibold))

                    Text(selection.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selection.accentColor.opacity(0.12))
                .foregroundStyle(selection.accentColor)
                .clipShape(Capsule())
            }
        ) {
            ForEach(BabyActionCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L10n.Stats.actionPickerLabel)
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

    private func dailyMetrics(for state: ProfileActionState,
                              focusCategory: BabyActionCategory,
                              days: Int = 7) -> [DailyActionMetric] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var dailyTotals: [Date: DailyActionMetric] = [:]

        for offset in 0..<days {
            if let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) {
                dailyTotals[day] = DailyActionMetric(date: day, value: 0)
            }
        }

        for action in state.history where action.category == focusCategory {
            let day = calendar.startOfDay(for: action.startDate)
            guard var metric = dailyTotals[day] else { continue }

            if focusCategory == .diaper {
                metric.value += 1
            } else {
                let endDate = action.endDate ?? Date()
                let duration = max(0, endDate.timeIntervalSince(action.startDate))
                metric.value += duration / 60 // minutes
            }

            dailyTotals[day] = metric
        }

        if focusCategory != .diaper,
           let active = state.activeActions[focusCategory] {
            let day = calendar.startOfDay(for: active.startDate)
            if var metric = dailyTotals[day] {
                let duration = max(0, Date().timeIntervalSince(active.startDate))
                metric.value += duration / 60
                dailyTotals[day] = metric
            }
        }

        return dailyTotals
            .values
            .sorted { $0.date < $1.date }
    }
}

private struct DailyActionMetric: Identifiable {
    let date: Date
    var value: Double

    var id: Date { date }
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
    let calendar = Calendar.current
    let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()

    state.history = [
        BabyAction(category: .sleep,
                   startDate: calendar.date(byAdding: .hour, value: -1, to: yesterday) ?? yesterday,
                   endDate: calendar.date(byAdding: .minute, value: -30, to: yesterday)),
        BabyAction(category: .sleep,
                   startDate: calendar.date(byAdding: .hour, value: -2, to: twoDaysAgo) ?? twoDaysAgo,
                   endDate: calendar.date(byAdding: .hour, value: -1, to: twoDaysAgo)),
        BabyAction(category: .feeding,
                   startDate: Date().addingTimeInterval(-7200),
                   endDate: Date().addingTimeInterval(-6900),
                   feedingType: .bottle,
                   bottleVolume: 120),
        BabyAction(category: .diaper,
                   startDate: Date().addingTimeInterval(-5400),
                   endDate: Date().addingTimeInterval(-5300),
                   diaperType: .both)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return StatsView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}
