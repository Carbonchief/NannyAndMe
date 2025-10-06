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

    var body: some View {
        let state = currentState

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

                if !state.history.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.headline)

                        VStack(spacing: 12) {
                            ForEach(state.history) { action in
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
    }

    private func headerSection(for state: ProfileActionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log today's care actions")
                .font(.title2)
                .fontWeight(.semibold)

            if let recent = state.mostRecentAction {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(recent.title)
                            .font(.headline)
                    } icon: {
                        Image(systemName: recent.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(recent.category.accentColor)
                    }

                    Text(recent.detailDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if recent.endDate == nil {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Active for \(recent.durationDescription(asOf: context.date))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else if let ended = recent.endDateTimeDescription() {
                        Text("Last finished \(ended)")
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
                Text("Start an action below to begin tracking your baby's day.")
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
                        Text("No entries yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let activeAction {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Started at \(activeAction.startTimeDescription())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Elapsed: \(activeAction.durationDescription(asOf: context.date))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(category.accentColor)
                    }
                }

                Button("Stop") {
                    onStop()
                }
                .buttonStyle(.borderedProminent)
                .tint(category.accentColor)
            } else {
                if let lastCompleted {
                    Text("Last run \(lastCompleted.endDateTimeDescription() ?? lastCompleted.startDateTimeDescription())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(category.startActionButtonTitle) {
                    onStart()
                }
                .buttonStyle(.bordered)
                .tint(category.accentColor)
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

                Text("Started \(action.startDateTimeDescription())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let endDescription = action.endDateTimeDescription() {
                    Text("Ended \(endDescription) • Duration \(action.durationDescription())")
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
                        Text("Start tracking a sleep session. Stop it when your little one wakes up to capture the total rest time.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                    }

                case .diaper:
                    Section("Diaper type") {
                        Picker("Diaper type", selection: $diaperSelection) {
                            ForEach(BabyAction.DiaperType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                case .feeding:
                    Section("Feeding type") {
                        Picker("Feeding type", selection: $feedingSelection) {
                            ForEach(BabyAction.FeedingType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if feedingSelection.requiresVolume {
                        Section("Bottle volume") {
                            Picker("Bottle volume", selection: $bottleSelection) {
                                ForEach(BottleVolumeOption.allOptions) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            if bottleSelection == .custom {
                                TextField("Custom volume (ml)", text: $customBottleVolume)
                                    .keyboardType(.numberPad)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New \(category.title) Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
                return "\(value) ml"
            case .custom:
                return "Custom"
            }
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
