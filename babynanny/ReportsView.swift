//
//  ReportsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI
import Charts
import UIKit

struct ReportsView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @AppStorage("reports.lastSelectedTab") private var persistedTabIdentifier = ReportsTab.dailySnapshot.persistenceIdentifier
    @State private var selectedTab: ReportsTab = .dailySnapshot
    @State private var calendarSelectedDate = Date()
    @State private var didInitializeTab = false
    @State private var shareItem: ChartShareItem?
    @State private var shareContentWidth: CGFloat = 0
    @State private var highlightedTrendDay: Date?

    var body: some View {
        let state = currentState
        VStack(spacing: 0) {
            tabBar()
            tabHeader()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    tabContent(for: state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .onPreferenceChange(ChartShareContentWidthPreferenceKey.self) { width in
            shareContentWidth = width
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear(perform: initializeTabIfNeeded)
        .onChange(of: profileStore.activeProfile.id) { _, _ in
            resetSelectionForActiveProfile()
        }
        .onChange(of: selectedTab) { _, newValue in
            if case .category = newValue {
                highlightedTrendDay = nil
            }
        }
        .onChange(of: calendarSelectedDate) { _, newValue in
        }
        .sheet(item: $shareItem) { item in
            ChartShareSheet(item: item) { outcome in
                if case .completed = outcome {
                }
                shareItem = nil
            }
        }
    }

    @ViewBuilder
    private func tabContent(for state: ProfileActionState) -> some View {
        switch selectedTab {
        case .dailySnapshot:
            dailySnapshotSection(for: state)
        case .category(_):
            dailyTrendSection(for: state)
            actionPatternSection(for: state)
        case .calendar:
            calendarSection(for: state)
        }
    }

    private func tabHeader() -> some View {
        Text(selectedTab.title)
            .font(.title2)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func dailySnapshotSection(for state: ProfileActionState) -> some View {
        let today = todayActions(for: state)
        let todaySummary = daySummary(for: Date(), state: state)
        statsGrid(for: state, todayActions: today, todaySummary: todaySummary)
    }

    private func tabBar() -> some View {
        let tabs = ReportsTab.allTabs

        return HStack(spacing: 12) {
            ForEach(tabs) { tab in
                let isSelected = tab == selectedTab

                Button {
                    select(tab: tab)
                } label: {
                    Image(systemName: tab.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isSelected ? tab.accentColor : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isSelected ? tab.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: isSelected ? tab.accentColor.opacity(0.18) : Color.clear,
                                radius: isSelected ? 8 : 0,
                                x: 0,
                                y: isSelected ? 4 : 0)
                }
                .buttonStyle(.plain)
                .frame(width: 52, height: 52)
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
    }

    private func select(tab: ReportsTab) {
        guard tab != selectedTab else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedTab = tab
        }

        persistedTabIdentifier = tab.persistenceIdentifier


        if tab.isCalendar {
        }
    }

    private func initializeTabIfNeeded() {
        guard !didInitializeTab else { return }

        if let restoredTab = ReportsTab(restoring: persistedTabIdentifier) {
            selectedTab = restoredTab
        } else {
            selectedTab = defaultTab(for: currentState)
            persistedTabIdentifier = selectedTab.persistenceIdentifier
        }
        calendarSelectedDate = Date()
        didInitializeTab = true
    }

    private func resetSelectionForActiveProfile() {
        didInitializeTab = false
        highlightedTrendDay = nil
        calendarSelectedDate = Date()
        persistedTabIdentifier = ReportsTab.dailySnapshot.persistenceIdentifier
        initializeTabIfNeeded()
    }

    private func statsGrid(for state: ProfileActionState,
                           todayActions: [BabyActionSnapshot],
                           todaySummary: DaySummary) -> some View
    {
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
                         icon: "waterbottle.fill",
                         tint: .orange)

                StatCard(title: L10n.Stats.sleepSessionsTitle,
                         value: "\(todaySleepCount(for: todayActions))",
                         subtitle: L10n.Stats.sleepSessionsSubtitle,
                         icon: "moon.zzz.fill",
                         tint: .purple)
            }

            HStack(spacing: 16) {
                StatCard(title: L10n.Stats.sleepDurationTitle,
                         value: formattedSummaryDuration(todaySummary.sleepDuration),
                         subtitle: L10n.Stats.sleepDurationSubtitle,
                         icon: "clock.fill",
                         tint: .indigo)

                StatCard(title: L10n.Stats.diaperChangesTitle,
                         value: "\(todaySummary.diaperCount)",
                         subtitle: L10n.Stats.diaperChangesSubtitle,
                         icon: BabyActionCategory.diaper.icon,
                         tint: BabyActionCategory.diaper.accentColor)
            }
        }
    }

    private func calendarSection(for state: ProfileActionState) -> some View {
        let summary = daySummary(for: calendarSelectedDate, state: state)
        let formattedDate = calendarSelectedDate.formatted(date: .long, time: .omitted)

        return VStack(alignment: .leading, spacing: 16) {
            reportsCard(spacing: 12) {
                DatePicker(
                    L10n.Stats.calendarDatePickerLabel,
                    selection: $calendarSelectedDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            reportsCard(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Stats.calendarSummaryTitle(formattedDate))
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(L10n.Stats.calendarSummaryCount(summary.totalActions))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                calendarSummaryCards(for: summary)

                if summary.totalActions > 0 {
                    calendarTimeline(for: summary)
                } else {
                    Text(L10n.Stats.calendarEmptyTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func calendarSummaryCards(for summary: DaySummary) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                StatCard(title: L10n.Actions.sleep,
                         value: formattedSummaryDuration(summary.sleepDuration),
                         subtitle: L10n.Stats.calendarSleepSubtitle(summary.sleepSessions),
                         icon: BabyActionCategory.sleep.icon,
                         tint: BabyActionCategory.sleep.accentColor)

                StatCard(title: L10n.Actions.feeding,
                         value: "\(summary.feedingCount)",
                         subtitle: summary.feedingSubtitle,
                         icon: BabyActionCategory.feeding.icon,
                         tint: BabyActionCategory.feeding.accentColor)
            }

            HStack(spacing: 16) {
                StatCard(title: L10n.Actions.diaper,
                         value: "\(summary.diaperCount)",
                         subtitle: L10n.Stats.calendarDiaperSubtitle,
                         icon: BabyActionCategory.diaper.icon,
                         tint: BabyActionCategory.diaper.accentColor)

                StatCard(title: L10n.Stats.calendarTotalTitle,
                         value: "\(summary.totalActions)",
                         subtitle: L10n.Stats.calendarTotalSubtitle,
                         icon: "chart.bar.fill",
                         tint: .indigo)
            }
        }
    }

    private func calendarTimeline(for summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Stats.calendarTimelineTitle)
                .font(.headline)

            ForEach(summary.actions) { action in
                CalendarActionRow(action: action,
                                  dayStart: summary.dayStart,
                                  dayEnd: summary.dayEnd)
            }
        }
    }

    private func reportsCard<Content: View>(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    private func daySummary(for date: Date, state: ProfileActionState) -> DaySummary {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return DaySummary.empty(for: date)
        }

        var seen: Set<UUID> = []
        var actions: [BabyActionSnapshot] = []

        for action in state.history where actionIntersectsDay(action, dayStart: dayStart, dayEnd: dayEnd) {
            if seen.insert(action.id).inserted {
                actions.append(action)
            }
        }

        for action in state.activeActions.values where actionIntersectsDay(action, dayStart: dayStart, dayEnd: dayEnd) {
            if seen.insert(action.id).inserted {
                actions.append(action)
            }
        }

        actions.sort { $0.startDate < $1.startDate }

        var sleepDuration: TimeInterval = 0
        var sleepSessions = 0
        var feedingCount = 0
        var bottleVolume = 0
        var diaperCount = 0

        for action in actions {
            switch action.category {
            case .sleep:
                sleepSessions += 1
                sleepDuration += overlapDuration(for: action, dayStart: dayStart, dayEnd: dayEnd)
            case .feeding:
                feedingCount += 1
                if let volume = action.bottleVolume {
                    bottleVolume += volume
                }
            case .diaper:
                diaperCount += 1
            }
        }

        return DaySummary(date: date,
                          dayStart: dayStart,
                          dayEnd: dayEnd,
                          actions: actions,
                          sleepDuration: sleepDuration,
                          sleepSessions: sleepSessions,
                          feedingCount: feedingCount,
                          bottleVolume: bottleVolume,
                          diaperCount: diaperCount)
    }

    private func actionIntersectsDay(_ action: BabyActionSnapshot, dayStart: Date, dayEnd: Date) -> Bool {
        let actionStart = action.startDate
        let actionEnd = action.endDate ?? Date()

        if actionStart >= dayStart && actionStart < dayEnd {
            return true
        }

        if actionEnd > dayStart && actionEnd <= dayEnd {
            return true
        }

        return actionStart < dayStart && actionEnd > dayStart
    }

    private func overlapDuration(for action: BabyActionSnapshot, dayStart: Date, dayEnd: Date) -> TimeInterval {
        let actionEnd = action.endDate ?? Date()
        let start = max(action.startDate, dayStart)
        let end = min(actionEnd, dayEnd)
        guard end > start else { return 0 }
        return end.timeIntervalSince(start)
    }

    private func formattedSummaryDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return L10n.Stats.calendarDurationZero }
        return summaryDurationFormatter.string(from: duration) ?? L10n.Stats.calendarDurationZero
    }

    @ViewBuilder
    private func dailyTrendSection(for state: ProfileActionState) -> some View {
        let hasAnyTrackedData = !state.history.isEmpty || !state.activeActions.isEmpty

        if hasAnyTrackedData {
            let focusCategory = resolvedCategory(for: state)
            let windowDays = 7
            let rawMetrics = dailyMetrics(for: state, focusCategory: focusCategory, days: windowDays)
            let displayConfiguration = dailyTrendDisplayConfiguration(for: rawMetrics,
                                                                      focusCategory: focusCategory)
            let metrics = displayConfiguration.metrics
            let hasData = metrics.contains { $0.value > 0 }
            let yAxisTitle = displayConfiguration.yAxisTitle
            let axisDays = recentDayStarts(count: windowDays)
            let subtypeTitle = L10n.Stats.subtypeLegend
            let subtypeScale = colorScale(for: metrics.map(\.subtype))
            let aggregates = aggregateDailyTrendMetrics(metrics)
            let valueFormatter = displayConfiguration.valueFormatter

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.Stats.lastSevenDays)
                        .font(.headline)

                    Spacer()

                    if hasData {
                        Button {
                            let context = DailyTrendShareContext(metrics: metrics,
                                                                  yAxisTitle: yAxisTitle,
                                                                  axisDays: axisDays,
                                                                  subtypeTitle: subtypeTitle,
                                                                  subtypeScale: subtypeScale,
                                                                  focusCategory: focusCategory)
                            shareDailyTrendChart(context: context)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Stats.shareChartAccessibility)
                    }
                }

                if hasData {
                    dailyTrendChart(metrics: metrics,
                                     yAxisTitle: yAxisTitle,
                                     axisDays: axisDays,
                                     subtypeTitle: subtypeTitle,
                                     subtypeScale: subtypeScale,
                                     aggregates: aggregates,
                                     selectedDate: $highlightedTrendDay,
                                     valueFormatter: valueFormatter)
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
            .overlay(widthTracker())
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
        let subtypeTitle = L10n.Stats.subtypeLegend
        let subtypeScale = colorScale(for: patternSegments.map(\.subtype))

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Stats.patternTitle)
                        .font(.headline)

                    Text(L10n.Stats.patternSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasData {
                    Button {
                        let context = ActionPatternShareContext(segments: patternSegments,
                                                                dayAxisValues: dayAxisValues,
                                                                subtypeTitle: subtypeTitle,
                                                                subtypeScale: subtypeScale,
                                                                focusCategory: focusCategory)
                        shareActionPatternChart(context: context)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Stats.shareChartAccessibility)
                }
            }

            if hasData {
                actionPatternChart(segments: patternSegments,
                                    dayAxisValues: dayAxisValues,
                                    subtypeTitle: subtypeTitle,
                                    subtypeScale: subtypeScale)
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
        .overlay(widthTracker())
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private func dailyTrendChart(metrics: [DailyActionMetric],
                                 yAxisTitle: String,
                                 axisDays: [Date],
                                 subtypeTitle: String,
                                 subtypeScale: (domain: [String], range: [Color]),
                                 aggregates: [DailyTrendAggregate] = [],
                                 selectedDate: Binding<Date?>? = nil,
                                 valueFormatter: DailyTrendValueFormatter = .minutes) -> some View
    {
        let selectedDay = selectedDate?.wrappedValue

        Chart {
            ForEach(metrics) { metric in
                BarMark(
                    x: .value(L10n.Stats.dayAxisLabel, metric.date, unit: .day),
                    y: .value(yAxisTitle, metric.value)
                )
                .foregroundStyle(by: .value(subtypeTitle, metric.subtype.legendLabel))
                .cornerRadius(6)
                .opacity(opacityForTrendBar(date: metric.date, selectedDate: selectedDay))
            }

            if let selectedDay,
               let aggregate = aggregates.first(where: { $0.date == selectedDay })
            {
                PointMark(
                    x: .value(L10n.Stats.dayAxisLabel, aggregate.date, unit: .day),
                    y: .value(yAxisTitle, aggregate.total)
                )
                .symbolSize(0)
                .opacity(0)
                .annotation(position: .top, alignment: .center) {
                    DailyTrendValueCallout(label: valueFormatter.string(for: aggregate.total))
                }
            }
        }
        .chartForegroundStyleScale(domain: subtypeScale.domain, range: subtypeScale.range)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: axisDays) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let dateValue = value.as(Date.self) {
                        Text(dateValue, format: .dateTime.weekday(.abbreviated))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            if let selectedDate {
                GeometryReader { geo in
                    if let plotFrameAnchor = proxy.plotFrame {
                        let plotFrame = geo[plotFrameAnchor]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        guard plotFrame.contains(value.location) else {
                                            selectedDate.wrappedValue = nil
                                            return
                                        }

                                        let locationX = value.location.x - plotFrame.origin.x
                                        if let tappedDate: Date = proxy.value(atX: locationX, as: Date.self) {
                                            let normalized = Calendar.current.startOfDay(for: tappedDate)
                                            if let nearest = nearestTrendDay(to: normalized,
                                                                             from: aggregates.map(\.date)) {
                                                if nearest == selectedDate.wrappedValue {
                                                    selectedDate.wrappedValue = nil
                                                } else {
                                                    selectedDate.wrappedValue = nearest
                                                }
                                            } else {
                                                selectedDate.wrappedValue = nil
                                            }
                                        } else {
                                            selectedDate.wrappedValue = nil
                                        }
                                    }
                            )
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private func actionPatternChart(segments: [ActionPatternSegment],
                                    dayAxisValues: [Date],
                                    subtypeTitle: String,
                                    subtypeScale: (domain: [String], range: [Color])) -> some View
    {
        Chart(segments) { segment in
            BarMark(
                x: .value(L10n.Stats.dayAxisLabel, segment.day, unit: .day),
                yStart: .value(L10n.Stats.hourAxisLabel, segment.startMinutes),
                yEnd: .value(L10n.Stats.hourAxisLabel, segment.endMinutes)
            )
            .cornerRadius(6)
            .foregroundStyle(by: .value(subtypeTitle, segment.subtype.legendLabel))
        }
        .chartForegroundStyleScale(domain: subtypeScale.domain, range: subtypeScale.range)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
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
        .frame(height: 280)
    }

    private func shareDailyTrendChart(context: DailyTrendShareContext) {
        let chartView = AnyView(
            dailyTrendChart(metrics: context.metrics,
                             yAxisTitle: context.yAxisTitle,
                             axisDays: context.axisDays,
                             subtypeTitle: context.subtypeTitle,
                             subtypeScale: context.subtypeScale)
        )

        renderChartShare(title: L10n.Stats.lastSevenDays,
                          subtitle: context.focusCategory.title,
                          chart: chartView,
                          identifier: "daily_trend")
    }

    private func shareActionPatternChart(context: ActionPatternShareContext) {
        let chartView = AnyView(
            actionPatternChart(segments: context.segments,
                               dayAxisValues: context.dayAxisValues,
                               subtypeTitle: context.subtypeTitle,
                               subtypeScale: context.subtypeScale)
        )

        renderChartShare(title: L10n.Stats.patternTitle,
                          subtitle: context.focusCategory.title,
                          chart: chartView,
                          identifier: "daily_pattern")
    }

    private func renderChartShare(title: String,
                                  subtitle: String?,
                                  chart: AnyView,
                                  identifier: String) {
        let targetWidth = shareContentWidth > 0 ? shareContentWidth : nil
        let snapshot = ChartShareSnapshot(title: title, subtitle: subtitle, targetWidth: targetWidth) {
            chart
        }

        let renderer = ImageRenderer(content: snapshot.environment(\.colorScheme, .light))
        if let targetWidth {
            renderer.proposedSize = ProposedViewSize(width: targetWidth + 48, height: nil)
        }
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else {
            return
        }

        shareItem = ChartShareItem(image: image, chartIdentifier: identifier)
    }

    private func resolvedCategory(for state: ProfileActionState) -> BabyActionCategory {
        switch selectedTab {
        case .dailySnapshot:
            return state.mostRecentAction?.category ?? .sleep
        case .category(let category):
            return category
        case .calendar:
            return state.mostRecentAction?.category ?? .sleep
        }
    }

    private func defaultTab(for _: ProfileActionState) -> ReportsTab {
        .dailySnapshot
    }

    private var currentState: ProfileActionState {
        actionStore.state(for: profileStore.activeProfile.id)
    }

    private func todayActions(for state: ProfileActionState) -> [BabyActionSnapshot] {
        let calendar = Calendar.current
        return state.history.filter { calendar.isDate($0.startDate, inSameDayAs: Date()) }
    }

    private func todayBottleVolume(for actions: [BabyActionSnapshot]) -> Int {
        actions.compactMap { action in
            guard action.category == .feeding, action.feedingType == .bottle else { return nil }
            return action.bottleVolume
        }.reduce(0, +)
    }

    private func todaySleepCount(for actions: [BabyActionSnapshot]) -> Int {
        actions.filter { $0.category == .sleep }.count
    }

    private func dailyMetrics(for state: ProfileActionState,
                              focusCategory: BabyActionCategory,
                              days: Int = 7) -> [DailyActionMetric] {
        let calendar = Calendar.current
        let dayStarts = recentDayStarts(count: days)
        var totals = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, [ActionSubtype: Double]()) })

        for action in state.history where action.category == focusCategory {
            let day = calendar.startOfDay(for: action.startDate)
            guard totals[day] != nil else { continue }

            let increment: Double

            if focusCategory == .diaper {
                increment = 1
            } else {
                let endDate = action.endDate ?? Date()
                let duration = max(0, endDate.timeIntervalSince(action.startDate))
                increment = duration / 60
            }

            for subtype in subtypes(for: action, focusCategory: focusCategory) {
                var bucket = totals[day] ?? [:]
                bucket[subtype, default: 0] += increment
                totals[day] = bucket
            }
        }

        if focusCategory != .diaper,
           let active = state.activeActions[focusCategory] {
            let day = calendar.startOfDay(for: active.startDate)
            if totals[day] != nil {
                let increment = max(0, Date().timeIntervalSince(active.startDate)) / 60

                for subtype in subtypes(for: active, focusCategory: focusCategory) {
                    var bucket = totals[day] ?? [:]
                    bucket[subtype, default: 0] += increment
                    totals[day] = bucket
                }
            }
        }

        return dayStarts.flatMap { day -> [DailyActionMetric] in
            guard let bucket = totals[day] else { return [] }

            return bucket
                .sorted { lhs, rhs in
                    if lhs.key.sortIndex == rhs.key.sortIndex {
                        return lhs.key.legendLabel < rhs.key.legendLabel
                    }
                    return lhs.key.sortIndex < rhs.key.sortIndex
                }
                .map { DailyActionMetric(date: day, subtype: $0.key, value: $0.value) }
        }
    }

    private func aggregateDailyTrendMetrics(_ metrics: [DailyActionMetric]) -> [DailyTrendAggregate] {
        let grouped = Dictionary(grouping: metrics, by: \.date)

        return grouped
            .map { entry in
                DailyTrendAggregate(date: entry.key,
                                    total: entry.value.reduce(0) { partial, metric in partial + metric.value })
            }
            .sorted { $0.date < $1.date }
    }

    private func opacityForTrendBar(date: Date, selectedDate: Date?) -> Double {
        guard let selectedDate else { return 1 }
        return date == selectedDate ? 1 : 0.35
    }

    private func nearestTrendDay(to date: Date, from candidates: [Date]) -> Date? {
        guard !candidates.isEmpty else { return nil }

        return candidates.min { lhs, rhs in
            abs(lhs.timeIntervalSince(date)) < abs(rhs.timeIntervalSince(date))
        }
    }

    private func dailyTrendDisplayConfiguration(for metrics: [DailyActionMetric],
                                                focusCategory: BabyActionCategory)
        -> (metrics: [DailyActionMetric], yAxisTitle: String, valueFormatter: DailyTrendValueFormatter)
    {
        if focusCategory == .diaper {
            return (metrics, L10n.Stats.diapersYAxis, .count)
        }

        guard focusCategory == .sleep || focusCategory == .feeding else {
            return (metrics, L10n.Stats.minutesYAxis, .minutes)
        }

        guard let maxValue = metrics.map(\.value).max(), maxValue > 0 else {
            return (metrics, L10n.Stats.minutesYAxis, .minutes)
        }

        let unit: DailyTrendDurationUnit

        if maxValue < 1 {
            unit = .seconds
        } else if maxValue >= 120 {
            unit = .hours
        } else {
            unit = .minutes
        }

        let scaledMetrics = metrics.map { metric -> DailyActionMetric in
            var metric = metric
            metric.value = unit.scaledValue(fromMinutes: metric.value)
            return metric
        }

        return (scaledMetrics, unit.axisTitle, DailyTrendValueFormatter(unit: unit))
    }

    private func subtypes(for action: BabyActionSnapshot, focusCategory: BabyActionCategory) -> [ActionSubtype] {
        switch focusCategory {
        case .sleep:
            return [.general(.sleep)]
        case .diaper:
            guard let diaperType = action.diaperType else {
                return [.unspecified(.diaper)]
            }

            switch diaperType {
            case .pee:
                return [.diaper(.pee)]
            case .poo:
                return [.diaper(.poo)]
            case .both:
                return [.diaper(.pee), .diaper(.poo)]
            }
        case .feeding:
            guard let feedingType = action.feedingType else {
                return [.unspecified(.feeding)]
            }
            return [.feeding(feedingType)]
        }
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
            let actionSubtypes = subtypes(for: action, focusCategory: focusCategory)

            if focusCategory == .diaper {
                guard action.startDate >= windowStart else { continue }
                let day = calendar.startOfDay(for: action.startDate)
                let minutes = Double(calendar.component(.hour, from: action.startDate) * 60 +
                    calendar.component(.minute, from: action.startDate))
                let endMinutes = min(minutes + 5, 1440)

                for subtype in actionSubtypes {
                    segments.append(ActionPatternSegment(day: day,
                                                         startMinutes: minutes,
                                                         endMinutes: endMinutes,
                                                         subtype: subtype))
                }
            } else {
                let actionStart = max(action.startDate, windowStart)
                let actionEnd = min(action.endDate ?? now, now)

                guard actionEnd > actionStart else { continue }

                for subtype in actionSubtypes {
                    segments.append(contentsOf: splitAction(from: actionStart,
                                                            to: actionEnd,
                                                            calendar: calendar,
                                                            subtype: subtype))
                }
            }
        }

        if focusCategory != .diaper, let active = state.activeActions[focusCategory] {
            let actionStart = max(active.startDate, windowStart)
            let actionEnd = now

            if actionEnd > actionStart {
                let actionSubtypes = subtypes(for: active, focusCategory: focusCategory)
                for subtype in actionSubtypes {
                    segments.append(contentsOf: splitAction(from: actionStart,
                                                            to: actionEnd,
                                                            calendar: calendar,
                                                            subtype: subtype))
                }
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
                              calendar: Calendar,
                              subtype: ActionSubtype) -> [ActionPatternSegment] {
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
                let rawEndMinutes: Double

                if segmentEnd == nextDayStart {
                    rawEndMinutes = 1440
                } else {
                    rawEndMinutes = minutesIntoDay(for: segmentEnd, calendar: calendar)
                }

                let endMinutes = max(startMinutes + 3, rawEndMinutes)
                results.append(ActionPatternSegment(day: currentDayStart,
                                                    startMinutes: min(startMinutes, 1440),
                                                    endMinutes: min(endMinutes, 1440),
                                                    subtype: subtype))
            }
            currentDayStart = nextDayStart
        }

        return results
    }

    private func recentDayStarts(count: Int) -> [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        return (0..<count)
            .compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: startOfToday)
            }
            .sorted()
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

    private func colorScale<S: Sequence>(for subtypes: S) -> (domain: [String], range: [Color])
        where S.Element == ActionSubtype
    {
        var seen: Set<String> = []
        var domain: [String] = []
        var range: [Color] = []

        for subtype in subtypes {
            let label = subtype.legendLabel
            guard !seen.contains(label) else { continue }

            seen.insert(label)
            domain.append(label)
            range.append(subtype.color)
        }

        return (domain, range)
    }
}

private struct DailyTrendShareContext {
    let metrics: [DailyActionMetric]
    let yAxisTitle: String
    let axisDays: [Date]
    let subtypeTitle: String
    let subtypeScale: (domain: [String], range: [Color])
    let focusCategory: BabyActionCategory
}

private struct ActionPatternShareContext {
    let segments: [ActionPatternSegment]
    let dayAxisValues: [Date]
    let subtypeTitle: String
    let subtypeScale: (domain: [String], range: [Color])
    let focusCategory: BabyActionCategory
}

private enum ReportsTab: Hashable, Identifiable {
    case dailySnapshot
    case category(BabyActionCategory)
    case calendar

    var id: String {
        switch self {
        case .dailySnapshot:
            return "daily_snapshot"
        case .category(let category):
            return "category_\(category.rawValue)"
        case .calendar:
            return "calendar"
        }
    }

    var iconName: String {
        switch self {
        case .dailySnapshot:
            return "chart.bar.doc.horizontal.fill"
        case .category(let category):
            return category.icon
        case .calendar:
            return "calendar"
        }
    }

    var accentColor: Color {
        switch self {
        case .dailySnapshot:
            return Color.indigo
        case .category(let category):
            return category.accentColor
        case .calendar:
            return Color.teal
        }
    }

    var analyticsValue: String {
        switch self {
        case .dailySnapshot:
            return "daily_snapshot"
        case .category(let category):
            return category.rawValue
        case .calendar:
            return "calendar"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .dailySnapshot:
            return L10n.Stats.dailySnapshotTitle
        case .category(let category):
            return category.title
        case .calendar:
            return L10n.Stats.calendarTabLabel
        }
    }

    var title: String {
        switch self {
        case .dailySnapshot:
            return L10n.Stats.dailySnapshotTitle
        case .category(let category):
            return category.title
        case .calendar:
            return L10n.Stats.calendarTabLabel
        }
    }

    var isCalendar: Bool {
        if case .calendar = self {
            return true
        }
        return false
    }

    static var allTabs: [ReportsTab] {
        [.dailySnapshot] + BabyActionCategory.allCases.map { ReportsTab.category($0) } + [.calendar]
    }

    var persistenceIdentifier: String {
        id
    }

    init?(restoring identifier: String) {
        if identifier == ReportsTab.dailySnapshot.persistenceIdentifier {
            self = .dailySnapshot
            return
        }

        if identifier == ReportsTab.calendar.persistenceIdentifier {
            self = .calendar
            return
        }

        let categoryPrefix = "category_"
        if identifier.hasPrefix(categoryPrefix) {
            let rawValue = String(identifier.dropFirst(categoryPrefix.count))
            if let category = BabyActionCategory(rawValue: rawValue) {
                self = .category(category)
                return
            }
        }

        return nil
    }
}

private struct ChartShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let chartIdentifier: String
}

private enum ChartShareOutcome: Sendable {
    case completed
    case cancelled
    case failed(Error)
}

private struct ChartShareSheet: UIViewControllerRepresentable {
    let item: ChartShareItem
    let completion: (ChartShareOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [item.image], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in
                if let error {
                    context.coordinator.handle(.failed(error))
                } else if completed {
                    context.coordinator.handle(.completed)
                } else {
                    context.coordinator.handle(.cancelled)
                }
            }
        }

        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
                .first
            if let sourceView = popover.sourceView {
                popover.sourceRect = CGRect(
                    x: sourceView.bounds.midX,
                    y: sourceView.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    final class Coordinator {
        private let completion: (ChartShareOutcome) -> Void

        init(completion: @escaping (ChartShareOutcome) -> Void) {
            self.completion = completion
        }

        func handle(_ outcome: ChartShareOutcome) {
            completion(outcome)
        }
    }
}

private struct ChartShareSnapshot<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    let targetWidth: CGFloat?

    init(title: String, subtitle: String? = nil, targetWidth: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.targetWidth = targetWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: targetWidth, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .padding(16)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
        .overlay(alignment: .bottomTrailing) {
            Text("Nanny & Me")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(16)
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}

private extension ReportsView {
    @ViewBuilder
    func widthTracker() -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ChartShareContentWidthPreferenceKey.self,
                            value: proxy.size.width)
        }
    }
}

private struct ChartShareContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum DailyTrendDurationUnit {
    case seconds
    case minutes
    case hours

    func scaledValue(fromMinutes minutes: Double) -> Double {
        switch self {
        case .seconds:
            return minutes * 60
        case .minutes:
            return minutes
        case .hours:
            return minutes / 60
        }
    }

    var axisTitle: String {
        switch self {
        case .seconds:
            return L10n.Stats.secondsYAxis
        case .minutes:
            return L10n.Stats.minutesYAxis
        case .hours:
            return L10n.Stats.hoursYAxis
        }
    }
}

private enum DailyTrendValueFormatter {
    case count
    case seconds
    case minutes
    case hours

    init(unit: DailyTrendDurationUnit) {
        switch unit {
        case .seconds:
            self = .seconds
        case .minutes:
            self = .minutes
        case .hours:
            self = .hours
        }
    }

    func string(for value: Double) -> String {
        switch self {
        case .count:
            return DailyTrendValueFormatter.countFormatter.string(from: NSNumber(value: value))
                ?? String(Int(round(value)))
        case .seconds:
            return DailyTrendValueFormatter.durationString(from: value, unit: .seconds)
        case .minutes:
            return DailyTrendValueFormatter.durationString(from: value, unit: .minutes)
        case .hours:
            return DailyTrendValueFormatter.durationString(from: value, unit: .hours)
        }
    }

    private static func durationString(from value: Double, unit: DailyTrendDurationUnit) -> String {
        let totalSecondsDouble: Double

        switch unit {
        case .seconds:
            totalSecondsDouble = value
        case .minutes:
            totalSecondsDouble = value * 60
        case .hours:
            totalSecondsDouble = value * 3600
        }

        var totalSeconds = Int(round(totalSecondsDouble))

        let hours = totalSeconds / 3600
        totalSeconds %= 3600
        let minutes = totalSeconds / 60
        totalSeconds %= 60
        let seconds = totalSeconds

        return "\(hours)h \(minutes)m \(seconds)s"
    }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private struct DailyActionMetric: Identifiable {
    let date: Date
    let subtype: ActionSubtype
    var value: Double

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)-\(subtype.id)"
    }
}

private struct DailyTrendAggregate: Identifiable {
    let date: Date
    let total: Double

    var id: Date { date }
}

private struct DailyTrendValueCallout: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(.label))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(.systemBackground).opacity(0.92))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
            )
            .accessibilityLabel(label)
    }
}

private enum ActionSubtype: Hashable {
    case general(BabyActionCategory)
    case diaper(BabyActionSnapshot.DiaperType)
    case feeding(BabyActionSnapshot.FeedingType)
    case unspecified(BabyActionCategory)

    var id: String {
        switch self {
        case .general(let category):
            return "general-\(category.rawValue)"
        case .diaper(let type):
            return "diaper-\(type.rawValue)"
        case .feeding(let type):
            return "feeding-\(type.rawValue)"
        case .unspecified(let category):
            return "unspecified-\(category.rawValue)"
        }
    }

    var legendLabel: String {
        switch self {
        case .general(let category):
            return category.title
        case .diaper(let type):
            return type.title
        case .feeding(let type):
            return type.title
        case .unspecified:
            return L10n.Common.unspecified
        }
    }

    var color: Color {
        switch self {
        case .general(let category):
            return category.accentColor
        case .diaper(let type):
            switch type {
            case .pee:
                return .teal
            case .poo:
                return .brown
            case .both:
                return .mint
            }
        case .feeding(let type):
            switch type {
            case .bottle:
                return .orange
            case .leftBreast:
                return .pink
            case .rightBreast:
                return .purple
            case .meal:
                return .green
            }
        case .unspecified:
            return Color(.systemGray3)
        }
    }

    var sortIndex: Int {
        switch self {
        case .general:
            return 0
        case .diaper(let type):
            return 10 + type.sortIndex
        case .feeding(let type):
            return 20 + type.sortIndex
        case .unspecified:
            return 99
        }
    }
}

private struct ActionPatternSegment: Identifiable {
    let id = UUID()
    let day: Date
    let startMinutes: Double
    let endMinutes: Double
    let subtype: ActionSubtype
}

private struct DaySummary {
    let date: Date
    let dayStart: Date
    let dayEnd: Date
    let actions: [BabyActionSnapshot]
    let sleepDuration: TimeInterval
    let sleepSessions: Int
    let feedingCount: Int
    let bottleVolume: Int
    let diaperCount: Int

    var totalActions: Int { actions.count }

    var feedingSubtitle: String {
        if bottleVolume > 0 {
            return L10n.Stats.calendarFeedingSubtitle(bottleVolume)
        }
        return L10n.Stats.calendarFeedingSubtitleNoBottle
    }

    static func empty(for date: Date) -> DaySummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        return DaySummary(date: date,
                   dayStart: start,
                   dayEnd: end,
                   actions: [],
                   sleepDuration: 0,
                   sleepSessions: 0,
                   feedingCount: 0,
                   bottleVolume: 0,
                   diaperCount: 0)
    }
}

private extension BabyActionSnapshot.DiaperType {
    var sortIndex: Int {
        switch self {
        case .pee:
            return 0
        case .poo:
            return 1
        case .both:
            return 2
        }
    }
}

private extension BabyActionSnapshot.FeedingType {
    var sortIndex: Int {
        switch self {
        case .bottle:
            return 0
        case .leftBreast:
            return 1
        case .rightBreast:
            return 2
        case .meal:
            return 3
        }
    }
}

private struct CalendarActionRow: View {
    let action: BabyActionSnapshot
    let dayStart: Date
    let dayEnd: Date

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(action.category.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: action.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(action.category.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(action.detailDescription)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(calendarTimeRange(for: action, dayStart: dayStart, dayEnd: dayEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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

private func calendarTimeRange(for action: BabyActionSnapshot, dayStart: Date, dayEnd: Date) -> String {
    let intervalStart = max(action.startDate, dayStart)
    let actionEnd = action.endDate ?? Date()
    let intervalEnd = min(actionEnd, dayEnd)

    if intervalEnd <= intervalStart {
        return intervalStart.formatted(summaryTimeFormatStyle)
    }

    return summaryIntervalFormatter.format(intervalStart..<intervalEnd)
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
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile

    var state = ProfileActionState()
    state.activeActions[.sleep] = BabyActionSnapshot(category: .sleep, startDate: Date().addingTimeInterval(-1800))
    let calendar = Calendar.current
    let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()

    state.history = [
        BabyActionSnapshot(category: .sleep,
                   startDate: calendar.date(byAdding: .hour, value: -1, to: yesterday) ?? yesterday,
                   endDate: calendar.date(byAdding: .minute, value: -30, to: yesterday)),
        BabyActionSnapshot(category: .sleep,
                   startDate: calendar.date(byAdding: .hour, value: -2, to: twoDaysAgo) ?? twoDaysAgo,
                   endDate: calendar.date(byAdding: .hour, value: -1, to: twoDaysAgo)),
        BabyActionSnapshot(category: .feeding,
                   startDate: Date().addingTimeInterval(-7200),
                   endDate: Date().addingTimeInterval(-6900),
                   feedingType: .bottle,
                   bottleType: .formula,
                   bottleVolume: 120),
        BabyActionSnapshot(category: .diaper,
                   startDate: Date().addingTimeInterval(-5400),
                   endDate: Date().addingTimeInterval(-5300),
                   diaperType: .both)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return ReportsView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}

private let summaryDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .abbreviated
    formatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
    return formatter
}()

private let summaryIntervalFormatter = Date.IntervalFormatStyle(date: .omitted, time: .shortened)

private let summaryTimeFormatStyle = Date.FormatStyle.dateTime.hour().minute()

private let analyticsDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
