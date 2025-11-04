# Agent Instructions

These guidelines apply to the entire `NannyAndMe` repository.

## Swift code style
- Use four spaces for indentation and keep line lengths under ~120 characters.
- Prefer Swift's modern concurrency and property wrappers (e.g., `@MainActor`, `@StateObject`, `@EnvironmentObject`) when managing view state.
- Avoid force unwrapping optionals; favor safe binding (`if let` / `guard let`) and sensible defaults.
- Keep view logic lightweight. Extract reusable SwiftUI components or view models when a view exceeds ~200 lines.
- Always use the modern onChange syntax introduced in iOS 17.

## Localization
- When introducing user-facing text, update the shared localization helpers and provide translations for all supported languages (English, German, and Spanish).

## Documentation
- Update `README.md` when adding new features, configuration steps, or architectural changes.
- Document any new public types or view models with Swift documentation comments (`///`).

## Testing
- Add unit or UI tests for new functionality when practical. Prefer lightweight view model tests over UI tests when logic can be isolated.

## Assets & previews
- Keep asset catalog names descriptive and organized by feature area.
- Maintain SwiftUI previews for new views to aid quick iteration. Use mock data objects where necessary.
