import SwiftUI

struct AllLogsView: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var actionStore: ActionLogStore
    @State var editingAction: BabyAction?
    @State var actionPendingDeletion: BabyAction?
    @State private var isShowingFilter = false
    @State var filterStartDate: Date?
    @State var filterEndDate: Date?

    let calendar = Calendar.current
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .navigationTitle(L10n.Logs.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingFilter = true
                } label: {
                    Label(L10n.Logs.filterButton, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let description = activeFilterDescription() {
                filterSummaryView(description)
            }
        }
        .sheet(item: $editingAction) { action in
            ActionEditSheet(action: action) { updatedAction in
                actionStore.updateAction(for: profileStore.activeProfile.id, action: updatedAction)
                editingAction = nil
            } onDelete: { actionToDelete in
                deleteAction(actionToDelete)
            }
        }
        .sheet(isPresented: $isShowingFilter) {
            AllLogsDateFilterSheet(
                calendar: calendar,
                startDate: filterStartDate,
                endDate: filterEndDate
            ) { start, end in
                applyFilter(startDate: start, endDate: end)
            } onClear: {
                clearFilter()
            }
        }
        .alert(item: $actionPendingDeletion) { action in
            Alert(
                title: Text(L10n.Logs.deleteConfirmationTitle),
                message: Text(L10n.Logs.deleteConfirmationMessage),
                primaryButton: .destructive(Text(L10n.Logs.deleteAction)) {
                    deleteAction(action)
                },
                secondaryButton: .cancel {
                    actionPendingDeletion = nil
                }
            )
        }
    }

    @ViewBuilder
    private func content(asOf referenceDate: Date) -> some View {
        let grouped = groupedActions()

        if grouped.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(L10n.Logs.emptyTitle)
                    .font(.headline)
                Text(L10n.Logs.emptySubtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(grouped, id: \.date) { entry in
                    Section(header: Text(dateFormatter.string(from: entry.date))) {
                        ForEach(entry.actions) { action in
                            AllLogsRowView(
                                action: action,
                                referenceDate: referenceDate,
                                timeFormatter: timeFormatter,
                                onEdit: { editingAction = $0 },
                                onDelete: { actionPendingDeletion = $0 }
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                }
            }
            .listRowSpacing(0)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }

}
