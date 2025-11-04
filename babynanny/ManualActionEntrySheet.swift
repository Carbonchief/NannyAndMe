import SwiftUI

struct ManualActionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore

    @State private var category: BabyActionCategory = .sleep
    @State private var diaperSelection: BabyActionSnapshot.DiaperType = .pee
    @State private var feedingSelection: BabyActionSnapshot.FeedingType = .bottle
    @State private var bottleTypeSelection: BabyActionSnapshot.BottleType = .formula
    @State private var bottleSelection: BottleVolumeOption = .preset(120)
    @State private var customBottleVolume: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                startSection
                endSection
                diaperSection
                feedingSection
            }
            .navigationTitle(L10n.ManualEntry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.ManualEntry.saveButton) {
                        save()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
        .onChange(of: category) { _, newValue in
            if newValue.isInstant {
                endDate = startDate
            }
        }
        .onChange(of: feedingSelection) { _, newValue in
            if newValue.requiresVolume == false {
                bottleSelection = .preset(120)
                customBottleVolume = ""
            }
        }
    }

    private var categorySection: some View {
        Section(header: Text(L10n.Home.editCategoryLabel)) {
            Picker(L10n.Home.editCategoryLabel, selection: $category) {
                ForEach(BabyActionCategory.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var startSection: some View {
        Section(header: Text(L10n.Home.editStartSectionTitle)) {
            DatePicker(
                L10n.Home.editStartPickerLabel,
                selection: $startDate,
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    @ViewBuilder
    private var endSection: some View {
        if category.isInstant == false {
            Section(header: Text(L10n.Home.editEndSectionTitle)) {
                DatePicker(
                    L10n.Home.editEndPickerLabel,
                    selection: $endDate,
                    in: startDate...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }
    }

    @ViewBuilder
    private var diaperSection: some View {
        if category == .diaper {
            Section(header: Text(L10n.Home.diaperTypeSectionTitle)) {
                Picker(L10n.Home.diaperTypePickerLabel, selection: $diaperSelection) {
                    ForEach(BabyActionSnapshot.DiaperType.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var feedingSection: some View {
        if category == .feeding {
            Section(header: Text(L10n.Home.feedingTypeSectionTitle)) {
                Picker(L10n.Home.feedingTypePickerLabel, selection: $feedingSelection) {
                    ForEach(BabyActionSnapshot.FeedingType.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if feedingSelection == .bottle {
                Section(header: Text(L10n.Home.bottleTypeSectionTitle)) {
                    Picker(L10n.Home.bottleTypePickerLabel, selection: $bottleTypeSelection) {
                        ForEach(BabyActionSnapshot.BottleType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text(L10n.Home.bottleVolumeSectionTitle)) {
                    Picker(L10n.Home.bottleVolumePickerLabel, selection: $bottleSelection) {
                        ForEach(BottleVolumeOption.presets) { option in
                            Text(option.label).tag(option)
                        }
                        Text(BottleVolumeOption.custom.label).tag(BottleVolumeOption.custom)
                    }
                    .pickerStyle(.segmented)

                    if bottleSelection == .custom {
                        TextField(L10n.Home.customVolumeFieldPlaceholder, text: $customBottleVolume)
                            .keyboardType(.numberPad)
                    }
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
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

    private func save() {
        let endValue: Date? = category.isInstant ? startDate : endDate
        let bottleVolume = feedingSelection.requiresVolume ? resolvedBottleVolume : nil
        let bottleType = feedingSelection == .bottle ? bottleTypeSelection : nil

        let action = BabyActionSnapshot(
            category: category,
            startDate: startDate,
            endDate: endValue,
            diaperType: category == .diaper ? diaperSelection : nil,
            feedingType: category == .feeding ? feedingSelection : nil,
            bottleType: bottleType,
            bottleVolume: bottleVolume
        )

        actionStore.addManualAction(for: profileStore.activeProfile.id, action: action)
        dismiss()
    }
}

#Preview {
    ManualActionEntrySheet()
        .environmentObject(ProfileStore.preview)
        .environmentObject(ActionLogStore.previewStore(profiles: [:]))
        .environmentObject(LocationManager.shared)
}
