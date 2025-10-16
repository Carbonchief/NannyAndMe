# Sync operations runbook

This document outlines how the NannyAndMe sync pipeline behaves and how to test or reset it during development.

## Push-driven updates

1. **SwiftData + CloudKit** – The app uses SwiftData's built-in CloudKit support with a private database. Every `ProfileActionStateModel` and `BabyActionModel` change is mirrored to the user's private zone.
2. **Subscriptions** – On launch the `SyncCoordinator` verifies that a database-wide `CKDatabaseSubscription` exists. If not, it creates one configured for silent pushes.
3. **Silent push handling** – When CloudKit delivers a push, `AppDelegate` forwards the payload to the `SyncCoordinator`. The coordinator deduplicates notification IDs, updates diagnostics, and schedules a debounced `fetchAndMergeChanges()` call on the shared `ModelContainer`.
4. **UI propagation** – SwiftData merges remote records into the local store, which triggers `NSPersistentStoreRemoteChange`. `ActionLogStore` listens for these notifications, rehydrates `ProfileStore` metadata, and the SwiftUI views refresh automatically through their environment objects or `@Query` readers.

## Resetting the local store (without touching iCloud)

Use this when you want to clear the on-device cache but preserve CloudKit data for the account:

1. Delete the app from the simulator or device.
2. In Xcode, choose **Product ▸ Run** to reinstall. SwiftData will bootstrap an empty store and repopulate it as CloudKit syncs down existing records.
3. If you only need to wipe data during a debug session, run `xcrun simctl erase <device>` to factory-reset the simulator.

> ⚠️ Avoid deleting records directly from the CloudKit Dashboard when testing; doing so may cause sync gaps for other testers.

## Testing push updates

1. Sign into the same iCloud account on two devices (simulator + device or two simulators).
2. Launch the app on both. Grant notification permission on the physical device.
3. On Device A, update a profile name or log a new action.
4. Observe Device B. Within seconds the UI should update without manual refresh. For debug builds, open **Settings ▸ Debug ▸ Sync Diagnostics** to confirm the push time stamp advanced.

## Common pitfalls

- **Duplicate subscriptions** – The coordinator fetches existing subscriptions at launch and only creates a new one when necessary, preventing CloudKit errors caused by duplicate IDs.
- **No-op saves** – `AppDataStack` checks `ModelContext.hasChanges` before saving, so toggling UI state without a data change will not trigger redundant sync traffic.
- **Conflict storms** – Each `BabyAction` carries an `updatedAt` timestamp. `ActionConflictResolver` chooses the newer timestamp (or the entry with the latest end date on ties), stopping ping-pong updates between devices.
- **Manual fetch loops** – All syncs are push-triggered or manually requested via `SyncCoordinator.requestSyncIfNeeded(reason:)`; there is no polling loop.

## Adding sharing later

`SyncCoordinator` isolates CloudKit touchpoints, making it straightforward to extend the stack with `CKShare`-based collaboration in the future. Implement share acceptance inside the coordinator and keep the existing private-database flow untouched.
