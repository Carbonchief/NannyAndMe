# Architecture Overview

## SwiftData model graph

The app persists all user state with SwiftData models that mirror directly to CloudKit:

- `Profile` (`ProfileActionStateModel` alias) is the root entity. It owns profile metadata and an ordered collection of `BabyAction` objects.
- `BabyAction` (`BabyActionModel` alias) represents an individual sleep/feeding/diaper event. Each action keeps a stable `UUID` identifier and timestamps normalized to UTC.

Relationships use SwiftData's inverse tracking so that deleting a profile cascades to its actions while individual actions can safely be re-parented. Each model stores a defaulted `UUID` identifier so CloudKit mirroring can restore stable identities without relying on SwiftData's unique-constraint attribute, which CloudKit mirroring does not support.

## Model container configuration

`AppDataStack.makeModelContainer` constructs a single `ModelContainer` for `Profile` and `BabyAction`. The `ModelConfiguration` attaches to the CloudKit container `iCloud.com.prioritybit.babynanny` with `.cloudKitDatabase(.both)` so SwiftData automatically mirrors the private and shared scopes. The same configuration is used everywhere in the app (main context, previews, tests) to avoid data islands.

## CloudKit mirroring lifecycle

`SyncStatusViewModel` consumes an async event stream sourced from either the real `CloudKitSyncMonitor` SPI (when the toolchain exposes it) or a fallback `CloudKitSyncMonitorCompat` shim that synthesizes a final idle event. The view model publishes a `State` enum that drives:

- A blocking overlay (`SyncStatusOverlayView`) during first-run imports.
- Status indicators in the new debug diagnostics panel.
- Force-refresh and timeout handling for manual sync attempts.

Remote notifications are funneled through `SyncCoordinator`, which still prepares CloudKit database subscriptions and triggers additional fetches when APNs wake the app. The coordinator and status view model share the main `ModelContext` so updates are reflected immediately.

## Sharing flow

`CloudKitSharingManager` now relies on SwiftData's built-in share support. When a share is requested it calls `ModelContext.share(_:)`, applies metadata (title/thumbnail), saves, and records the share's `CKShare` identifiers in `ShareMetadataStore`. Participant mutations reuse the stored share record ID and send minimal `CKModifyRecordsOperation` updates—no custom record zones or manual child record syncing are necessary. Because profiles own their actions through SwiftData relationships, sharing a profile automatically includes every associated action.

`ShareProfilePageViewModel` asks the manager for the share and presents participants via the standard `CKShare` interface. Updates, removals, and stop-sharing requests flow through the same manager so the UI reacts as soon as CloudKit confirms the change. Since SwiftData mirrors shared zones, collaborators see updates without custom fetch logic.

## Debug tooling

Under `#if DEBUG`, `SyncDiagnosticsView` combines information from `SyncCoordinator`, `SyncStatusViewModel`, and the CloudKit container. Developers can:

- Inspect account status, last push, and last successful sync.
- Review the current CloudKit monitor phase and model progress.
- Trigger a manual sync or dump record counts for the private and shared databases.

The view is accessible from Settings → Debug and complements the overlay that end users see during long imports.
