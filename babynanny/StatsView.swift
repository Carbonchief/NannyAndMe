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

                actionPatternSection(for: state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(L10n.Stats.title)
        .onChange(of: profileStore.activeProfile.id) {
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

    @ViewBuilder
    private func actionPatternSection(for state: ProfileActionState) -> some View {
        let focusCategory = resolvedCategory(for: state)
        let windowDays = 7
        let patternSegments = actionPatternSegments(for: state,
                                                   focusCategory: focusCategory,
                                                   days: windowDays)
        let hasData = !patternSegments.isEmpty
        let dayAxisValues = orderedDays(for: patternSegments, totalDays: windowDays)

        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Stats.patternTitle)
                .font(.headline)

            Text(L10n.Stats.patternSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if hasData {
                Chart(patternSegments) { segment in
                    BarMark(
                        x: .value(L10n.Stats.dayAxisLabel, segment.day, unit: .day),
                        yStart: .value(L10n.Stats.hourAxisLabel, segment.startMinutes),
                        yEnd: .value(L10n.Stats.hourAxisLabel, segment.endMinutes)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(focusCategory.accentColor.gradient)
                }
                .chartYAxis {
                    AxisMarks(values: Array(stride(from: 0, through: 1440, by: 180))) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(timeLabel(for: minutes))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...1440)
                .chartXAxis {
                    AxisMarks(values: dayAxisValues) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                Text(dayLabel(for: dateValue))
                            }
                        }
                    }
                }
                .frame(height: 220)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Stats.patternEmptyTitle(focusCategory.title.localizedLowercase))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(L10n.Stats.patternEmptySubtitle(focusCategory.title.localizedLowercase))
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
    }

    private func resolvedCategory(for state: ProfileActionState) -> BabyActionCategory {
        selectedCategory ?? state.mostRecentAction?.category ?? .sleep
    }

    // MARK: - FIXED: use @ViewBuilder + trailing-closure Picker label (no explicit `return`)
    @ViewBuilder
    private func categoryPicker(for state: ProfileActionState) -> some View {
        let selection = resolvedCategory(for: state)
        let binding = Binding<BabyActionCategory>(
            get: { resolvedCategory(for: state) },
            set: { newValue in
                selectedCategory = newValue
            }
        )

        Picker(selection: binding) {
            ForEach(BabyActionCategory.allCases) { category in
                Text(category.title).tag(category)
            }
        } label: {
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

    private func actionPatternSegments(for state: ProfileActionState,
                                       focusCategory: BabyActionCategory,
                                       days: Int = 7) -> [ActionPatternSegment] {
        let calendar = Calendar.current
        let now = Date()
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else {
            return []
        }

        var segments: [ActionPatternSegment] = []

        for action in state.history where action.category == focusCategory {
            if focusCategory == .diaper {
                guard action.startDate >= windowStart else { continue }
                let day = calendar.startOfDay(for: action.startDate)
                let minutes = Double(calendar.component(.hour, from: action.startDate) * 60 +
                    calendar.component(.minute, from: action.startDate))
                let endMinutes = min(minutes + 5, 1440)
                segments.append(ActionPatternSegment(day: day,
                                                     startMinutes: minutes,
                                                     endMinutes: endMinutes))
            } else {
                let actionStart = max(action.startDate, windowStart)
                let actionEnd = min(action.endDate ?? now, now)

                guard actionEnd > actionStart else { continue }

                segments.append(contentsOf: splitAction(from: actionStart,
                                                        to: actionEnd,
                                                        calendar: calendar))
            }
        }

        if focusCategory != .diaper, let active = state.activeActions[focusCategory] {
            let actionStart = max(active.startDate, windowStart)
            let actionEnd = now

            if actionEnd > actionStart {
                segments.append(contentsOf: splitAction(from: actionStart,
                                                        to: actionEnd,
                                                        calendar: calendar))
            }
        }

        return segments.sorted { lhs, rhs in
            if lhs.day == rhs.day {
                return lhs.startMinutes < rhs.startMinutes
            }
            return lhs.day < rhs.day
        }
    }

    private func splitAction(from start: Date,
                              to end: Date,
                              calendar: Calendar) -> [ActionPatternSegment] {
        var results: [ActionPatternSegment] = []
        var currentDayStart = calendar.startOfDay(for: start)

        while currentDayStart < end {
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) else {
                break
            }

            let segmentStart = max(start, currentDayStart)
            let segmentEnd = min(end, nextDayStart)

            if segmentEnd > segmentStart {
                let startMinutes = minutesIntoDay(for: segmentStart, calendar: calendar)
                let endMinutes = max(startMinutes + 3,
                                     minutesIntoDay(for: segmentEnd, calendar: calendar))
                results.append(ActionPatternSegment(day: currentDayStart,
                                                    startMinutes: min(startMinutes, 1440),
                                                    endMinutes: min(endMinutes, 1440)))
            }
            currentDayStart = nextDayStart
        }

        return results
    }

    private func minutesIntoDay(for date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double(components.hour ?? 0)
        let minutes = Double(components.minute ?? 0)
        return hours * 60 + minutes
    }

    private func dayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func timeLabel(for minutes: Double) -> String {
        let clamped = max(0, min(minutes, 1440))
        let hour = Int(clamped) / 60
        let minute = Int(clamped) % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func orderedDays(for segments: [ActionPatternSegment], totalDays: Int) -> [Date] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        var axisDays: [Date] = []

        for offset in stride(from: totalDays - 1, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) {
                axisDays.append(day)
            }
        }

        let segmentDays = Set(segments.map { $0.day })

        for segmentDay in segmentDays where !axisDays.contains(segmentDay) {
            axisDays.append(segmentDay)
        }

        return axisDays.sorted()
    }
}

private struct DailyActionMetric: Identifiable {
    let date: Date
    var value: Double

    var id: Date { date }
}

private struct ActionPatternSegment: Identifiable {
    let id = UUID()
    let day: Date
    let startMinutes: Double
    let endMinutes: Double
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
