// AUDIT NOTES:
// - Legacy widget rendered multiple actions and read from a JSON app-group
//   cache, violating ActivityKit guidance to drive UI from `ContentState`.
// - Manual duration formatting required periodic updates, wasting battery and
//   drifting when the extension was suspended.
// - No clear mapping between SwiftData records and live activities, so the app
//   could not restore state across launches or terminate finished sessions.
//
// Refactor plan:
// 1. Introduce a minimal `DurationAttributes` + `ContentState` shared with the
//    app so every live activity links back to a SwiftData record.
// 2. Replace the widget views with lock screen and Dynamic Island layouts that
//    rely entirely on system relative timers.
// 3. Feed the widget via ActivityKit updates from the app process—no direct
//    datastore reads in the extension.

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 17.0, *)
struct DurationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DurationAttributes.self) { context in
            DurationLockScreenView(context: context)
                .activityBackgroundTint(.clear)
        } dynamicIsland: { context in
            dynamicIsland(for: context)
        }
        .configurationDisplayName("Duration")
        .description("Track in-progress actions from Nanny and Me.")
    }

    private func dynamicIsland(
        for context: ActivityViewContext<DurationAttributes>
    ) -> DynamicIsland {
        // Compact-only Dynamic Island: icon + relative duration, no expanded regions.
        DynamicIsland {
            DynamicIslandExpandedRegion(.center) {
                EmptyView()
            }
        } compactLeading: {
            actionIconView(for: context)
        } compactTrailing: {
            durationText(for: context)
                .font(.caption2.monospacedDigit())
                .privacySensitive()
        } minimal: {
            actionIconView(for: context)
        }
        .widgetURL(
            URL(string: "nannyme://activity/\(context.attributes.activityID.uuidString)")
        )
    }

    private func durationText(
        for context: ActivityViewContext<DurationAttributes>
    ) -> Text {
        if let endDate = context.state.endDate {
            return Text(timerInterval: context.state.startDate...endDate, countsDown: false)
        }

        return Text(context.state.startDate, style: .timer)
    }

    @ViewBuilder
    private func actionIconView(
        for context: ActivityViewContext<DurationAttributes>
    ) -> some View {
        let symbolName = actionIconName(for: context)
        Image(systemName: symbolName)
            .accessibilityLabel(context.state.actionType)
    }

    private func actionIconName(
        for context: ActivityViewContext<DurationAttributes>
    ) -> String {
        guard let icon = context.state.actionIconSystemName, icon.isEmpty == false else {
            return "clock"
        }
        return icon
    }
}

@available(iOS 17.0, *)
private struct DurationLockScreenView: View {
    let context: ActivityViewContext<DurationAttributes>

    private var runningInterval: ClosedRange<Date> {
        let end = context.state.endDate ?? .now
        return context.state.startDate...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name = context.state.profileDisplayName, name.isEmpty == false {
                Text(name)
                    .font(.headline)
                    .privacySensitive()
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(context.state.actionType)
                        .font(.title3.weight(.semibold))
                        .privacySensitive()

                    Text(timerInterval: runningInterval, countsDown: false)
                        .monospacedDigit()
                        .font(.title2)
                        .privacySensitive()
                }

                Spacer(minLength: 12)

                StopActionButton(
                    actionID: context.state.activityID,
                    style: .title,
                    postHogLabel: "duration_stop_button_liveActivity_lockScreen"
                )
            }

            if let note = context.state.notePreview, note.isEmpty == false {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetURL(widgetURL)
    }

    private var widgetURL: URL? {
        URL(string: "nannyme://activity/\(context.attributes.activityID.uuidString)")
    }
}

@available(iOS 17.0, *)
private struct StopActionButton: View {
    enum Style {
        case title
        case iconOnly
    }

    let actionID: UUID
    let style: Style
    let postHogLabel: String

    @ViewBuilder
    var body: some View {
        if let stopURL {
            Link(destination: stopURL) {
                label
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .postHogLabel(postHogLabel)
            .privacySensitive(false)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .title:
            Label {
                Text(WidgetL10n.Common.stop)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "stop.fill")
            }
            .labelStyle(.titleAndIcon)
        case .iconOnly:
            Image(systemName: "stop.fill")
                .symbolVariant(.fill)
                .accessibilityLabel(WidgetL10n.Common.stop)
        }
    }

    private var stopURL: URL? {
        URL(string: "nannyme://activity/\(actionID.uuidString)/stop")
    }
}
