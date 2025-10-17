# Manual QA Checklist

Use the following script to validate SwiftData + CloudKit syncing and sharing.

1. **Seed Device A**
   - Launch the app, create a profile, and log three actions (sleep, feeding, diaper).
   - Confirm entries appear on the Home and All Logs screens.
   - Open the debug panel (Settings → Debug) and verify the private scope shows three `BabyAction` records and one `Profile` record.

2. **Initial import on Device B**
   - Install the app with the same Apple ID on a clean device or simulator.
   - Wait for the sync overlay to disappear; the debug panel should report `Finished` with no outstanding changes.
   - Confirm the seeded profile and all three actions appear in Home/All Logs without manual refresh.

3. **Share the profile**
   - On Device A, open Settings → Share Profile and create a share.
   - Invite Device B (iCloud email) and accept the share prompt on Device B.
   - After acceptance, Device B's action lists should include the shared profile and existing logs.

4. **Live collaboration**
   - On Device B, edit one of the shared actions (change the duration or metadata).
   - Within seconds, Device A should reflect the edit (UI refresh happens automatically via SwiftData mirroring).
   - Add a new action on Device A; verify it appears on Device B after the push arrives.

5. **Modify participants**
   - On Device A, downgrade Device B to read-only, then remove the participant. Device B should lose access shortly after.
   - Stop sharing entirely and confirm Device A no longer lists the participant.

6. **Deletion cascade**
   - Delete the shared profile on Device A and confirm the actions disappear locally.
   - Verify Device B also loses access to the profile and actions once CloudKit processes the deletion.

7. **Diagnostics sanity**
   - In the debug panel, use "Force mirror refresh" to trigger a manual sync and observe the status flipping to `Importing` before returning to `Finished`.
   - Tap "Dump counts per scope" and confirm the private and shared counts match expectations (no orphaned records).
