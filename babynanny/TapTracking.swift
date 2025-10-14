import SwiftUI

public extension Button where Label == Text {
    /// Button("Title").phTap("did_tap_title") { ... }
    static func phTap(_ title: String,
                      event: String,
                      properties: [String: Any] = [:],
                      action: @escaping () -> Void) -> some View {
        Button(title) {
            Analytics.capture(event, properties: properties.merging(["$element_text": title]) { $1 })
            action()
        }
    }
}

public extension View {
    /// Wrap any action to capture an event before running the action
    func phOnTapCapture(event: String,
                        properties: [String: Any] = [:],
                        action: @escaping () -> Void) -> some View {
        Button(action: {
            Analytics.capture(event, properties: properties)
            action()
        }, label: { self })
        .buttonStyle(.plain)
    }

    /// Attach PostHog capture to an existing tappable control without rewriting the action
    func phCaptureTap(event: String,
                      properties: [String: Any] = [:]) -> some View {
        modifier(PostHogTapModifier(event: event, properties: properties))
    }
}

private extension Dictionary where Key == String, Value == Any {
    func merging(_ other: [String: Any], uniquingKeysWith: (Any, Any) -> Any) -> [String: Any] {
        var result = self
        for (k, v) in other {
            if let old = result[k] {
                result[k] = uniquingKeysWith(old, v)
            } else {
                result[k] = v
            }
        }
        return result
    }
}

private struct PostHogTapModifier: ViewModifier {
    let event: String
    let properties: [String: Any]

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                Analytics.capture(event, properties: properties)
            }
        )
    }
}
