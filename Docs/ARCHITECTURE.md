# Architecture Overview

## SwiftData model graph

The app persists all user state with SwiftData models that mirror the care log domain:

- `Profile` (`ProfileActionStateModel` alias) is the root entity. It owns profile metadata and an ordered collection of `BabyAction` objects.
- `BabyAction` (`BabyActionModel` alias) represents an individual sleep/feeding/diaper event. Each action keeps a stable `UUID` identifier and timestamps normalized to UTC so local merges remain deterministic.

Relationships use SwiftData's inverse tracking so that deleting a profile cascades to its actions while individual actions can safely be re-parented. Each model stores a defaulted `UUID` identifier so persisted histories remain stable even if records are exported and re-imported.

## Model container configuration

`AppDataStack.makeModelContainer` constructs a single `ModelContainer` for `Profile` and `BabyAction`. The `ModelConfiguration` stores data on device (optionally in-memory for previews/tests) and disables autosave. The same configuration is used everywhere in the app (main context, previews, tests) to avoid divergent schemas.

## Local persistence lifecycle

`AppDataStack` owns the shared `ModelContext` and exposes helpers to coalesce saves. UI layers call `scheduleSaveIfNeeded` and `saveIfNeeded` to throttle writes when the user makes rapid changes. All saves are gated by `ModelContext.hasChanges` and wrapped in lightweight logging so background sync work never blocks the main thread.

`ActionLogStore` observes the shared context for inserts/updates and keeps an in-memory cache keyed by profile. When a change notification arrives, the store rebuilds the cache so SwiftUI views can render without hitting disk. Profile metadata updates (name, avatar, birth date) stay in sync via `ProfileStore.synchronizeProfileMetadata`.

## Data export & import

The Share Data screen exports the active profile and its actions to JSON. Imports run through `ActionLogStore.merge` which deduplicates by action identifier, updates existing entries when timestamps differ, and appends new actions. Profile metadata merges through `ProfileStore.mergeActiveProfile`, ensuring imported names or avatars replace the local copy only when the incoming profile matches the active profile.

## Debug tooling

The Settings screen exposes switches for notification reminders, profile photo management, and action reminder previews. For runtime diagnostics the app logs SwiftData saves and merge operations via the unified logger (`com.prioritybit.babynanny.swiftdata`). Developers can inspect the console while interacting with the simulator to confirm writes succeed.
