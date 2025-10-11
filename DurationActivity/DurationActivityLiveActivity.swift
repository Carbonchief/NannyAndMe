//
//  DurationActivityLiveActivity.swift
//  DurationActivity
//
//  Created by Luan van der Walt on 2025/10/11.
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 17.0, *)
struct DurationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        struct RunningAction: Codable, Hashable, Identifiable {
            var id: UUID
            var category: DurationActivityCategory
            var title: String
            var subtitle: String?
            var subtypeWord: String?
            var startDate: Date
            var iconSystemName: String
        }

        var actions: [RunningAction]
        var updatedAt: Date
    }

    var profileName: String?
}

@available(iOS 17.0, *)
enum DurationActivityCategory: String, Codable, Hashable {
    case sleep
    case diaper
    case feeding
}

@available(iOS 17.0, *)
struct DurationActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DurationActivityAttributes.self) { context in
            DurationActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let action = context.state.actions.first {
                        DurationActivityIconView(action: action)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let action = context.state.actions.first {
                        Text(action.startDate, style: .timer)
                            .font(.title3)
                            .monospacedDigit()
                            .foregroundStyle(action.category.accentColor)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = context.attributes.profileName, name.isEmpty == false {
                            Text(name)
                                .font(.headline)
                                .fontWeight(.semibold)
                        }

                        ForEach(context.state.actions.prefix(2)) { action in
                            DurationActivityActionRow(action: action)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                if let action = context.state.actions.first {
                    Image(systemName: action.iconSystemName)
                        .font(.headline)
                }
            } compactTrailing: {
                if let action = context.state.actions.first {
                    VStack(spacing: 2) {
                        if let subtypeWord = action.subtypeWord, subtypeWord.isEmpty == false {
                            Text(subtypeWord)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                                .foregroundStyle(action.category.accentColor)
                        }

                        Text(action.startDate, style: .timer)
                            .monospacedDigit()
                            .font(.footnote)
                    }
                }
            } minimal: {
                if let action = context.state.actions.first {
                    ZStack {
                        Circle()
                            .fill(action.category.accentColor.opacity(0.15))
                            .frame(width: 36, height: 36)

                        if let subtypeWord = action.subtypeWord, subtypeWord.isEmpty == false {
                            Text(subtypeWord)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .foregroundStyle(action.category.accentColor)
                                .padding(6)
                        } else {
                            Image(systemName: action.iconSystemName)
                                .foregroundStyle(action.category.accentColor)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityLockScreenView: View {
    let context: ActivityViewContext<DurationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let profileName = context.attributes.profileName, profileName.isEmpty == false {
                Text(profileName)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            ForEach(context.state.actions.prefix(3)) { action in
                DurationActivityActionRow(action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

@available(iOS 17.0, *)
private struct DurationActivityActionRow: View {
    let action: DurationActivityAttributes.ContentState.RunningAction

    private var highlightedSubtype: String? {
        guard let subtype = action.subtypeWord, subtype.isEmpty == false else { return nil }

        if let subtitle = action.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           subtitle.caseInsensitiveCompare(subtype) == .orderedSame {
            return nil
        }

        return subtype
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DurationActivityIconView(action: action)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(action.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if let subtypeWord = highlightedSubtype {
                        Text(subtypeWord)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .foregroundStyle(action.category.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(action.category.accentColor.opacity(0.12))
                            )
                    }
                }

                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(action.startDate, style: .timer)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(action.category.accentColor)
            }

            Spacer(minLength: 0)
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityIconView: View {
    let action: DurationActivityAttributes.ContentState.RunningAction

    var body: some View {
        ZStack {
            Circle()
                .fill(action.category.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)

            Image(systemName: action.iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(action.category.accentColor)
        }
    }
}

@available(iOS 17.0, *)
private extension DurationActivityCategory {
    var accentColor: Color {
        switch self {
        case .sleep:
            return .indigo
        case .diaper:
            return .green
        case .feeding:
            return .orange
        }
    }
}

@available(iOS 17.0, *)
private extension DurationActivityAttributes {
    static var preview: DurationActivityAttributes {
        DurationActivityAttributes(profileName: "Aria")
    }
}

@available(iOS 17.0, *)
private extension DurationActivityAttributes.ContentState {
    static var preview: DurationActivityAttributes.ContentState {
        let now = Date()
        let sleep = RunningAction(
            id: UUID(),
            category: .sleep,
            title: WidgetL10n.Actions.sleep,
            subtitle: nil,
            subtypeWord: nil,
            startDate: now.addingTimeInterval(-5400),
            iconSystemName: "moon.zzz.fill"
        )
        let feeding = RunningAction(
            id: UUID(),
            category: .feeding,
            title: WidgetL10n.Actions.feeding,
            subtitle: WidgetL10n.Actions.feedingWithType(WidgetL10n.FeedingType.bottle),
            subtypeWord: WidgetL10n.FeedingType.bottle,
            startDate: now.addingTimeInterval(-1200),
            iconSystemName: "takeoutbag.and.cup.and.straw.fill"
        )

        return DurationActivityAttributes.ContentState(
            actions: [sleep, feeding],
            updatedAt: now
        )
    }
}

#Preview("Notification", as: .content, using: DurationActivityAttributes.preview) {
    DurationActivityLiveActivity()
} contentStates: {
    DurationActivityAttributes.ContentState.preview
}
