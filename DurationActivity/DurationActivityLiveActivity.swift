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
                .activityBackgroundTint(context.primaryAccentColor.opacity(0.12))
                .activitySystemActionForegroundColor(context.primaryAccentColor)
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
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        DurationActivityHeaderView(
                            accentColor: context.primaryAccentColor,
                            spacingStyle: .compact
                        )

                        ForEach(context.state.actions.prefix(2)) { action in
                            DurationActivityActionRow(action: action)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        context.primaryAccentColor.opacity(0.2),
                                        context.primaryAccentColor.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(context.primaryAccentColor.opacity(0.15), lineWidth: 1)
                            )
                    )
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
            .keylineTint(context.primaryAccentColor)
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityLockScreenView: View {
    let context: ActivityViewContext<DurationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DurationActivityHeaderView(
                accentColor: context.primaryAccentColor,
                spacingStyle: .regular
            )

            ForEach(context.state.actions.prefix(3)) { action in
                DurationActivityActionRow(action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            context.primaryAccentColor.opacity(0.2),
                            context.primaryAccentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(context.primaryAccentColor.opacity(0.15), lineWidth: 1)
                )
        )
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

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(action.title)
                        .font(.footnote)
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
                                    .fill(action.category.accentColor.opacity(0.16))
                            )
                    }
                }

                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(action.startDate, style: .timer)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(action.category.accentColor)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(action.category.accentColor.opacity(0.08))
        )
    }
}

@available(iOS 17.0, *)
private struct DurationActivityIconView: View {
    let action: DurationActivityAttributes.ContentState.RunningAction

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            action.category.accentColor.opacity(0.32),
                            action.category.accentColor.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(color: action.category.accentColor.opacity(0.2), radius: 6, x: 0, y: 4)

            Image(systemName: action.iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityHeaderView: View {
    enum SpacingStyle {
        case compact
        case regular
    }

    let accentColor: Color
    var spacingStyle: SpacingStyle

    private var headerSpacing: CGFloat {
        switch spacingStyle {
        case .compact:
            return 8
        case .regular:
            return 12
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            Text(WidgetL10n.Duration.trackingLabel.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(accentColor.opacity(0.18))
                )
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
private extension ActivityViewContext where Attributes == DurationActivityAttributes {
    var primaryAccentColor: Color {
        state.actions.first?.category.accentColor ?? .accentColor
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
