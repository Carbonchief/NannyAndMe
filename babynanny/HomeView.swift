//
//  HomeView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import Foundation
import SwiftUI
import UIKit

private let customReminderDelayStep: TimeInterval = 5 * 60

struct HomeView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.openURL) private var openURL
    @AppStorage("trackActionLocations") private var trackActionLocations = false
    @State private var presentedCategory: BabyActionCategory?
    @State private var editingAction: BabyActionSnapshot?
    @State private var activeAlert: HomeAlert?
    @State private var categoryClearedForSheet: BabyActionCategory?
    @State private var throttledCategories: Set<BabyActionCategory> = []
    @State private var reminderPrompt: ReminderPromptState?
    @State private var recentActionDetail: RecentActionDetailState?
    private let onShowAllLogs: () -> Void

    init(onShowAllLogs: @escaping () -> Void = {}) {
        self.onShowAllLogs = onShowAllLogs
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(referenceDate: context.date)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            ActionEditSheet(
                action: action,
                showsContinueButton: action.category != .diaper
            ) { updatedAction in
                actionStore.updateAction(for: activeProfileID, action: updatedAction)
                editingAction = nil
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case let .pendingStart(pending):
                let runningList = ListFormatter.localizedString(byJoining: pending.interruptedActionTitles)
                return Alert(
                    title: Text(L10n.Home.interruptionAlertTitle),
                    message: Text(L10n.Home.interruptionAlertMessage(pending.category.title, runningList)),
                    primaryButton: .destructive(Text(L10n.Home.interruptionAlertConfirm)) {
                        completePendingStartAction(pending)
                        activeAlert = nil
                    },
                    secondaryButton: .cancel {
                        activeAlert = nil
                    }
                )
            case .reminderAuthorization:
                return Alert(
                    title: Text(L10n.Home.customReminderNotificationsDeniedTitle),
                    message: Text(L10n.Home.customReminderNotificationsDeniedMessage),
                    primaryButton: .default(Text(L10n.Home.customReminderNotificationsDeniedSettings)) {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settingsURL)
                        }
                        activeAlert = nil
                    },
                    secondaryButton: .cancel(Text(L10n.Home.customReminderNotificationsDeniedCancel)) {
                        activeAlert = nil
                    }
                )
            }
        }
        .disabled(reminderPrompt != nil || recentActionDetail != nil)
        .overlay {
            ActionReminderDelayDialogOverlay(
                prompt: $reminderPrompt,
                delayRange: ProfileStore.customReminderDelayRange,
                onConfirm: { prompt, selectedDelay in
                    scheduleReminder(for: prompt, delay: selectedDelay)
                },
                onCancel: { prompt in
                }
            )
        }
        .overlay {
            RecentActionDetailDialogOverlay(detailState: $recentActionDetail) { actionToEdit in
                editingAction = actionToEdit
            }
        }
        .animation(.easeInOut(duration: 0.25), value: reminderPrompt != nil)
        .animation(.easeInOut(duration: 0.25), value: recentActionDetail != nil)
    }

    @ViewBuilder
    private func content(referenceDate: Date) -> some View {
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
                            isInteractionDisabled: throttledCategories.contains(category),
                            onStart: { handleStartTap(for: category) },
                            onStop: { handleStopTap(for: category) },
                            onLongPress: { handleReminderLongPress(for: category) }
                        )
                    }
                }

                if profileStore.showRecentActivityOnHome && !recentHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.Home.recentActivity)
                                .font(.headline)

                            Spacer()

                            Button(L10n.Home.recentActivityShowAll) {
                                onShowAllLogs()
                            }
                            .tint(.accentColor)
                        }

                        VStack(spacing: 12) {
                            ForEach(recentHistory) { action in
                                HistoryRow(
                                    action: action,
                                    onEdit: { actionToEdit in
                                        editingAction = actionToEdit
                                    },
                                    onLongPress: { pressedAction in
                                        handleHistoryLongPress(for: pressedAction)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await actionStore.performUserInitiatedRefresh()
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
            HStack(alignment: .center, spacing: 12) {
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
                    Button(L10n.Common.stop) {
                        _ = handleStopTap(for: recent.category)
                    }
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

    @discardableResult
    private func handleStartTap(for category: BabyActionCategory) -> Bool {
        guard registerCardInteraction(for: category) else { return false }

        switch category {
        case .sleep:
            _ = requestStartAction(for: .sleep,
                                    configuration: .sleep,
                                    dismissingSheet: false)
        case .diaper, .feeding:
            let interruptedTitles = interruptedActionTitles(for: category)

            guard interruptedTitles.isEmpty else {
                let pendingAction = PendingStartAction(
                    category: category,
                    interruptedActionTitles: interruptedTitles,
                    nextStep: .presentCategorySheet
                )
                activeAlert = .pendingStart(pendingAction)
                return false
            }

            presentedCategory = category
        }

        return true
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
            let pendingAction = PendingStartAction(
                category: category,
                interruptedActionTitles: interruptedTitles,
                nextStep: .start(configuration: configuration, dismissSheet: dismissingSheet)
            )
            activeAlert = .pendingStart(pendingAction)
            return false
        }

        categoryClearedForSheet = nil
        startAction(for: category, configuration: configuration)
        return true
    }

    private func startAction(for category: BabyActionCategory, configuration: ActionConfiguration) {
        let shouldCaptureLocation = trackActionLocations && locationManager.isAuthorizedForUse

        let start = {
            actionStore.startAction(for: activeProfileID,
                                    category: category,
                                    diaperType: configuration.diaperType,
                                    feedingType: configuration.feedingType,
                                    bottleType: configuration.bottleType,
                                    bottleVolume: configuration.bottleVolume,
                                    location: nil)
        }

        guard shouldCaptureLocation else {
            start()
            return
        }

        Task { @MainActor in
            let capturedLocation = await locationManager.captureCurrentLocation()
            let loggedLocation = capturedLocation.map { capture in
                ActionLogStore.LoggedLocation(
                    latitude: capture.coordinate.latitude,
                    longitude: capture.coordinate.longitude,
                    placename: capture.placename
                )
            }

            actionStore.startAction(for: activeProfileID,
                                    category: category,
                                    diaperType: configuration.diaperType,
                                    feedingType: configuration.feedingType,
                                    bottleType: configuration.bottleType,
                                    bottleVolume: configuration.bottleVolume,
                                    location: loggedLocation)
        }
    }

    private func stopAction(for category: BabyActionCategory) {
        actionStore.stopAction(for: activeProfileID, category: category)
    }

    @discardableResult
    private func handleStopTap(for category: BabyActionCategory) -> Bool {
        guard registerCardInteraction(for: category) else { return false }

        stopAction(for: category)
        return true
    }

    private func handleReminderLongPress(for category: BabyActionCategory) {

        Task { @MainActor in
            let isAuthorized = await profileStore.ensureNotificationAuthorization()
            if isAuthorized {
                showReminderDialog(for: category)
            } else {
                activeAlert = .reminderAuthorization(ReminderAuthorizationAlert(category: category))
            }
        }
    }

    private func showReminderDialog(for category: BabyActionCategory) {
        let activeProfile = profileStore.activeProfile
        let initialDelay = defaultReminderDelay(for: category)
        reminderPrompt = ReminderPromptState(
            profileID: activeProfile.id,
            profileName: activeProfile.displayName,
            category: category,
            initialDelay: initialDelay
        )

    }

    private func handleHistoryLongPress(for action: BabyActionSnapshot) {
        guard recentActionDetail == nil,
              let completedAction = mostRecentCompletedAction(from: action) else { return }


        withAnimation(.easeInOut(duration: 0.2)) {
            recentActionDetail = RecentActionDetailState(action: completedAction)
        }
    }

    private func mostRecentCompletedAction(from action: BabyActionSnapshot) -> BabyActionSnapshot? {
        if action.endDate != nil {
            return action
        }

        return currentState.history.first { snapshot in
            snapshot.category == action.category && snapshot.endDate != nil
        }
    }

    private func scheduleReminder(for prompt: ReminderPromptState,
                                  delay: TimeInterval) {
        let clampedDelay = clampReminderDelay(delay)
        profileStore.scheduleCustomActionReminder(for: prompt.profileID,
                                                  category: prompt.category,
                                                  delay: clampedDelay,
                                                  isOneOff: true)

    }

    private func defaultReminderDelay(for category: BabyActionCategory) -> TimeInterval {
        clampReminderDelay(profileStore.activeProfile.reminderInterval(for: category))
    }

    private func clampReminderDelay(_ delay: TimeInterval) -> TimeInterval {
        let range = ProfileStore.customReminderDelayRange
        return min(max(delay, range.lowerBound), range.upperBound)
    }

    private var activeProfileID: UUID {
        profileStore.activeProfile.id
    }

    private var currentState: ProfileActionState {
        actionStore.state(for: activeProfileID)
    }

    @MainActor
    private func registerCardInteraction(for category: BabyActionCategory) -> Bool {
        guard throttledCategories.contains(category) == false else { return false }

        throttledCategories.insert(category)

        Task { @MainActor [category] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            throttledCategories.remove(category)
        }

        return true
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

private struct ReminderPromptState: Identifiable {
    let id = UUID()
    let profileID: UUID
    let profileName: String
    let category: BabyActionCategory
    let initialDelay: TimeInterval
}

private struct ReminderAuthorizationAlert: Identifiable {
    let id = UUID()
    let category: BabyActionCategory
}

private struct RecentActionDetailState: Identifiable {
    let id = UUID()
    let action: BabyActionSnapshot
}

private struct ActionReminderDelayDialogOverlay: View {
    @Binding var prompt: ReminderPromptState?
    let delayRange: ClosedRange<TimeInterval>
    let onConfirm: (ReminderPromptState, TimeInterval) -> Void
    let onCancel: (ReminderPromptState) -> Void

    var body: some View {
        Group {
            if let activePrompt = prompt {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ActionReminderDelayDialog(
                        profileName: activePrompt.profileName,
                        category: activePrompt.category,
                        initialDelay: activePrompt.initialDelay,
                        delayRange: delayRange
                    ) { selectedDelay in
                        onConfirm(activePrompt, selectedDelay)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            prompt = nil
                        }
                    } onCancel: {
                        onCancel(activePrompt)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            prompt = nil
                        }
                    }
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

private struct ActionReminderDelayDialog: View {
    let profileName: String
    let category: BabyActionCategory
    let delayRange: ClosedRange<TimeInterval>
    let onConfirm: (TimeInterval) -> Void
    let onCancel: () -> Void

    @State private var selectedDelay: TimeInterval

    init(profileName: String,
         category: BabyActionCategory,
         initialDelay: TimeInterval,
         delayRange: ClosedRange<TimeInterval>,
         onConfirm: @escaping (TimeInterval) -> Void,
         onCancel: @escaping () -> Void) {
        self.profileName = profileName
        self.category = category
        self.delayRange = delayRange
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedDelay = State(initialValue: Self.normalizedDelay(initialDelay, within: delayRange))
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(L10n.Home.customReminderTitle)
                    .font(.headline)

                Text(L10n.Home.customReminderMessage(for: profileName, category: category))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Text(L10n.Home.customReminderDelayLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                CountdownDialer(delay: $selectedDelay, delayRange: delayRange)
                    .frame(height: 216)
            }

            HStack(spacing: 16) {
                Button(L10n.Common.cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button(L10n.Home.customReminderSchedule) {
                    let selected = Self.normalizedDelay(selectedDelay, within: delayRange)
                    onConfirm(selected)
                }
                .buttonStyle(.borderedProminent)
                .tint(category.accentColor)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(category.accentColor, lineWidth: 1)
        )
    }

    static func normalizedDelay(_ delay: TimeInterval,
                                within range: ClosedRange<TimeInterval>) -> TimeInterval {
        let clamped = min(max(delay, range.lowerBound), range.upperBound)
        let stepped = (clamped / customReminderDelayStep).rounded() * customReminderDelayStep
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    @MainActor
    private struct CountdownDialer: UIViewRepresentable {
        @Binding var delay: TimeInterval
        let delayRange: ClosedRange<TimeInterval>

        func makeUIView(context: Context) -> UIDatePicker {
            let picker = UIDatePicker()
            picker.datePickerMode = .countDownTimer
            picker.minuteInterval = max(1, Int(customReminderDelayStep / 60))
            picker.countDownDuration = ActionReminderDelayDialog.normalizedDelay(delay,
                                                                                  within: delayRange)
            picker.addTarget(context.coordinator,
                             action: #selector(Coordinator.valueChanged(_:)),
                             for: .valueChanged)
            return picker
        }

        func updateUIView(_ uiView: UIDatePicker, context: Context) {
            let normalized = ActionReminderDelayDialog.normalizedDelay(delay, within: delayRange)
            if abs(uiView.countDownDuration - normalized) > 0.5 {
                uiView.countDownDuration = normalized
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        @MainActor
        final class Coordinator: NSObject {
            private let parent: CountdownDialer

            init(parent: CountdownDialer) {
                self.parent = parent
            }

            @objc
            func valueChanged(_ sender: UIDatePicker) {
                let normalized = ActionReminderDelayDialog.normalizedDelay(sender.countDownDuration,
                                                                           within: parent.delayRange)
                if abs(normalized - sender.countDownDuration) > 0.5 {
                    sender.countDownDuration = normalized
                }
                parent.delay = normalized
            }
        }
    }
}

private struct ActionCard: View {
    let category: BabyActionCategory
    let activeAction: BabyActionSnapshot?
    let lastCompleted: BabyActionSnapshot?
    let isInteractionDisabled: Bool
    let onStart: () -> Bool
    let onStop: () -> Bool
    let onLongPress: () -> Void

    @State private var didTriggerLongPress = false

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
            defer { didTriggerLongPress = false }

            if didTriggerLongPress {
                return
            }

            if isActive {
                if onStop() {
                }
            } else {
                if onStart() {
                }
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
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                guard isInteractionDisabled == false else { return }
                didTriggerLongPress = true
                onLongPress()
            }
        )
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

private struct RecentActionDetailDialogOverlay: View {
    @Binding var detailState: RecentActionDetailState?
    let onEdit: (BabyActionSnapshot) -> Void

    var body: some View {
        Group {
            if let detailState {
                let action = detailState.action

                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    RecentActionDetailDialog(
                        action: action,
                        onDone: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.detailState = nil
                            }
                        },
                        onEdit: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.detailState = nil
                            }
                            onEdit(action)
                        }
                    )
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(1)
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

private struct RecentActionDetailDialog: View {
    let action: BabyActionSnapshot
    let onDone: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(action.category.accentColor.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Image(systemName: action.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(action.category.accentColor)
                }

                Text(action.title)
                    .font(.headline)

                if let detailText = detailText {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(detailRows) { row in
                    RecentActionDetailRow(label: row.label, value: row.value)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button(L10n.Common.done) {
                    onDone()
                }
                .buttonStyle(.bordered)

                Button(L10n.Logs.editAction) {
                    onEdit()
                }
                .buttonStyle(.borderedProminent)
                .tint(action.category.accentColor)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(action.category.accentColor, lineWidth: 1)
        )
    }

    private var detailText: String? {
        let description = action.detailDescription
        return description == action.title ? nil : description
    }

    private var detailRows: [DetailRowData] {
        var rows: [DetailRowData] = []
        rows.append(
            DetailRowData(
                label: L10n.Home.historyStartedLabel,
                value: formattedDateTime(for: action.startDate)
            )
        )

        if let endDate = action.endDate {
            rows.append(
                DetailRowData(
                    label: L10n.Home.historyStoppedLabel,
                    value: formattedDateTime(for: endDate)
                )
            )
        }

        if action.category != .diaper {
            rows.append(
                DetailRowData(
                    label: L10n.Home.historyDurationLabel,
                    value: action.durationDescription()
                )
            )
        }

        switch action.category {
        case .sleep:
            break
        case .diaper:
            if let diaperType = action.diaperType {
                rows.append(
                    DetailRowData(
                        label: L10n.Home.diaperTypeSectionTitle,
                        value: diaperType.title
                    )
                )
            }
        case .feeding:
            if let feedingType = action.feedingType {
                rows.append(
                    DetailRowData(
                        label: L10n.Home.feedingTypeSectionTitle,
                        value: feedingType.title
                    )
                )

                if feedingType == .bottle {
                    if let bottleType = action.bottleType {
                        rows.append(
                            DetailRowData(
                                label: L10n.Home.bottleTypeSectionTitle,
                                value: bottleType.title
                            )
                        )
                    }

                    if let bottleVolume = action.bottleVolume {
                        rows.append(
                            DetailRowData(
                                label: L10n.Home.bottleVolumeSectionTitle,
                                value: L10n.Home.bottlePresetLabel(bottleVolume)
                            )
                        )
                    }
                }
            }
        }

        return rows
    }

    private func formattedDateTime(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return BabyActionFormatter.shared.format(time24Hour: date)
        }

        return BabyActionFormatter.shared.format(dateTime: date)
    }

    private struct DetailRowData: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }
}

private struct RecentActionDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let onLongPress: (BabyActionSnapshot) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(action.category.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(action.category.accentColor)
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                let timeInformation = timeAgoDescription(asOf: context.date)
                let durationText = durationDescription(asOf: context.date)
                let detail = detailDescription(for: action)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(timeInformation.display)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()

                        if let durationText {
                            Text(durationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(timeInformation: timeInformation,
                                                       durationText: durationText))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 60, alignment: .center)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6) {
            onLongPress(action)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEdit(action)
            } label: {
                Label(L10n.Logs.editAction, systemImage: "square.and.pencil")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button {
                onEdit(action)
            } label: {
                Label(L10n.Logs.editAction, systemImage: "square.and.pencil")
            }
            .tint(.accentColor)
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

        guard interval >= 0 else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            formatter.dateTimeStyle = .named
            let value = formatter.localizedString(for: eventDate, relativeTo: referenceDate)
            return TimeInformation(display: value, accessibility: value)
        }

        let absInterval = abs(interval)
        let allowedUnits: NSCalendar.Unit
        let allowedComponents: [Calendar.Component]

        if absInterval < 3600 {
            allowedUnits = [.minute, .second]
            allowedComponents = [.minute, .second]
        } else if absInterval < 86_400 {
            allowedUnits = [.hour, .minute]
            allowedComponents = [.hour, .minute]
        } else {
            allowedUnits = [.day, .hour]
            allowedComponents = [.day, .hour]
        }

        let accessibilityFormatter = DateComponentsFormatter()
        accessibilityFormatter.unitsStyle = .full
        accessibilityFormatter.allowedUnits = allowedUnits
        accessibilityFormatter.maximumUnitCount = 2
        accessibilityFormatter.zeroFormattingBehavior = [.dropAll]

        let fallbackFormatter = RelativeDateTimeFormatter()
        fallbackFormatter.unitsStyle = .full
        fallbackFormatter.dateTimeStyle = .named

        let displayComponents = compactDisplayComponents(for: absInterval,
                                                         allowedComponents: allowedComponents)
        let accessibilityComponents = accessibilityFormatter.string(from: absInterval)

        let displayValue: String
        let accessibilityValue: String

        if let displayComponents {
            displayValue = L10n.Formatter.ago(displayComponents)
        } else {
            displayValue = fallbackFormatter.localizedString(for: eventDate, relativeTo: referenceDate)
        }

        if let accessibilityComponents {
            accessibilityValue = L10n.Formatter.ago(accessibilityComponents)
        } else {
            accessibilityValue = fallbackFormatter.localizedString(for: eventDate, relativeTo: referenceDate)
        }

        return TimeInformation(display: displayValue, accessibility: accessibilityValue)
    }

    func durationDescription(asOf referenceDate: Date) -> String? {
        guard !action.category.isInstant else { return nil }
        return L10n.Home.historyDuration(action.durationDescription(asOf: referenceDate))
    }

    func accessibilityLabel(timeInformation: TimeInformation, durationText: String?) -> String {
        guard let durationText else { return timeInformation.accessibility }
        return "\(timeInformation.accessibility), \(durationText)"
    }

    func compactDisplayComponents(for interval: TimeInterval,
                                  allowedComponents: [Calendar.Component]) -> String? {
        guard !allowedComponents.isEmpty else { return nil }

        var remaining = Int(interval.rounded(.down))
        var formattedComponents: [String] = []

        for (index, component) in allowedComponents.enumerated() {
            guard let unitSeconds = seconds(for: component), unitSeconds > 0 else { continue }

            let value: Int

            if index == allowedComponents.count - 1 {
                value = remaining / unitSeconds
            } else {
                value = remaining / unitSeconds
                remaining -= value * unitSeconds
            }

            guard value > 0 else { continue }

            formattedComponents.append("\(value)\(symbol(for: component))")

            if formattedComponents.count == 2 {
                break
            }
        }

        guard !formattedComponents.isEmpty else { return nil }
        return formattedComponents.joined(separator: " ")
    }

    func symbol(for component: Calendar.Component) -> String {
        switch component {
        case .day:
            return "d"
        case .hour:
            return "h"
        case .minute:
            return "m"
        case .second:
            return "s"
        default:
            return ""
        }
    }

    func seconds(for component: Calendar.Component) -> Int? {
        switch component {
        case .day:
            return 86_400
        case .hour:
            return 3_600
        case .minute:
            return 60
        case .second:
            return 1
        default:
            return nil
        }
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

private enum HomeAlert: Identifiable {
    case pendingStart(PendingStartAction)
    case reminderAuthorization(ReminderAuthorizationAlert)

    var id: UUID {
        switch self {
        case let .pendingStart(pending):
            return pending.id
        case let .reminderAuthorization(alert):
            return alert.id
        }
    }
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

private extension BabyActionSnapshot.FeedingType {
    var isBreast: Bool {
        self == .leftBreast || self == .rightBreast
    }
}

private struct ActionTypeSelectionGrid<Option: ActionTypeOption>: View {
    let options: [Option]
    @Binding var selection: Option
    let accentColor: Color
    var onOptionActivated: ((Option) -> Void)?
    let highlightedOptions: [Option: Alignment]

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    init(options: [Option],
         selection: Binding<Option>,
         accentColor: Color,
         onOptionActivated: ((Option) -> Void)? = nil,
         highlightedOptions: [Option: Alignment] = [:]) {
        self.options = options
        self._selection = selection
        self.accentColor = accentColor
        self.onOptionActivated = onOptionActivated
        self.highlightedOptions = highlightedOptions
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(options) { option in
                Button {
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
                    .overlay(alignment: .topLeading) {
                        badgeView(for: option, alignment: .topLeading)
                    }
                    .overlay(alignment: .topTrailing) {
                        badgeView(for: option, alignment: .topTrailing)
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
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selection)
    }

    @ViewBuilder
    private func badgeView(for option: Option, alignment: Alignment) -> some View {
        if highlightedOptions[option] == alignment {
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
                .padding(alignment == .topLeading ? .leading : .trailing, 6)
        }
    }
}

struct ActionEditSheet: View {
    let action: BabyActionSnapshot
    let onSave: (BabyActionSnapshot) -> Void
    private let showsContinueButton: Bool

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

    init(
        action: BabyActionSnapshot,
        showsContinueButton: Bool = true,
        onSave: @escaping (BabyActionSnapshot) -> Void
    ) {
        self.action = action
        self.onSave = onSave
        self.showsContinueButton = showsContinueButton

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
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            guard let currentEndDate = endDate else { return }
            if currentEndDate < newValue {
                endDate = newValue
            }
        }
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
            .pickerStyle(.segmented)

            if bottleSelection == .custom {
                TextField(L10n.Home.customVolumeFieldPlaceholder, text: $customBottleVolume)
                    .keyboardType(.numberPad)
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
        if showsContinueButton && canContinueAction {
            Section(
                footer: Text(L10n.Logs.continueActionInfo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            ) {
                Button(action: continueAction) {
                    Label(L10n.Logs.continueAction, systemImage: "play.fill")
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive, action: deleteAction) {
                Label(L10n.Logs.deleteAction, systemImage: "trash")
            }
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
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore

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
                            }
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
                            highlightedOptions: highlightedFeedingOptions
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
                            .pickerStyle(.segmented)

                            if bottleSelection == .custom {
                                TextField(L10n.Home.customVolumeFieldPlaceholder, text: $customBottleVolume)
                                    .keyboardType(.numberPad)
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
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(category.startActionButtonTitle) {
                        startIfReady()
                    }
                    .disabled(isStartDisabled)
                }
            }
        }
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

    private var highlightedFeedingOptions: [BabyActionSnapshot.FeedingType: Alignment] {
        guard let lastBreastSide = lastBreastFeedingType else { return [:] }

        switch lastBreastSide {
        case .leftBreast:
            return [.leftBreast: .topLeading]
        case .rightBreast:
            return [.rightBreast: .topTrailing]
        default:
            return [:]
        }
    }

    private var lastBreastFeedingType: BabyActionSnapshot.FeedingType? {
        let state = actionStore.state(for: profileStore.activeProfile.id)

        if let active = state.activeAction(for: .feeding), let type = active.feedingType, type.isBreast {
            return type
        }

        return state.history.first(where: { action in
            action.category == .feeding && (action.feedingType?.isBreast ?? false)
        })?.feedingType
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
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile

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
        .environmentObject(LocationManager.shared)
}
