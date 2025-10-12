//
//  DurationActivityLiveActivity.swift
//  DurationActivity
//
//  Created by Luan van der Walt on 2025/10/11.
//

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

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
            let accentColor = context.primaryAccentColor
            let primaryAction = context.state.actions.first

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let action = primaryAction {
                        DurationActivityIconView(action: action)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let action = primaryAction {
                        Text(action.startDate, style: .timer)
                            .font(.title3)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(action.category.accentColor)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    if let action = primaryAction {
                        DurationActivityExpandedHighlightView(
                            action: action,
                            attributes: context.attributes,
                            accentColor: accentColor,
                            updatedAt: context.state.updatedAt
                        )
                    } else {
                        DurationActivityEmptyExpandedView(accentColor: accentColor)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    DurationActivitySupplementaryActionsView(
                        actions: Array(context.state.actions.dropFirst().prefix(2))
                    )
                }
            } compactLeading: {
                if let action = primaryAction {
                    Image(systemName: action.iconSystemName)
                        .font(.headline)
                        .accessibilityHidden(true)
                }
            } compactTrailing: {
                if let action = primaryAction {
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
                            .contentTransition(.numericText())
                            .font(.footnote)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(action.accessibilityDescription))
                }
            } minimal: {
                if let action = primaryAction {
                    DurationActivityMinimalView(action: action)
                } else {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .accessibilityLabel(Text(WidgetL10n.Duration.noActiveTimers))
                }
            }
            .keylineTint(accentColor)
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityLockScreenView: View {
    let context: ActivityViewContext<DurationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DurationActivityHeaderView(
                profileName: context.attributes.profileName,
                updatedAt: context.state.updatedAt,
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DurationActivityIconView(action: action)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(action.title)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    if let subtypeWord = action.highlightedSubtypeWord {
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
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(action.category.accentColor.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(action.accessibilityDescription))
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

            Image(systemName: action.iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

@available(iOS 17.0, *)
private struct DurationActivityHeaderView: View {
    enum SpacingStyle {
        case compact
        case regular
    }

    var profileName: String?
    var updatedAt: Date?
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
            if let profileName, profileName.isEmpty == false {
                Text(profileName)
                    .font(.headline)
                    .foregroundStyle(.primary)
            } else {
                Text(WidgetL10n.Profile.newProfile)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if let updatedAt {
                Text(updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(iOS 17.0, *)
private struct DurationActivityExpandedHighlightView: View {
    let action: DurationActivityAttributes.ContentState.RunningAction
    let attributes: DurationActivityAttributes
    let accentColor: Color
    let updatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DurationActivityHeaderView(
                profileName: attributes.profileName,
                updatedAt: updatedAt,
                spacingStyle: .compact
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(action.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let subtypeWord = action.highlightedSubtypeWord {
                    Text(subtypeWord)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .textCase(.uppercase)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(0.16))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(action.accessibilityDescription))
    }
}

@available(iOS 17.0, *)
private struct DurationActivitySupplementaryActionsView: View {
    let actions: [DurationActivityAttributes.ContentState.RunningAction]

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(actions) { action in
                    DurationActivityActionRow(action: action)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@available(iOS 17.0, *)
private struct DurationActivityEmptyExpandedView: View {
    let accentColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            Text(WidgetL10n.Duration.noActiveTimers)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
    }
}

@available(iOS 17.0, *)
private struct DurationActivityMinimalView: View {
    let action: DurationActivityAttributes.ContentState.RunningAction

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(action.accessibilityDescription))
    }
}

@available(iOS 17.0, *)
private extension DurationActivityAttributes.ContentState.RunningAction {
    var highlightedSubtypeWord: String? {
        guard let subtype = subtypeWord, subtype.isEmpty == false else { return nil }

        if let subtitle = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           subtitle.caseInsensitiveCompare(subtype) == .orderedSame {
            return nil
        }

        return subtype
    }

    var accessibilityDescription: String {
        var components: [String] = [title]

        if let subtitle, subtitle.isEmpty == false {
            components.append(subtitle)
        }

        let relativeDescription = DurationActivityFormatter.relativeDate.localizedString(
            for: startDate,
            relativeTo: Date()
        )

        components.append(relativeDescription)

        return components.joined(separator: ", ")
    }
}

@available(iOS 17.0, *)
private enum DurationActivityFormatter {
    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
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
