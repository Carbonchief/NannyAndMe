import SwiftUI

struct AllLogsRowView: View {
    let action: BabyAction
    let referenceDate: Date
    let timeFormatter: DateFormatter
    let onEdit: (BabyAction) -> Void
    let onDelete: (BabyAction) -> Void

    var body: some View {
        Button {
            onEdit(action)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(action.category.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: action.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(action.category.accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Logs.entryTitle(timeFormatter.string(from: action.startDate),
                                               durationDescription,
                                               actionSummary))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let detail = detailDescription {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEdit(action)
            } label: {
                Label(L10n.Logs.editAction, systemImage: "square.and.pencil")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete(action)
            } label: {
                Label(L10n.Logs.deleteAction, systemImage: "trash")
            }
        }
    }

    private var durationDescription: String {
        action.durationDescription(asOf: referenceDate)
    }

    private var actionSummary: String {
        switch action.category {
        case .sleep:
            return L10n.Logs.summarySleep()
        case .diaper:
            if let type = action.diaperType {
                return L10n.Logs.summaryDiaper(withType: type.title.localizedLowercase)
            }
            return L10n.Logs.summaryDiaper()
        case .feeding:
            if let type = action.feedingType {
                if type == .bottle {
                    let bottleTypeTitle = action.bottleType?.title.localizedLowercase
                    if let bottleTypeTitle, let volume = action.bottleVolume {
                        return L10n.Logs.summaryFeedingBottle(type: bottleTypeTitle, volume: volume)
                    }
                    if let volume = action.bottleVolume {
                        return L10n.Logs.summaryFeedingBottle(volume: volume)
                    }
                    if let bottleTypeTitle {
                        return L10n.Logs.summaryFeedingBottleTypeOnly(bottleTypeTitle)
                    }
                }
                return L10n.Logs.summaryFeeding(withType: type.title.localizedLowercase)
            }
            return L10n.Logs.summaryFeeding()
        }
    }

    private var detailDescription: String? {
        if action.endDate == nil {
            return L10n.Logs.active
        }
        return nil
    }
}
