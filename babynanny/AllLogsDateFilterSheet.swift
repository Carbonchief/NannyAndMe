import SwiftUI

struct AllLogsDateFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let calendar: Calendar
    private let onApply: (Date?, Date?) -> Void
    private let onClear: () -> Void

    @State private var startDateSelection: Date
    @State private var endDateSelection: Date
    @State private var useStartDate: Bool
    @State private var useEndDate: Bool

    init(calendar: Calendar,
         startDate: Date?,
         endDate: Date?,
         onApply: @escaping (Date?, Date?) -> Void,
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(L10n.Logs.filterStartToggle, isOn: $useStartDate.animation())
                    if useStartDate {
                        DatePicker(
                            L10n.Logs.filterStartLabel,
                            selection: $startDateSelection,
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    Toggle(L10n.Logs.filterEndToggle, isOn: $useEndDate.animation())
                    if useEndDate {
                        DatePicker(
                            L10n.Logs.filterEndLabel,
                            selection: $endDateSelection,
                            in: endDateRange,
                            displayedComponents: .date
                        )
                    }
                }

                if useStartDate || useEndDate {
                    Section {
                        Button(L10n.Logs.filterClear) {
                            clearSelection()
                        }
                    }
                }
            }
            .navigationTitle(L10n.Logs.filterTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        applySelection()
                    }
                }
            }
            .onChange(of: startDateSelection) { newValue in
                if useEndDate, endDateSelection < newValue {
                    endDateSelection = newValue
                }
            }
            .onChange(of: useStartDate) { newValue in
                if newValue, useEndDate, endDateSelection < startDateSelection {
                    endDateSelection = startDateSelection
                }
            }
            .onChange(of: useEndDate) { newValue in
                if newValue, endDateSelection < startDateSelection {
                    endDateSelection = startDateSelection
                }
            }
        }
    }

    private var endDateRange: ClosedRange<Date> {
        let lowerBound = useStartDate ? startDateSelection : Date.distantPast
        return lowerBound...Date.distantFuture
    }

    private func applySelection() {
        let start = useStartDate ? calendar.startOfDay(for: startDateSelection) : nil
        let end = useEndDate ? calendar.startOfDay(for: endDateSelection) : nil
        onApply(start, end)
        dismiss()
    }

    private func clearSelection() {
        useStartDate = false
        useEndDate = false
        onClear()
        dismiss()
    }
}
