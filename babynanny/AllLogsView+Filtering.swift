import SwiftUI

extension AllLogsView {
    func groupedActions() -> [(date: Date, actions: [BabyAction])] {
        let actions = actionStore.state(for: profileStore.activeProfile.id).history
        var grouped: [Date: [BabyAction]] = [:]
        var orderedDates: [Date] = []

        let filteredActions = actions.filter(isActionIncluded)

        for action in filteredActions.sorted(by: { $0.startDate > $1.startDate }) {
            let day = calendar.startOfDay(for: action.startDate)

            if grouped[day] != nil {
                grouped[day]?.append(action)
            } else {
                grouped[day] = [action]
                orderedDates.append(day)
            }
        }

        return orderedDates.map { date in
            let actionsForDate = grouped[date] ?? []
            return (date: date, actions: actionsForDate)
        }
    }

    func deleteAction(_ action: BabyAction) {
        actionStore.deleteAction(for: profileStore.activeProfile.id, actionID: action.id)
        if editingAction?.id == action.id {
            editingAction = nil
        }
        if actionPendingDeletion?.id == action.id {
            actionPendingDeletion = nil
        }
    }

    func applyFilter(startDate: Date?, endDate: Date?) {
        var normalizedStart = startDate.map { calendar.startOfDay(for: $0) }
        var normalizedEnd = endDate.map { calendar.startOfDay(for: $0) }

        if let start = normalizedStart, let end = normalizedEnd, start > end {
            normalizedEnd = start
        }

        filterStartDate = normalizedStart
        filterEndDate = normalizedEnd
    }

    func clearFilter() {
        filterStartDate = nil
        filterEndDate = nil
    }

    func activeFilterDescription() -> String? {
        switch (filterStartDate, filterEndDate) {
        case let (start?, end?):
            return L10n.Logs.filterSummaryRange(dateFormatter.string(from: start), dateFormatter.string(from: end))
        case let (start?, nil):
            return L10n.Logs.filterSummaryStart(dateFormatter.string(from: start))
        case let (nil, end?):
            return L10n.Logs.filterSummaryEnd(dateFormatter.string(from: end))
        default:
            return nil
        }
    }

    func filterSummaryView(_ description: String) -> some View {
        HStack(spacing: 12) {
            Label(description, systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: clearFilter) {
                Text(L10n.Logs.filterClear)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    fileprivate func isActionIncluded(_ action: BabyAction) -> Bool {
        if let startBoundary = filterStartDate, action.startDate < startBoundary {
            return false
        }
        if let endBoundary = filterEndDate {
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: endBoundary) {
                if action.startDate >= nextDay {
                    return false
                }
            } else if action.startDate > endBoundary {
                return false
            }
        }
        return true
    }
}
