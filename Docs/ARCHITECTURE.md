# Architecture Overview

## SwiftData model graph

The app persists all user state with SwiftData models that mirror directly to CloudKit:

- `Profile` (`ProfileActionStateModel` alias) is the root entity. It owns profile metadata and an ordered collection of `BabyAction` objects.
- `BabyAction` (`BabyActionModel` alias) represents an individual sleep/feeding/diaper event. Each action keeps a stable `UUID` identifier and timestamps normalized to UTC.

Relationships use SwiftData's inverse tracking so that deleting a profile cascades to its actions while individual actions can safely be re-parented. Each model stores a defaulted `UUID` identifier so CloudKit mirroring can restore stable identities without relying on SwiftData's unique-constraint attribute, which CloudKit mirroring does not support.

## Model container configuration

`AppDataStack.makeModelContainer` constructs the shared `ModelContainer` for `Profile` and `BabyAction`. When CloudKit sync is
enabled the `ModelConfiguration` attaches to the container `iCloud.com.prioritybit.nannyandme`, otherwise it falls back to a
purely local store (used for previews, tests, and the bootstrap placeholder container) to avoid registering multiple CloudKit
mirroring delegates for the same store.

## CloudKit mirroring lifecycle

`SyncStatusViewModel` consumes an async event stream sourced from either the real `CloudKitSyncMonitor` SPI (when the toolchain exposes it) or a fallback `CloudKitSyncMonitorCompat` shim that synthesizes a final idle event. The view model publishes a `State` enum that drives:

- A non-blocking sync message anchored to the bottom of `HomeView` during first-run imports.
- Status indicators in the new debug diagnostics panel.
- Force-refresh and timeout handling for manual sync attempts.

Remote notifications are funneled through `SyncCoordinator`, which still prepares CloudKit database subscriptions and triggers additional fetches when APNs wake the app. The coordinator and status view model share the main `ModelContext` so updates are reflected immediately.

## Sharing flow

`CloudKitSharingManager` provisions shares by talking directly to CloudKit. It looks for previously cached `CKShare` identifiers, fetches the associated records when possible, and falls back to creating a new share with `CKShare(rootRecord:)`. The manager persists share metadata via `ShareMetadataStore` so future lookups avoid redundant network work. Participant mutations reuse the stored record identifiers and send targeted `CKModifyRecordsOperation` updates, while stop-sharing tears down the share record and its custom zone. Every profile lives in a dedicated zone named `profile-<UUID>` that contains one `CD_Profile` root record plus `CD_BabyAction` children. `CloudKitRecordMapper` keeps the CloudKit payload in sync with SwiftData models, and `AppDataStack` schedules a background export after each save so shared zones remain current.

`ShareProfilePageViewModel` asks the manager for the share and presents participants via the standard `CKShare` interface. Updates, removals, and stop-sharing requests flow through the same manager so the UI reacts as soon as CloudKit confirms the change. Since SwiftData mirrors shared zones, collaborators see updates without custom fetch logic.

## Debug tooling

Under `#if DEBUG`, `SyncDiagnosticsView` combines information from `SyncCoordinator`, `SyncStatusViewModel`, and the CloudKit container. Developers can:

- Inspect account status, last push, and last successful sync.
- Review the current CloudKit monitor phase and model progress.
- Review shared zones, cached change tokens, and subscription identifiers, and trigger a manual shared-zone fetch for debugging.
- Trigger a manual sync or dump record counts for the private and shared databases.

The view is accessible from Settings → Debug and complements the inline footer that end users see during long imports.
