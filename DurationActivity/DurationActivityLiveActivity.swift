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
        let runningInterval: ClosedRange<Date> = {
            let end = context.state.endDate ?? .now
            return context.state.startDate...end
        }()

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading) {
                    if let name = context.state.profileDisplayName, name.isEmpty == false {
                        Text(name)
                            .font(.headline)
                            .privacySensitive()
                    }

                    Text(context.state.actionType)
                        .font(.subheadline)
                        .privacySensitive()
                }
            }

            DynamicIslandExpandedRegion(.trailing) {
                Text(timerInterval: runningInterval, countsDown: false)
                    .font(.title2.monospacedDigit())
                    .privacySensitive()
            }

            DynamicIslandExpandedRegion(.bottom) {
                if let note = context.state.notePreview, note.isEmpty == false {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .privacySensitive()
                }
            }
        } compactLeading: {
            Image(systemName: "stopwatch")
                .accessibilityLabel(context.state.actionType)
        } compactTrailing: {
            Text(timerInterval: runningInterval, countsDown: false)
                .font(.caption2.monospacedDigit())
                .privacySensitive()
        } minimal: {
            Image(systemName: "stopwatch")
                .accessibilityLabel(context.state.actionType)
        }
        .widgetURL(
            URL(string: "nannyme://activity/\(context.attributes.activityID.uuidString)")
        )
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

            Text(context.state.actionType)
                .font(.title3.weight(.semibold))
                .privacySensitive()

            Text(timerInterval: runningInterval, countsDown: false)
                .monospacedDigit()
                .font(.title2)
                .privacySensitive()

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
