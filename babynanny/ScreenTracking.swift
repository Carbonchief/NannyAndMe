import SwiftUI

private struct PostHogScreenViewModifier: ViewModifier {
    let name: String
    let properties: [String: Any]
    @State private var hasFired = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                // fire once per appearance lifecycle
                guard !hasFired else { return }
                hasFired = true
                Analytics.screen(name, properties: properties)
            }
    }
}

public extension View {
    /// Attach to a top-level view of a screen
    func phScreen(_ name: String, properties: [String: Any] = [:]) -> some View {
        modifier(PostHogScreenViewModifier(name: name, properties: properties))
    }
}
