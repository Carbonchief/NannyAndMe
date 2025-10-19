import SwiftUI

private struct PostHogLabelModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        content.accessibilityIdentifier("posthog." + label)
    }
}

extension View {
    func postHogLabel(_ label: String) -> some View {
        modifier(PostHogLabelModifier(label: label))
    }
}
