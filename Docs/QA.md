# Manual QA Checklist

Use the following script to validate core functionality after local-only persistence changes.

1. **Seed base data**
   - Launch the app, rename the default profile, and add a profile photo.
   - Log sleep, feeding, and diaper actions. Confirm entries appear on the Home and All Logs screens.
   - Toggle the "Show recent activity on Home" setting and verify the Home view updates accordingly.

2. **Reminder workflows**
   - Enable action reminders for the active profile.
   - Use the custom reminder preview button for each category and confirm notifications arrive (requires notification permission).
   - Log an action and ensure the related reminder toggle resets the override.

3. **Location tracking**
   - Enable "Track action locations" in Settings. Grant location access when prompted.
   - Log a new action and verify the All Logs list shows a location badge and location details in the entry drawer.

4. **Share Data iCloud sharing/import**
   - From **Settings ▸ Share Data**, tap **Manage invites** and send an invitation using the iCloud sharing sheet.
   - Accept the invitation on a second device/account and confirm the shared profile appears after the sync completes.
   - Tap **Stop sharing** on the origin device and verify the shared profile disappears for invitees.
   - Import a previously exported JSON file and verify the profile details and logged actions return without duplicates.

5. **Profile management**
   - Add a second profile and switch between profiles using the avatar button.
   - Delete the secondary profile and ensure the active profile falls back to the original one.

6. **Duration Activity shortcuts**
   - Start a duration action (e.g., sleep) and leave it running.
   - Trigger the custom URL scheme `nannyme://activity/<action-id>/stop` from Safari or the debugger to ensure the action stops.

7. **Share Data external import prompt**
   - With the app in the foreground, deliver a JSON export from another device (AirDrop, Messages, or Files).
   - Confirm the Share Data sheet appears automatically and completing the import merges new actions without duplicating existing entries.
