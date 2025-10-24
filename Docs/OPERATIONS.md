# Data operations runbook

This document outlines how NannyAndMe stores data locally and how to back it up or reset it during development.

## Local storage

1. **SwiftData on-device** – The app keeps all profiles and actions in a single SwiftData store located in the app's sandbox. There is no automatic cloud mirroring.
2. **Explicit saves** – `AppDataStack` coalesces save operations so bursts of edits (e.g., logging multiple actions quickly) do not block the main thread.
3. **Model notifications** – `ActionLogStore` listens for SwiftData context changes to refresh in-memory caches that drive the UI.

## Resetting the local store

Use this when you want to clear on-device data and start from a clean slate:

1. Delete the app from the simulator or device.
2. Reinstall via Xcode (**Product ▸ Run**) or the debugger. SwiftData will bootstrap an empty store and create a placeholder profile on first launch.
3. Alternatively, run `xcrun simctl erase <device>` to factory-reset the simulator.

> ⚠️ Removing the app also deletes any locally exported JSON backups unless they were copied outside the sandbox.

## Exporting and importing data

1. Open **Settings ▸ Share Data**.
2. Tap **Export** to create a JSON archive of the active profile and its actions. You can AirDrop the file or store it with Files.app.
3. Tap **Import** to merge a previously exported archive. The merge routine deduplicates by action identifier and updates existing entries when timestamps or metadata differ.

## Troubleshooting tips

- **Missing reminders** – Ensure notification permissions are granted and that the active profile has reminders enabled. Use the reminder preview buttons in Settings to schedule a test notification.
- **Location logging** – Location details appear only when system authorization is granted and the "Track action locations" toggle is on. If a reminder highlights denied access, use the provided button to jump to iOS Settings.
- **JSON import conflicts** – If an import reports a mismatched profile error, confirm that the archive was exported for the currently active profile. The app prevents cross-profile merges to avoid accidental overwrites.
