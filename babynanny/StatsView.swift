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

    @ViewBuilder
    private func dailyTrendSection(for state: ProfileActionState) -> some View {
        if let focusCategory = state.mostRecentAction?.category {
            let metrics = dailyMetrics(for: state, focusCategory: focusCategory)
            let hasData = metrics.contains { $0.value > 0 }
            let yAxisTitle = focusCategory == .diaper ? "Diapers" : "Minutes"

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last 7 Days")
                        .font(.headline)

                    Spacer()

                    Text(focusCategory.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(focusCategory.accentColor.opacity(0.12))
                        .foregroundStyle(focusCategory.accentColor)
                        .clipShape(Capsule())
                }

                if hasData {
                    Chart(metrics) { metric in
                        BarMark(
                            x: .value("Day", metric.date, unit: .day),
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
                            if let dateValue = value.as(Date.self) {
                                AxisValueLabel(dateValue, format: .dateTime.weekday(.abbreviated))
                            }
                        }
                    }
                    .frame(height: 220)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No \(focusCategory.title.lowercased()) logged in the last week.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Track \(focusCategory.title.lowercased()) to see trends over time.")
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
                Text("Activity Trends")
                    .font(.headline)

                Text("Once you start logging activities you'll see a weekly breakdown here.")
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
