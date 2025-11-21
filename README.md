# NannyAndMe

NannyAndMe is a SwiftUI-based iOS application that helps caregivers keep track of a baby's daily routine. The app provides a unified log for sleep sessions, diaper changes, and feedings while giving caregivers quick access to recent activity, stats, and configurable profiles.

## Features

- **Unified care log** – Start and stop timers for sleep, diaper, and feeding actions while recording key metadata such as diaper type, feeding method, and bottle volume.
- **Recent history** – View a chronological list of the latest actions with friendly descriptions and formatted timestamps.
- **Home preferences** – Choose whether the recent activity list appears on the Home tab via Settings.
- **Context-aware controls** – Automatically surface active timers, offer start/stop buttons per category, and present configuration sheets when additional details are required.
- **Profile switching** – Manage multiple baby profiles via an in-app profile switcher with dedicated avatars.
- **Profile photos** – Choose, crop, and automatically optimize profile pictures for each child.
- **Profile metadata persistence** – Save profile names and avatars locally with SwiftData so changes stick between launches.
- **Settings and stats views** – Review caregiver preferences and explore insights like weekly trends and daily patterns.
- **RevenueCat subscriptions** – Unlock premium functionality through RevenueCat's SDK, hosted paywalls, and Customer Center management tools.
- **Monthly age reminders** – Receive 10 a.m. notifications on each child's monthly milestones, with combined alerts when multiple profiles share the same celebration.
- **Action reminders** – Get configurable notifications for sleep, diaper, and feeding actions with per-action intervals that reset whenever you log an entry.
- **First-launch onboarding** – Celebrate new caregivers, highlight the core benefits, and introduce the Premium free trial with a dedicated welcome flow.
- **Optional location logging** – Capture where each action was recorded and surface that context alongside entries when location tracking is enabled in Settings.
- **Action map** – Explore logged locations on a clustered map with quick date and action filters whenever location tracking is enabled.
- **Data sharing** – Export the active profile's logs to JSON and merge imports that include new or updated entries.
- **Localized experience** – Navigate the interface in English, German, or Spanish with fully translated caregiver-facing text.
- **Supabase authentication** – Use the side menu to sign in or automatically create a Supabase account and prepare for cloud-powered features.

## Project structure

```
NannyAndMe/
├── README.md
├── AGENTS.md
├── babynanny/                # Application source code and SwiftUI views
│   ├── ActionLogViewModel.swift
│   ├── ContentView.swift
│   ├── HomeView.swift
│   ├── ProfileStore.swift
│   ├── ProfileAvatarView.swift
│   ├── ProfileSwitcherView.swift
│   ├── SettingsView.swift
│   ├── SideMenu.swift
│   ├── ReportsView.swift
│   └── babynannyApp.swift
├── babynanny.xcodeproj       # Xcode project definition
├── babynannyTests/           # Unit test target (empty scaffold)
└── babynannyUITests/         # UI test target (empty scaffold)
```

## Requirements

- macOS with Xcode 16 (or newer) installed
- iOS 18 SDK (included with Xcode 16)
- Swift 6 toolchain (bundled with the listed Xcode version)
- Apple Developer account (required for running on devices)

## Getting started

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd NannyAndMe
   ```
2. **Open the project**
   ```bash
   open babynanny.xcodeproj
   ```
3. **Resolve Swift Package dependencies**
   ```bash
   xcodebuild -resolvePackageDependencies -project babynanny.xcodeproj
   ```
4. **Configure Supabase credentials**
   - Open `babynanny/SupabaseConfig.plist`.
   - Replace the placeholder URL and anonymous key with the values from your Supabase project.
   - Keep your real credentials out of commits (e.g., by resetting the file before pushing).
   - Add `nannyme://auth/verify` to your Supabase project's list of allowed redirect URLs so email verification links reopen the app.
5. **Configure PostHog analytics**
   - Open `babynanny/PostHogConfig.plist`.
   - Provide your PostHog project API key, preferred host (e.g., `https://us.i.posthog.com`), and whether autocapture should be enabled.
   - Keep production credentials out of source control; prefer per-developer overrides or CI-provided values.
6. **Configure RevenueCat**
   - Add the app to your RevenueCat project and replace the public API key in `babynannyApp` when you move beyond the provided test key.
   - Create an entitlement named **Nanny & Me Pro** so it matches `RevenueCatSubscriptionService.entitlementID`.
   - Add the App Store products `NAMlifetime` (lifetime) and `NAMWeekly` (weekly) to RevenueCat, then include them in your primary offering and attach a hosted paywall design.
   - Enable RevenueCat's Customer Center so the in-app "Manage subscription" button can present change-plan and cancellation options.
   - Sync offerings after you update them so the SwiftUI paywall receives the latest configuration.
7. **Enable push notifications**
   - In the **Signing & Capabilities** tab for the `babynanny` target, confirm that the **Push Notifications** capability is enabled.
   - Upload an APNs key or certificate for your Apple Developer account and ensure the bundle identifier used by the app matches the identifier on that key/certificate.
   - Update the `aps-environment` entitlement (currently set to `development`) if you need to ship a production build.
   - Run the app on a physical device to obtain an APNs token (logged by the application delegate) and register it with your push provider.
8. **Run the app**
   - Select the `babynanny` scheme.
   - Choose an iOS Simulator device (e.g., iPhone 15 Pro) or a physical device when testing remote notifications.
   - Press <kbd>Cmd</kbd>+<kbd>R</kbd> to build and run.
8. **That's it.** The app stores data locally; no additional iCloud setup is required. Supabase authentication is optional but enables future connected features.

## Testing

Run the unit or UI test suites from Xcode with <kbd>Cmd</kbd>+<kbd>U</kbd>, or from the command line:

```bash
xcodebuild test \
  -project babynanny.xcodeproj \
  -scheme babynanny \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## Development tips

- The `ActionLogViewModel` owns the state for active timers and the recent history list. Extend this type when adding new care categories or data persistence.
- `BabyActionSnapshot` models encapsulate formatting helpers (e.g., duration and timestamp descriptions). Keep new derived values inside this struct for consistency.
- UI components prefer dependency injection via `@EnvironmentObject` (`ProfileStore`) or `@StateObject` (`ActionLogViewModel`). Follow this pattern to maintain predictable SwiftUI state flows.
- Preview your SwiftUI views regularly with the included `#Preview` providers to ensure layouts render correctly on different device sizes.

## FAQ

### Can I add Siri commands to start my actions?

Siri Shortcuts are not currently integrated in the project. To support voice-triggered actions, you would need to add an App Intents extension (or legacy SiriKit intent definitions) that exposes the relevant start/stop log actions, handle those intents in a shared module, and update the app's entitlement and Info.plist declarations accordingly. Until those additions are made the app will not respond to Siri commands.

## Contributing

1. Create a new feature branch: `git checkout -b feature/amazing-change`.
2. Make your updates and add or adjust tests when appropriate.
3. Ensure the project builds and the tests pass.
4. Open a pull request describing the change and any manual testing performed.

## License

This project currently has no explicit license. Please add one before distributing the application outside your organization.
