import SwiftUI

struct AllLogsDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let calendar: Calendar
    private let onApply: (Date?, Date?, BabyActionCategory?) -> Void
    private let onClear: () -> Void

    @State private var startDateSelection: Date
    @State private var endDateSelection: Date
    @State private var useStartDate: Bool
    @State private var useEndDate: Bool
    @State private var selectedCategory: BabyActionCategory?

    init(calendar: Calendar,
         startDate: Date?,
         endDate: Date?,
         selectedCategory: BabyActionCategory?,
         onApply: @escaping (Date?, Date?, BabyActionCategory?) -> Void,
         onClear: @escaping () -> Void) {
        self.calendar = calendar
        self.onApply = onApply
        self.onClear = onClear

        let today = calendar.startOfDay(for: Date())
        let normalizedStart = startDate.map { calendar.startOfDay(for: $0) }
        let normalizedEnd = endDate.map { calendar.startOfDay(for: $0) }
        let initialStart = normalizedStart ?? normalizedEnd ?? today
        let initialEndCandidate = normalizedEnd ?? initialStart
        let initialEnd = max(initialEndCandidate, initialStart)

        _startDateSelection = State(initialValue: initialStart)
        _endDateSelection = State(initialValue: initialEnd)
        _useStartDate = State(initialValue: normalizedStart != nil)
        _useEndDate = State(initialValue: normalizedEnd != nil)
        _selectedCategory = State(initialValue: selectedCategory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.Logs.filterStartToggle, isOn: $useStartDate.animation())
                        .postHogLabel("logs.filter.useStart")
                    if useStartDate {
                        DatePicker(
                            L10n.Logs.filterStartLabel,
                            selection: $startDateSelection,
                            displayedComponents: .date
                        )
                        .postHogLabel("logs.filter.startDate")
                    }
                }

                Section {
                    Toggle(L10n.Logs.filterEndToggle, isOn: $useEndDate.animation())
                        .postHogLabel("logs.filter.useEnd")
                    if useEndDate {
                        DatePicker(
                            L10n.Logs.filterEndLabel,
                            selection: $endDateSelection,
                            in: endDateRange,
                            displayedComponents: .date
                        )
                        .postHogLabel("logs.filter.endDate")
                    }
                }

                Section(L10n.Logs.filterCategorySection) {
                    Picker(L10n.Logs.filterCategorySection, selection: $selectedCategory) {
                        Text(L10n.Logs.filterCategoryAll)
                            .tag(BabyActionCategory?.none)
                        ForEach(BabyActionCategory.allCases) { category in
                            Text(category.title)
                                .tag(Optional(category))
                        }
                    }
                    .postHogLabel("logs.filter.category")
                    .pickerStyle(.inline)
                }

                if useStartDate || useEndDate || selectedCategory != nil {
                    Section {
                        Button(L10n.Logs.filterClear) {
                            clearSelection()
                        }
                        .postHogLabel("logs.filter.clear")
                        .phCaptureTap(
                            event: "logs_filter_clear_selection_button",
                            properties: ["has_selection": (useStartDate || useEndDate || selectedCategory != nil) ? "true" : "false"]
                        )
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle(L10n.Logs.filterTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .postHogLabel("logs.filter.cancel")
                    .phCaptureTap(event: "logs_filter_cancel_toolbar")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        applySelection()
                    }
                    .postHogLabel("logs.filter.apply")
                    .phCaptureTap(
                        event: "logs_filter_apply_toolbar",
                        properties: [
                            "has_start": useStartDate ? "true" : "false",
                            "has_end": useEndDate ? "true" : "false",
                            "has_category": selectedCategory == nil ? "false" : "true"
                        ]
                    )
                }
            }
            .onChange(of: startDateSelection) { _, newValue in
                if useEndDate, endDateSelection < newValue {
                    endDateSelection = newValue
                }
                Analytics.capture(
                    "logs_filter_update_start_date",
                    properties: ["use_start": useStartDate ? "true" : "false"]
                )
            }
            .onChange(of: useStartDate) { _, newValue in
                Analytics.capture(
                    "logs_filter_toggle_start_date",
                    properties: ["is_on": newValue ? "true" : "false"]
                )
                if newValue, useEndDate, endDateSelection < startDateSelection {
                    endDateSelection = startDateSelection
                }
            }
            .onChange(of: useEndDate) { _, newValue in
                Analytics.capture(
                    "logs_filter_toggle_end_date",
                    properties: ["is_on": newValue ? "true" : "false"]
                )
                if newValue, endDateSelection < startDateSelection {
                    endDateSelection = startDateSelection
                }
            }
            .onChange(of: selectedCategory) { _, newValue in
                Analytics.capture(
                    "logs_filter_select_category",
                    properties: ["category": newValue?.rawValue ?? "all"]
                )
            }
        }
        .phScreen("logs_filter_sheet_allLogsDateFilterSheet")
    }

    private var endDateRange: ClosedRange<Date> {
        let lowerBound = useStartDate ? startDateSelection : Date.distantPast
        return lowerBound...Date.distantFuture
    }

    private func applySelection() {
        let start = useStartDate ? calendar.startOfDay(for: startDateSelection) : nil
        let end = useEndDate ? calendar.startOfDay(for: endDateSelection) : nil
        onApply(start, end, selectedCategory)
        dismiss()
    }

    private func clearSelection() {
        useStartDate = false
        useEndDate = false
        selectedCategory = nil
        onClear()
        dismiss()
    }
}
