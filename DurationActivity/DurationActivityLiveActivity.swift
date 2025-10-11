//
//  DurationActivityLiveActivity.swift
//  DurationActivity
//
//  Created by Luan van der Walt on 2025/10/11.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DurationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DurationActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DurationActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension DurationActivityAttributes {
    fileprivate static var preview: DurationActivityAttributes {
        DurationActivityAttributes(name: "World")
    }
}

extension DurationActivityAttributes.ContentState {
    fileprivate static var smiley: DurationActivityAttributes.ContentState {
        DurationActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DurationActivityAttributes.ContentState {
         DurationActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DurationActivityAttributes.preview) {
   DurationActivityLiveActivity()
} contentStates: {
    DurationActivityAttributes.ContentState.smiley
    DurationActivityAttributes.ContentState.starEyes
}
