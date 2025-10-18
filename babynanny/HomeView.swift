//
//  HomeView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import Foundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var syncStatusViewModel: SyncStatusViewModel
    @State private var presentedCategory: BabyActionCategory?
    @State private var editingAction: BabyActionSnapshot?
    @State private var pendingStartAction: PendingStartAction?
    @State private var categoryClearedForSheet: BabyActionCategory?
    private let onShowAllLogs: () -> Void

    init(onShowAllLogs: @escaping () -> Void = {}) {
        self.onShowAllLogs = onShowAllLogs
    }

    var body: some View {
        let state = currentState
        let recentHistory = state.latestHistoryEntriesPerCategory()

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection(for: state)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(BabyActionCategory.allCases) { category in
                        ActionCard(
                            category: category,
                            activeAction: state.activeAction(for: category),
                            lastCompleted: state.lastCompletedAction(for: category),
                            onStart: { handleStartTap(for: category) },
                            onStop: { stopAction(for: category) }
                        )
                    }
                }

                if profileStore.showRecentActivityOnHome && !recentHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.Home.recentActivity)
                                .font(.headline)

                            Spacer()

                            Button.phTap(
                                L10n.Home.recentActivityShowAll,
                                event: "home_showAllLogs_button_homeView",
                                properties: ["source": "recent_activity"]
                            ) {
                                onShowAllLogs()
                            }
                            .postHogLabel("home.recentActivity.showAll")
                            .tint(.accentColor)
                        }

                        VStack(spacing: 12) {
                            ForEach(recentHistory) { action in
                                HistoryRow(action: action) { actionToEdit in
                                    editingAction = actionToEdit
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            syncStatusFooter
        }
        .animation(.easeInOut(duration: 0.25), value: syncStatusViewModel.state)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .phScreen("home_screen_homeView", properties: ["tab": "home"])
        .sheet(item: $presentedCategory, onDismiss: {
            categoryClearedForSheet = nil
        }) { category in
            ActionDetailSheet(category: category) { configuration in
                requestStartAction(for: category,
                                   configuration: configuration,
                                   dismissingSheet: true)
            }
        }
        .sheet(item: $editingAction) { action in
            ActionEditSheet(action: action) { updatedAction in
                actionStore.updateAction(for: activeProfileID, action: updatedAction)
                editingAction = nil
            }
        }
        .alert(item: $pendingStartAction) { pending in
            let runningList = ListFormatter.localizedString(byJoining: pending.interruptedActionTitles)
            return Alert(
                title: Text(L10n.Home.interruptionAlertTitle),
                message: Text(L10n.Home.interruptionAlertMessage(pending.category.title, runningList)),
                primaryButton: .destructive(Text(L10n.Home.interruptionAlertConfirm)) {
                    Analytics.capture(
                        "home_confirm_interruption_alert",
                        properties: ["category": pending.category.rawValue]
                    )
                    completePendingStartAction(pending)
                    pendingStartAction = nil
                },
                secondaryButton: .cancel {
                    Analytics.capture(
                        "home_cancel_interruption_alert",
                        properties: ["category": pending.category.rawValue]
                    )
                    pendingStartAction = nil
                }
            )
        }
    }

    private func headerSection(for state: ProfileActionState) -> some View {
        VStack(spacing: 12) {
            ZStack {
                if let recent = state.mostRecentAction {
                    headerCard(for: recent)
                        .id(recent.category)
                        .transition(headerCardTransition)
                } else {
                    Text(L10n.Home.placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }
            }
            .animation(headerCardAnimation, value: state.mostRecentAction?.category)
        }
    }

    private var headerCardTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var headerCardAnimation: Animation {
        .interactiveSpring(response: 0.5, dampingFraction: 0.82, blendDuration: 0.25)
    }

    private func headerCard(for recent: BabyActionSnapshot) -> some View {
        let isRunning = recent.endDate == nil
        let trailingTransition = AnyTransition.move(edge: .trailing)
            .combined(with: .opacity)

        let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: headerCardAlignment(for: recent), spacing: 12) {
                AnimatedActionIcon(
                    systemName: recent.icon,
                    color: recent.category.accentColor
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        headerTitleContent(for: recent)

                        Spacer(minLength: 8)

                        headerCompletionElapsedView(for: recent)
                            .transition(trailingTransition)
                    }
                }

                Spacer(minLength: 12)

                if isRunning {
                    Button.phTap(
                        L10n.Common.stop,
                        event: "home_stop_action_header",
                        properties: ["category": recent.category.rawValue]
                    ) {
                        stopAction(for: recent.category)
                    }
                    .postHogLabel("home.header.stop.\(recent.category.rawValue)")
                    .buttonStyle(.borderedProminent)
                    .tint(recent.category.accentColor)
                    .transition(trailingTransition)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: isRunning)

            headerActiveDurationView(for: recent)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.28), value: isRunning)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            cardShape
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            cardShape
                .stroke(recent.category.accentColor, lineWidth: 2)
        )
        .clipShape(cardShape)
        .contentShape(Rectangle())
        .postHogLabel("home.header.editAction")
        .onTapGesture {
            editingAction = recent
        }
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func headerActiveDurationView(for action: BabyActionSnapshot) -> some View {
        if action.endDate == nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(action.durationDescription(asOf: context.date))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(action.category.accentColor)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func headerCompletionElapsedView(for action: BabyActionSnapshot) -> some View {
        if action.endDate != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let display = action.timeSinceCompletionDescription(asOf: context.date) ?? L10n.Formatter.justNow
                let accessibility = action.timeSinceCompletionAccessibilityDescription(asOf: context.date) ?? display

                Text(display)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel(L10n.Home.lastFinished(accessibility))
            }
        }
    }

    private func headerCardAlignment(for action: BabyActionSnapshot) -> VerticalAlignment {
        action.endDate == nil ? .top : .center
    }

    @ViewBuilder
    private func headerTitleContent(for action: BabyActionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerHeadline(for: action))
                .font(.headline)

            if let subtitle = headerSubtitle(for: action) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerHeadline(for action: BabyActionSnapshot) -> String {
        if action.category == .feeding, action.feedingType == .bottle {
            return action.feedingType?.title ?? action.detailDescription
        }

        return action.detailDescription
    }

    private func headerSubtitle(for action: BabyActionSnapshot) -> String? {
        guard action.category == .feeding, action.feedingType == .bottle else {
            return nil
        }

        var components: [String] = []

        if let bottleTypeTitle = action.bottleType?.title {
            components.append(bottleTypeTitle)
        }

        if let volume = action.bottleVolume {
            components.append(L10n.Home.bottlePresetLabel(volume))
        }

        guard components.isEmpty == false else { return nil }

        return components.joined(separator: " • ")
    }

    private func handleStartTap(for category: BabyActionCategory) {
        switch category {
        case .sleep:
            _ = requestStartAction(for: .sleep,
                                    configuration: .sleep,
                                    dismissingSheet: false)
        case .diaper, .feeding:
            let interruptedTitles = interruptedActionTitles(for: category)

            guard interruptedTitles.isEmpty else {
                pendingStartAction = PendingStartAction(
                    category: category,
                    interruptedActionTitles: interruptedTitles,
                    nextStep: .presentCategorySheet
                )
                return
            }

            presentedCategory = category
        }
    }

    @discardableResult
    private func requestStartAction(for category: BabyActionCategory,
                                    configuration: ActionConfiguration,
                                    dismissingSheet: Bool) -> Bool {
        if category.isInstant {
            startAction(for: category, configuration: configuration)
            return true
        }

        let interruptedTitles = interruptedActionTitles(for: category)
        let shouldBypassWarning = categoryClearedForSheet == category

        guard interruptedTitles.isEmpty || shouldBypassWarning else {
            pendingStartAction = PendingStartAction(
                category: category,
                interruptedActionTitles: interruptedTitles,
                nextStep: .start(configuration: configuration, dismissSheet: dismissingSheet)
            )
            return false
        }

        categoryClearedForSheet = nil
        startAction(for: category, configuration: configuration)
        return true
    }

    private func startAction(for category: BabyActionCategory, configuration: ActionConfiguration) {
        actionStore.startAction(for: activeProfileID,
                                category: category,
                                diaperType: configuration.diaperType,
                                feedingType: configuration.feedingType,
                                bottleType: configuration.bottleType,
                                bottleVolume: configuration.bottleVolume)
    }

    private func stopAction(for category: BabyActionCategory) {
        actionStore.stopAction(for: activeProfileID, category: category)
    }

    private var activeProfileID: UUID {
        profileStore.activeProfile.id
    }

    private var currentState: ProfileActionState {
        actionStore.state(for: activeProfileID)
    }

    @ViewBuilder
    private var syncStatusFooter: some View {
        if let content = syncStatusFooterContent {
            SyncStatusFooterMessage(content: content)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var syncStatusFooterContent: SyncStatusFooterContent? {
        switch syncStatusViewModel.state {
        case .failed:
            return SyncStatusFooterContent(
                title: L10n.Sync.initialSyncFailed,
                detail: syncStatusViewModel.lastError,
                isError: true
            )
        case .finished, .exporting, .idle, .waiting:
            return nil
        case .importing:
            return nil
        }
    }

    private func interruptedActionTitles(for category: BabyActionCategory) -> [String] {
        guard !category.isInstant else { return [] }

        return currentState.activeActions.compactMap { element -> String? in
            let (key, action) = element
            guard !key.isInstant else { return nil }
            return action.detailDescription
        }
    }

    private func completePendingStartAction(_ pending: PendingStartAction) {
        switch pending.nextStep {
        case let .start(configuration, dismissSheet):
            categoryClearedForSheet = nil
            startAction(for: pending.category, configuration: configuration)

            if dismissSheet {
                presentedCategory = nil
            }
        case .presentCategorySheet:
            categoryClearedForSheet = pending.category
            presentedCategory = pending.category
        }
    }
}

private extension HomeView {
    struct SyncStatusFooterContent {
        let title: String
        let detail: String?
        let isError: Bool
    }

    struct SyncStatusFooterMessage: View {
        let content: SyncStatusFooterContent

        var body: some View {
            VStack(spacing: content.detail?.isEmpty == false ? 6 : 0) {
                Text(content.title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(content.isError ? Color.red : Color.primary)

                if let detail = content.detail, detail.isEmpty == false {
                    Text(detail)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(content.isError ? Color.red.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(content.isError ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct ActionCard: View {
    let category: BabyActionCategory
    let activeAction: BabyActionSnapshot?
    let lastCompleted: BabyActionSnapshot?
    let onStart: () -> Void
    let onStop: () -> Void

    private var isActive: Bool { activeAction != nil }

    private var cardAnimation: Animation {
        .interactiveSpring(response: 0.45, dampingFraction: 0.86, blendDuration: 0.2)
    }

    private var cardContentTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    private var iconTransitionID: String {
        activeAction?.icon ?? lastCompleted?.icon ?? category.icon
    }

    var body: some View {
        Button {
            let event = isActive ? "home_stop_action_card" : "home_start_action_card"
            Analytics.capture(
                event,
                properties: [
                    "category": category.rawValue,
                    "is_active": isActive ? "true" : "false"
                ]
            )
            if isActive {
                onStop()
            } else {
                onStart()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)

                VStack(spacing: 10) {
                    ZStack {
                        iconView
                    }
                    .id(iconTransitionID)
                    .transition(cardContentTransition)

                    Text(category.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    detailSection

                    Spacer(minLength: 0)

                    ZStack {
                        Text(callToActionText)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(category.accentColor)
                            .multilineTextAlignment(.center)
                    }
                    .id(callToActionText)
                    .transition(cardContentTransition)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(cardAnimation, value: iconTransitionID)
                .animation(cardAnimation, value: callToActionText)
                .animation(cardAnimation, value: activeAction?.id)
            }
        }
        .postHogLabel("home.actionCard.\(category.rawValue)")
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .animation(cardAnimation, value: isActive)
    }

    private var backgroundColor: Color {
        isActive ? category.accentColor.opacity(0.15) : Color(.systemBackground)
    }

    private var borderColor: Color {
        isActive ? category.accentColor.opacity(0.35) : Color.black.opacity(0.05)
    }

    private var callToActionText: String {
        isActive ? L10n.Common.stop : category.startActionButtonTitle
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(category.accentColor.opacity(isActive ? 0.25 : 0.15))
                .frame(width: 56, height: 56)

            Image(systemName: activeAction?.icon ?? lastCompleted?.icon ?? category.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(category.accentColor)
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        ZStack {
            if let activeAction {
                activeDetailView(for: activeAction)
                    .id(activeAction.id)
                    .transition(cardContentTransition)
            } else {
                Color.clear
                    .frame(height: 0)
                    .transition(.opacity)
            }
        }
        .animation(cardAnimation, value: activeAction?.id)
    }

    private func activeDetailView(for action: BabyActionSnapshot) -> some View {
        VStack(spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(action.durationDescription(asOf: context.date))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .foregroundStyle(category.accentColor)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 2) {
                Text(L10n.Home.startedLabel)
                Text(action.startTimeDescription())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Home.startedAt(action.startTimeDescription()))
        }
    }
}

private struct AnimatedActionIcon: View {
    let systemName: String
    let color: Color

    private let iconDimension: CGFloat = 44

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: iconDimension, height: iconDimension)
    }
}

private struct HistoryRow: View {
    let action: BabyActionSnapshot
    let onEdit: (BabyActionSnapshot) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(action.category.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(action.category.accentColor)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timeInformation = timeAgoDescription(asOf: context.date)
                let durationText = durationDescription(asOf: context.date)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(action.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(timeInformation.display)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }

                    if let detail = detailDescription(for: action) {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let durationText {
                        HStack {
                            Spacer()

                            Text(durationText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(timeInformation: timeInformation,
                                                       durationText: durationText))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEdit(action)
            } label: {
                Label(L10n.Logs.editAction, systemImage: "square.and.pencil")
            }
            .tint(.accentColor)
            .postHogLabel("home.historyRow.edit.leading.\(action.category.rawValue)")
        }
        .swipeActions(edge: .trailing) {
            Button {
                Analytics.capture(
                    "home_edit_recentAction_swipe",
                    properties: ["action_id": action.id.uuidString, "category": action.category.rawValue]
                )
                onEdit(action)
            } label: {
                Label(L10n.Logs.editAction, systemImage: "square.and.pencil")
            }
            .tint(.accentColor)
            .postHogLabel("home.historyRow.edit.trailing.\(action.category.rawValue)")
        }
    }
}

private extension HistoryRow {
    struct TimeInformation {
        let display: String
        let accessibility: String
    }

    func detailDescription(for action: BabyActionSnapshot) -> String? {
        if action.category == .sleep {
            return nil
        }

        return action.detailDescription
    }

    func timeAgoDescription(asOf referenceDate: Date) -> TimeInformation {
        let eventDate = action.endDate ?? action.startDate
        let interval = referenceDate.timeIntervalSince(eventDate)

        if abs(interval) < 1 {
            let value = L10n.Formatter.justNow
            return TimeInformation(display: value, accessibility: value)
        }

        let displayFormatter = RelativeDateTimeFormatter()
        displayFormatter.unitsStyle = .full
        displayFormatter.dateTimeStyle = .named
        let display = displayFormatter.localizedString(for: eventDate, relativeTo: referenceDate)

        let accessibilityFormatter = RelativeDateTimeFormatter()
        accessibilityFormatter.unitsStyle = .full
        accessibilityFormatter.dateTimeStyle = .named
        let accessibility = accessibilityFormatter.localizedString(for: eventDate, relativeTo: referenceDate)

        return TimeInformation(display: display, accessibility: accessibility)
    }

    func durationDescription(asOf referenceDate: Date) -> String? {
        guard !action.category.isInstant else { return nil }
        return L10n.Home.historyDuration(action.durationDescription(asOf: referenceDate))
    }

    func accessibilityLabel(timeInformation: TimeInformation, durationText: String?) -> String {
        guard let durationText else { return timeInformation.accessibility }
        return "\(timeInformation.accessibility), \(durationText)"
    }
}

private struct ActionConfiguration {
    var diaperType: BabyActionSnapshot.DiaperType?
    var feedingType: BabyActionSnapshot.FeedingType?
    var bottleType: BabyActionSnapshot.BottleType?
    var bottleVolume: Int?

    static let sleep = ActionConfiguration(diaperType: nil, feedingType: nil, bottleType: nil, bottleVolume: nil)
}

private struct PendingStartAction: Identifiable {
    enum NextStep {
        case start(configuration: ActionConfiguration, dismissSheet: Bool)
        case presentCategorySheet
    }

    let id = UUID()
    let category: BabyActionCategory
    let interruptedActionTitles: [String]
    let nextStep: NextStep
}

private protocol ActionTypeOption: Identifiable, Hashable {
    var title: String { get }
    var icon: String { get }
}

extension BabyActionSnapshot.DiaperType: ActionTypeOption { }
extension BabyActionSnapshot.FeedingType: ActionTypeOption {
    static var newActionOptions: [BabyActionSnapshot.FeedingType] {
        [.bottle, .meal, .leftBreast, .rightBreast]
    }
}

private struct ActionTypeSelectionGrid<Option: ActionTypeOption>: View {
    let options: [Option]
    @Binding var selection: Option
    let accentColor: Color
    var onOptionActivated: ((Option) -> Void)? = nil
    let postHogLabelPrefix: String

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(options) { option in
                Button {
                    Analytics.capture(
                        "home_select_action_option_sheet",
                        properties: [
                            "category": postHogLabelPrefix,
                            "option_id": String(describing: option.id),
                            "previous_selection": String(describing: selection.id)
                        ]
                    )
                    selection = option
                    onOptionActivated?(option)
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: option.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(selection == option ? Color.white : accentColor)
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(selection == option ? accentColor : accentColor.opacity(0.15))
                            )

                        Text(option.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(selection == option ? accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(selection == option ? accentColor : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .postHogLabel("\(postHogLabelPrefix).\(String(describing: option.id))")
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
    }
}

private enum BottleVolumeOption: Hashable, Identifiable {
    case preset(Int)
    case custom

    static let presets: [BottleVolumeOption] = [.preset(60), .preset(90), .preset(120), .preset(150)]
    static let allOptions: [BottleVolumeOption] = presets + [.custom]

    var id: String {
        switch self {
        case .preset(let value):
            return "preset_\(value)"
        case .custom:
            return "custom"
        }
    }

    var label: String {
        switch self {
        case .preset(let value):
            return L10n.Home.bottlePresetLabel(value)
        case .custom:
            return L10n.Home.customBottleOption
        }
    }
}

struct ActionEditSheet: View {
    let action: BabyActionSnapshot
    let onSave: (BabyActionSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore

    @State private var startDate: Date
    @State private var diaperSelection: BabyActionSnapshot.DiaperType
    @State private var feedingSelection: BabyActionSnapshot.FeedingType
    @State private var bottleTypeSelection: BabyActionSnapshot.BottleType
    @State private var bottleSelection: BottleVolumeOption
    @State private var customBottleVolume: String
    @State private var endDate: Date?

    init(action: BabyActionSnapshot, onSave: @escaping (BabyActionSnapshot) -> Void) {
        self.action = action
        self.onSave = onSave

        _startDate = State(initialValue: action.startDate)
        _diaperSelection = State(initialValue: action.diaperType ?? .pee)
        _feedingSelection = State(initialValue: action.feedingType ?? .bottle)
        _bottleTypeSelection = State(initialValue: action.bottleType ?? .formula)
        _endDate = State(initialValue: action.endDate)

        let defaultSelection: BottleVolumeOption = .preset(120)
        if let volume = action.bottleVolume {
            if BottleVolumeOption.presets.contains(.preset(volume)) {
                _bottleSelection = State(initialValue: .preset(volume))
                _customBottleVolume = State(initialValue: "")
            } else {
                _bottleSelection = State(initialValue: .custom)
                _customBottleVolume = State(initialValue: String(volume))
            }
        } else {
            _bottleSelection = State(initialValue: defaultSelection)
            _customBottleVolume = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                categorySection
                startSection
                diaperSection
                feedingSection
                endSection
                continueSection
                deleteSection
            }
            .navigationTitle(L10n.Home.editActionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .postHogLabel("home.edit.cancel")
                    .phCaptureTap(
                        event: "home_edit_cancel_toolbar",
                        properties: actionAnalyticsProperties
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        save()
                    }
                    .postHogLabel("home.edit.save")
                    .phCaptureTap(
                        event: "home_edit_save_toolbar",
                        properties: actionAnalyticsProperties
                    )
                    .disabled(isSaveDisabled)
                }
            }
        }
        .phScreen(
            "home_edit_sheet_actionEditSheet",
            properties: screenAnalyticsProperties
        )
        .onChange(of: startDate) { _, newValue in
            guard let currentEndDate = endDate else { return }
            if currentEndDate < newValue {
                endDate = newValue
            }
        }
    }

    private var actionAnalyticsProperties: [String: String] {
        [
            "action_id": action.id.uuidString,
            "category": action.category.rawValue
        ]
    }

    private var screenAnalyticsProperties: [String: String] {
        [
            "category": action.category.rawValue
        ]
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            HStack {
                Spacer()
                Image(systemName: currentIconName)
                    .font(.title2)
                    .foregroundStyle(action.category.accentColor)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private var categorySection: some View {
        Section(header: Text(L10n.Home.editCategoryLabel)) {
            Text(action.category.title)
        }
    }

    private var startSection: some View {
        Section(header: Text(L10n.Home.editStartSectionTitle)) {
            DatePicker(
                L10n.Home.editStartPickerLabel,
                selection: $startDate,
                in: startDateRange,
                displayedComponents: [.date, .hourAndMinute]
            )
            .postHogLabel("home.edit.startDate")
        }
    }

    @ViewBuilder
    private var diaperSection: some View {
        if action.category == .diaper {
            Section(header: Text(L10n.Home.diaperTypeSectionTitle)) {
                Picker(selection: $diaperSelection) {
                    ForEach(BabyActionSnapshot.DiaperType.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text(L10n.Home.diaperTypePickerLabel)
                }
                .postHogLabel("home.edit.diaperType")
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var feedingSection: some View {
        if action.category == .feeding {
            Section(header: Text(L10n.Home.feedingTypeSectionTitle)) {
                Picker(selection: $feedingSelection) {
                    ForEach(BabyActionSnapshot.FeedingType.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text(L10n.Home.feedingTypePickerLabel)
                }
                .postHogLabel("home.edit.feedingType")
                .pickerStyle(.segmented)
            }

            if feedingSelection == .bottle {
                bottleTypeSection
                bottleVolumeSection
            }
        }
    }

    private var bottleTypeSection: some View {
        Section(header: Text(L10n.Home.bottleTypeSectionTitle)) {
            Picker(selection: $bottleTypeSelection) {
                ForEach(BabyActionSnapshot.BottleType.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Text(L10n.Home.bottleTypePickerLabel)
            }
            .postHogLabel("home.edit.bottleType")
            .pickerStyle(.segmented)
        }
    }

    private var bottleVolumeSection: some View {
        Section(header: Text(L10n.Home.bottleVolumeSectionTitle)) {
            Picker(selection: $bottleSelection) {
                ForEach(BottleVolumeOption.presets) { option in
                    Text(option.label).tag(option)
                }
                Text(BottleVolumeOption.custom.label).tag(BottleVolumeOption.custom)
            } label: {
                Text(L10n.Home.bottleVolumePickerLabel)
            }
            .postHogLabel("home.edit.bottleVolume")
            .pickerStyle(.segmented)

            if bottleSelection == .custom {
                TextField(L10n.Home.customVolumeFieldPlaceholder, text: $customBottleVolume)
                    .keyboardType(.numberPad)
                    .postHogLabel("home.edit.customBottleVolume")
            }
        }
    }

    @ViewBuilder
    private var endSection: some View {
        if !action.category.isInstant {
            if (endDate ?? action.endDate) != nil {
                Section(header: Text(L10n.Home.editEndSectionTitle)) {
                    DatePicker(
                        L10n.Home.editEndPickerLabel,
                        selection: endDateBinding,
                        in: endDateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .postHogLabel("home.edit.endDate")
                }
            } else {
                Section(header: Text(L10n.Home.editEndSectionTitle)) {
                    Text(L10n.Home.editEndNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        if canContinueAction {
            Section(
                footer: Text(L10n.Logs.continueActionInfo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            ) {
                Button(action: continueAction) {
                    Label(L10n.Logs.continueAction, systemImage: "play.fill")
                }
                .postHogLabel("home.edit.continue")
                .phCaptureTap(
                    event: "home_edit_continue_button",
                    properties: actionAnalyticsProperties
                )
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive, action: deleteAction) {
                Label(L10n.Logs.deleteAction, systemImage: "trash")
            }
            .postHogLabel("home.edit.delete")
            .phCaptureTap(
                event: "home_edit_delete_button",
                properties: actionAnalyticsProperties
            )
        }
    }

    private var currentIconName: String {
        switch action.category {
        case .diaper:
            return diaperSelection.icon
        case .feeding:
            return feedingSelection.icon
        case .sleep:
            return action.category.icon
        }
    }

    private var startDateRange: ClosedRange<Date> {
        let proposedUpperBound = (endDate ?? action.endDate) ?? Date()
        let upperBound = max(startDate, proposedUpperBound)
        return Date.distantPast...upperBound
    }

    private var endDateRange: ClosedRange<Date> {
        startDate...Date.distantFuture
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { endDate ?? action.endDate ?? Date() },
            set: { endDate = $0 }
        )
    }

    private var resolvedBottleVolume: Int? {
        switch bottleSelection {
        case .preset(let value):
            return value
        case .custom:
            let trimmed = customBottleVolume.trimmingCharacters(in: .whitespaces)
            guard let value = Int(trimmed), value > 0 else { return nil }
            return value
        }
    }

    private var isSaveDisabled: Bool {
        if action.category == .feeding && feedingSelection.requiresVolume {
            return resolvedBottleVolume == nil
        }
        return false
    }

    private var canContinueAction: Bool {
        actionStore.canContinueAction(for: profileStore.activeProfile.id, actionID: action.id)
    }

    private func save() {
        let updated = makeUpdatedAction(removingEndDate: false)
        onSave(updated)
        dismiss()
    }

    private func continueAction() {
        let updated = makeUpdatedAction(removingEndDate: true)
        onSave(updated)
        actionStore.continueAction(for: profileStore.activeProfile.id, actionID: updated.id)
        dismiss()
    }

    private func deleteAction() {
        actionStore.deleteAction(for: profileStore.activeProfile.id, actionID: action.id)
        dismiss()
    }

    private func makeUpdatedAction(removingEndDate: Bool) -> BabyActionSnapshot {
        var updated = action
        updated.startDate = startDate

        switch action.category {
        case .sleep:
            break
        case .diaper:
            updated.diaperType = diaperSelection
        case .feeding:
            updated.feedingType = feedingSelection
            updated.bottleType = feedingSelection == .bottle ? bottleTypeSelection : nil
            updated.bottleVolume = feedingSelection.requiresVolume ? resolvedBottleVolume : nil
        }

        if removingEndDate {
            updated.endDate = nil
        } else {
            updated.endDate = endDate ?? action.endDate
        }

        return updated.withValidatedDates()
    }
}
private struct ActionDetailSheet: View {
    let category: BabyActionCategory
    let onStart: (ActionConfiguration) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var diaperSelection: BabyActionSnapshot.DiaperType = .pee
    @State private var feedingSelection: BabyActionSnapshot.FeedingType = .bottle
    @State private var bottleTypeSelection: BabyActionSnapshot.BottleType = .formula
    @State private var bottleSelection: BottleVolumeOption = .preset(120)
    @State private var customBottleVolume: String = ""

    var body: some View {
        NavigationStack {
            Form {
                switch category {
                case .sleep:
                    Section {
                        Text(L10n.Home.sleepInfo)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }

                case .diaper:
                    Section {
                        ActionTypeSelectionGrid(
                            options: BabyActionSnapshot.DiaperType.allCases,
                            selection: $diaperSelection,
                            accentColor: category.accentColor,
                            onOptionActivated: { _ in
                                startIfReady()
                            },
                            postHogLabelPrefix: "home.detail.diaperType"
                        )
                    } header: {
                        Text(L10n.Home.diaperTypeSectionTitle)
                    }

                case .feeding:
                    Section {
                        ActionTypeSelectionGrid(
                            options: BabyActionSnapshot.FeedingType.newActionOptions,
                            selection: $feedingSelection,
                            accentColor: category.accentColor,
                            onOptionActivated: { _ in
                                startIfReady()
                            },
                            postHogLabelPrefix: "home.detail.feedingType"
                        )
                    } header: {
                        Text(L10n.Home.feedingTypeSectionTitle)
                    }

                    if feedingSelection == .bottle {
                        Section {
                            Picker(selection: $bottleTypeSelection) {
                                ForEach(BabyActionSnapshot.BottleType.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            } label: {
                                Text(L10n.Home.bottleTypePickerLabel)
                            }
                            .postHogLabel("home.detail.bottleType")
                            .pickerStyle(.segmented)
                        } header: {
                            Text(L10n.Home.bottleTypeSectionTitle)
                        }
                    }

                    if feedingSelection.requiresVolume {
                        Section {
                            Picker(selection: $bottleSelection) {
                                ForEach(BottleVolumeOption.allOptions) { option in
                                    Text(option.label).tag(option)
                                }
                            } label: {
                                Text(L10n.Home.bottleVolumePickerLabel)
                            }
                            .postHogLabel("home.detail.bottleVolume")
                            .pickerStyle(.segmented)

                            if bottleSelection == .custom {
                                TextField(L10n.Home.customVolumeFieldPlaceholder, text: $customBottleVolume)
                                    .keyboardType(.numberPad)
                                    .postHogLabel("home.detail.customBottleVolume")
                            }
                        } header: {
                            Text(L10n.Home.bottleVolumeSectionTitle)
                        }
                    }
                }
            }
            .navigationTitle(L10n.Home.newActionTitle(category.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .postHogLabel("home.detail.cancel")
                    .phCaptureTap(
                        event: "home_detail_cancel_toolbar",
                        properties: ["category": category.rawValue]
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(category.startActionButtonTitle) {
                        startIfReady()
                    }
                    .postHogLabel("home.detail.start")
                    .phCaptureTap(
                        event: "home_detail_start_toolbar",
                        properties: ["category": category.rawValue]
                    )
                    .disabled(isStartDisabled)
                }
            }
        }
        .phScreen(
            "home_detail_sheet_actionDetailSheet",
            properties: ["category": category.rawValue]
        )
    }

    private var configuration: ActionConfiguration {
        switch category {
        case .sleep:
            return ActionConfiguration(diaperType: nil, feedingType: nil, bottleType: nil, bottleVolume: nil)
        case .diaper:
            return ActionConfiguration(diaperType: diaperSelection, feedingType: nil, bottleType: nil, bottleVolume: nil)
        case .feeding:
            let volume = feedingSelection.requiresVolume ? resolvedBottleVolume : nil
            let bottleType = feedingSelection == .bottle ? bottleTypeSelection : nil
            return ActionConfiguration(diaperType: nil, feedingType: feedingSelection, bottleType: bottleType, bottleVolume: volume)
        }
    }

    private func startIfReady() {
        guard isStartDisabled == false else { return }
        let didStart = onStart(configuration)

        if didStart {
            dismiss()
        }
    }

    private var isStartDisabled: Bool {
        if category == .feeding && feedingSelection.requiresVolume {
            return resolvedBottleVolume == nil
        }
        return false
    }

    private var resolvedBottleVolume: Int? {
        switch bottleSelection {
        case .preset(let value):
            return value
        case .custom:
            let trimmed = customBottleVolume.trimmingCharacters(in: .whitespaces)
            guard let value = Int(trimmed), value > 0 else { return nil }
            return value
        }
    }

}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(initialProfiles: [profile], activeProfileID: profile.id, directory: FileManager.default.temporaryDirectory, filename: "previewHomeProfiles.json")

    var state = ProfileActionState()
    state.activeActions[.sleep] = BabyActionSnapshot(category: .sleep, startDate: Date().addingTimeInterval(-1200))
    state.history = [
        BabyActionSnapshot(category: .feeding, startDate: Date().addingTimeInterval(-5400), endDate: Date().addingTimeInterval(-5100), feedingType: .bottle, bottleType: .formula, bottleVolume: 110),
        BabyActionSnapshot(category: .diaper, startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-3500), diaperType: .pee)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return HomeView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}
