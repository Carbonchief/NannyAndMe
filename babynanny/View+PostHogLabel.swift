import SwiftUI

extension View {
    /// Applies a PostHog analytics label to the view by mirroring the value in the accessibility identifier.
    /// - Parameter value: The analytics label describing the interaction target.
    /// - Returns: A view tagged with the provided analytics label.
    func postHogLabel(_ value: String) -> some View {
        accessibilityIdentifier("posthog:\(value)")
    }
}
