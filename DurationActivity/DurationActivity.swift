//
//  DurationActivity.swift
//  DurationActivity
//
//  Created by Luan van der Walt on 2025/10/11.
//

import WidgetKit
import SwiftUI

struct Provider: AppIntentTimelineProvider {
    private let dataStore = DurationDataStore()

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationAppIntent(),
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        let snapshot = dataStore.loadSnapshot() ?? .placeholder
        return SimpleEntry(date: Date(), configuration: configuration, snapshot: snapshot)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        let snapshot = dataStore.loadSnapshot() ?? .empty
        let entryCount = snapshot.hasActiveActions ? 60 : 1

        var entries: [SimpleEntry] = []
        for minute in 0 ..< entryCount {
            guard let entryDate = Calendar.current.date(byAdding: .minute, value: minute, to: now) else { continue }
            entries.append(SimpleEntry(date: entryDate, configuration: configuration, snapshot: snapshot))
        }

        if entries.isEmpty {
            entries.append(SimpleEntry(date: now, configuration: configuration, snapshot: snapshot))
        }

        let reloadInterval: TimeInterval = snapshot.hasActiveActions ? 10 * 60 : 15 * 60
        let reloadDate = now.addingTimeInterval(reloadInterval)
        return Timeline(entries: entries, policy: .after(reloadDate))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let snapshot: DurationWidgetSnapshot
}

struct DurationActivityEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    private var maxVisibleActions: Int {
        switch family {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 2
        default:
            return 3
        }
    }

    private var visibleActions: [DurationWidgetAction] {
        Array(entry.snapshot.actions.prefix(maxVisibleActions))
    }

    private var durationFont: Font {
        switch family {
        case .systemSmall:
            return .title3
        case .systemMedium:
            return .title3
        default:
            return .title2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visibleActions.isEmpty {
                Text(WidgetL10n.Duration.noActiveTimers)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(visibleActions) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(action.durationDescription(asOf: entry.date))
                            .font(durationFont)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}

struct DurationActivity: Widget {
    let kind: String = "DurationActivity"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            DurationActivityEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .systemMedium) {
    DurationActivity()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, snapshot: .placeholder)
    SimpleEntry(date: .now.addingTimeInterval(300), configuration: .smiley, snapshot: .placeholder)
}
