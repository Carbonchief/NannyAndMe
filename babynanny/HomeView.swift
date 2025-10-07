//
//  HomeView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @State private var presentedCategory: BabyActionCategory?
    @State private var editingAction: BabyAction?
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

                VStack(spacing: 16) {
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

                if !recentHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.Home.recentActivity)
                                .font(.headline)

                            Spacer()

                            Button(action: onShowAllLogs) {
                                Text(L10n.Home.recentActivityShowAll)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.plain)
                            .tint(.accentColor)
                        }

                        VStack(spacing: 12) {
                            ForEach(recentHistory) { action in
                                HistoryRow(action: action)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $presentedCategory) { category in
            ActionDetailSheet(category: category) { configuration in
                startAction(for: category,
                             diaperType: configuration.diaperType,
                             feedingType: configuration.feedingType,
                             bottleVolume: configuration.bottleVolume)
            }
        }
        .sheet(item: $editingAction) { action in
            ActionEditSheet(action: action) { updatedAction in
                actionStore.updateAction(for: activeProfileID, action: updatedAction)
                editingAction = nil
            }
        }
    }

    private func headerSection(for state: ProfileActionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Home.headerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            if let recent = state.mostRecentAction {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Label {
                            Text(recent.title)
                                .font(.headline)
                        } icon: {
                            Image(systemName: recent.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(recent.category.accentColor)
                        }

                        Spacer(minLength: 12)

                        Button {
                            editingAction = recent
                        } label: {
                            Label(L10n.Home.editActionButton, systemImage: "square.and.pencil")
                                .font(.subheadline)
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                        .tint(.accentColor)
                    }

                    Text(recent.detailDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if recent.endDate == nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(L10n.Home.activeFor(recent.durationDescription(asOf: context.date)))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else if let ended = recent.endDateTimeDescription() {
                        Text(L10n.Home.lastFinished(ended))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            } else {
                Text(L10n.Home.placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleStartTap(for category: BabyActionCategory) {
        switch category {
        case .sleep:
            startAction(for: .sleep)
        case .diaper, .feeding:
            presentedCategory = category
        }
    }

    private func startAction(for category: BabyActionCategory,
                             diaperType: BabyAction.DiaperType? = nil,
                             feedingType: BabyAction.FeedingType? = nil,
                             bottleVolume: Int? = nil) {
        actionStore.startAction(for: activeProfileID,
                                category: category,
                                diaperType: diaperType,
                                feedingType: feedingType,
                                bottleVolume: bottleVolume)
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
}

private struct ActionCard: View {
    let category: BabyActionCategory
    let activeAction: BabyAction?
    let lastCompleted: BabyAction?
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(category.accentColor.opacity(0.15))
                            .frame(width: 48, height: 48)

                        Image(systemName: activeAction?.icon ?? lastCompleted?.icon ?? category.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(category.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.headline)

                        if let activeAction {
                            Text(activeAction.detailDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if let lastCompleted {
                            Text(lastCompleted.detailDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L10n.Home.noEntries)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .layoutPriority(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                actionButton
                    .controlSize(.large)
                    .font(.headline)
                    .fixedSize()
            }

            if let activeAction {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.Home.startedAt(activeAction.startTimeDescription()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(L10n.Home.elapsed(activeAction.durationDescription(asOf: context.date)))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(category.accentColor)
                    }
                }

            } else {
                if let lastCompleted {
                    Text(L10n.Home.lastRun(lastCompleted.endDateTimeDescription() ?? lastCompleted.startDateTimeDescription()))
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

private extension ActionCard {
    @ViewBuilder
    var actionButton: some View {
        if activeAction != nil {
            Button(L10n.Common.stop) {
                onStop()
            }
            .buttonStyle(.borderedProminent)
            .tint(category.accentColor)
        } else {
            Button(category.startActionButtonTitle) {
                onStart()
            }
            .buttonStyle(.bordered)
            .tint(category.accentColor)
        }
    }
}

private struct HistoryRow: View {
    let action: BabyAction

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

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(action.detailDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(L10n.Home.historyStarted(action.startDateTimeDescription()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let endDescription = action.endDateTimeDescription() {
                    Text(L10n.Home.historyEnded(endDescription, action.durationDescription()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }
}

private struct ActionConfiguration {
    var diaperType: BabyAction.DiaperType?
    var feedingType: BabyAction.FeedingType?
    var bottleVolume: Int?
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
    let action: BabyAction
    let onSave: (BabyAction) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var diaperSelection: BabyAction.DiaperType
    @State private var feedingSelection: BabyAction.FeedingType
    @State private var bottleSelection: BottleVolumeOption
    @State private var customBottleVolume: String

    init(action: BabyAction, onSave: @escaping (BabyAction) -> Void) {
        self.action = action
        self.onSave = onSave

        _startDate = State(initialValue: action.startDate)
        _diaperSelection = State(initialValue: action.diaperType ?? .pee)
        _feedingSelection = State(initialValue: action.feedingType ?? .bottle)

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
                Section(header: Text(L10n.Home.editCategoryLabel)) {
                    Text(action.category.title)
                }

                Section(header: Text(L10n.Home.editStartSectionTitle)) {
                    DatePicker(
                        L10n.Home.editStartPickerLabel,
                        selection: $startDate,
                        in: startDateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if action.category == .diaper {
                    Section(header: Text(L10n.Home.diaperTypeSectionTitle)) {
                        Picker(selection: $diaperSelection) {
                            ForEach(BabyAction.DiaperType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Text(L10n.Home.diaperTypePickerLabel)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if action.category == .feeding {
                    Section(header: Text(L10n.Home.feedingTypeSectionTitle)) {
                        Picker(selection: $feedingSelection) {
                            ForEach(BabyAction.FeedingType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Text(L10n.Home.feedingTypePickerLabel)
                        }
                        .pickerStyle(.segmented)
                    }

                    if feedingSelection.requiresVolume {
                        Section(header: Text(L10n.Home.bottleVolumeSectionTitle)) {
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
                        }
                    }
                }

                if let endDescription = action.endDateTimeDescription() {
                    Section(header: Text(L10n.Home.editEndSectionTitle)) {
                        Text(endDescription)
                            .font(.body)
                        Text(L10n.Home.editEndNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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
    }

    private var startDateRange: ClosedRange<Date> {
        let proposedUpperBound = action.endDate ?? Date()
        let upperBound = max(action.startDate, proposedUpperBound)
        return Date.distantPast...upperBound
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

    private func save() {
        var updated = action
        updated.startDate = startDate

        switch action.category {
        case .sleep:
            break
        case .diaper:
            updated.diaperType = diaperSelection
        case .feeding:
            updated.feedingType = feedingSelection
            updated.bottleVolume = feedingSelection.requiresVolume ? resolvedBottleVolume : nil
        }

        onSave(updated.withValidatedDates())
        dismiss()
    }
}

private struct ActionDetailSheet: View {
    let category: BabyActionCategory
    let onStart: (ActionConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var diaperSelection: BabyAction.DiaperType = .pee
    @State private var feedingSelection: BabyAction.FeedingType = .bottle
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
                        Picker(selection: $diaperSelection) {
                            ForEach(BabyAction.DiaperType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Text(L10n.Home.diaperTypePickerLabel)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text(L10n.Home.diaperTypeSectionTitle)
                    }

                case .feeding:
                    Section {
                        Picker(selection: $feedingSelection) {
                            ForEach(BabyAction.FeedingType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        } label: {
                            Text(L10n.Home.feedingTypePickerLabel)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text(L10n.Home.feedingTypeSectionTitle)
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
                        onStart(configuration)
                        dismiss()
                    }
                    .disabled(isStartDisabled)
                }
            }
        }
    }

    private var configuration: ActionConfiguration {
        switch category {
        case .sleep:
            return ActionConfiguration(diaperType: nil, feedingType: nil, bottleVolume: nil)
        case .diaper:
            return ActionConfiguration(diaperType: diaperSelection, feedingType: nil, bottleVolume: nil)
        case .feeding:
            let volume = feedingSelection.requiresVolume ? resolvedBottleVolume : nil
            return ActionConfiguration(diaperType: nil, feedingType: feedingSelection, bottleVolume: volume)
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
    state.activeActions[.sleep] = BabyAction(category: .sleep, startDate: Date().addingTimeInterval(-1200))
    state.history = [
        BabyAction(category: .feeding, startDate: Date().addingTimeInterval(-5400), endDate: Date().addingTimeInterval(-5100), feedingType: .bottle, bottleVolume: 110),
        BabyAction(category: .diaper, startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-3500), diaperType: .pee)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return HomeView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}
