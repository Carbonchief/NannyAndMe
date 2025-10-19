# Multipeer Connectivity Architecture

```
ShareDataView ──▶ ShareDataViewModel ──▶ MPCManager
                                     ├─▶ MPCSessionController
                                     └─▶ MPCTransferController
```

* **ShareDataView** presents SwiftUI state, routes user intents, and displays peer lists, connection state,
  transfer progress, and historic status.
* **ShareDataViewModel** adapts the manager into SwiftUI-friendly `@Published` properties, prepares payloads, and
  coordinates profile/action exports. It is injected with closures to read the current profile and action state so it can be
  unit tested in isolation.
* **MPCManager** owns discovery (`MCNearbyServiceBrowser`), advertising (`MCNearbyServiceAdvertiser`), and an
  `MCSession`. It publishes session state transitions, pending invitations, transfer progress, and recovered errors. Stable
  `MCPeerID` values are persisted in `UserDefaults` under `mpc.peer.displayName`; the stored identifier appends a four-character
  suffix derived from `identifierForVendor` so devices with the same marketing name still negotiate unique peer identifiers.
* **MPCSessionController** wraps the `MCSessionDelegate` callbacks to keep a single-threaded state machine on the main
  actor. It forwards envelopes, resource progress, and failures to the manager/transfer controller.
* **MPCTransferController** is responsible for encoding/decoding envelopes, tracking resource progress with key-value
  observations, and raising high-level events (profile snapshot received, delta received, etc.).

## Service configuration

* Service type: `nanme-share`
* Discovery info keys:
  * `shortName`: sanitized device name (ASCII, trimmed to 60 characters, whitespace collapsed). Updated automatically when the
    user renames the device.
  * `prettyName`: Base64-encoded UTF-8 device name used for UI presentation so apostrophes and emoji survive discovery.
  * `appVersion`: value of `CFBundleShortVersionString` when available.
* Encryption preference: `.required` (default).

`Info.plist` now declares `NSLocalNetworkUsageDescription` and `_nanme-share._tcp` under `NSBonjourServices` so iOS
explains the local networking prompt the first time MPC browsing/advertising starts.

## Message envelope

```swift
struct MPCEnvelope: Codable {
    let version: Int           // Current: 1
    let type: MPCMessageType   // hello, capabilities, profileSnapshot, actionsDelta, ack, error
    let payload: Data          // Nested JSON payload
    let sentAt: Date
}
```

Payload types:

* `MPCHelloMessage` – display name + capability summary.
* `MPCCapabilitiesMessage` – supported envelope version & maximum resource size hint.
* `ProfileExportV1` – entire profile + `ProfileActionState` snapshot.
* `ActionsDeltaMessage` – subset of actions changed since the last sync.
* `MPCAcknowledgement` – UUID receipt + timestamp.
* `MPCErrorMessage` – human readable + optional remediation code.

Incoming envelopes with a higher version emit `MPCError.unsupportedEnvelopeVersion`, prompting the UI to show a graceful
compatibility message instead of crashing.

## Transfer strategy

* Small messages are encoded as JSON and delivered with `MCSessionSendDataMode.reliable`.
* Large payloads (profile exports) use `sendResource(at:withName:toPeer:)`, exposing transfer progress and estimated time
  remaining via `MPCTransferProgress`.
* All progress updates are published to the view model so the UI can render `ProgressView` rows and VoiceOver-friendly
  accessibility descriptions.
* Transfers can be cancelled from the Share Data page; cancellation requests call through to the underlying `Progress`
  instance so partially sent files are abandoned cleanly.

## Session lifecycle

```
.idle → .browsing / .advertising → .inviting → .connected → .disconnecting → .idle
```

* The manager automatically rejects new invitations when already connected to a different peer, surfacing a toast that
  explains why.
* Invitations time out after 15 seconds unless the user accepts or dismisses the dialog.
* When the app moves to the background the view model stops browsing; returning to foreground restarts discovery if the
  toggle remains enabled.

## Testing

Run the MPC unit tests with:

```bash
xcodebuild test -scheme babynanny -destination 'platform=iOS Simulator,name=iPhone 15'
```

The suite currently verifies:

* Envelope encode/decode round trips.
* Graceful handling of unsupported envelope versions.
* Transfer progress bookkeeping.

Manual QA checklist (two physical devices recommended):

1. Ensure both devices have Bluetooth + Wi-Fi enabled and are running the latest build.
2. Open **Share Data → Nearby Devices** on both devices.
3. Confirm each device discovers the other and shows the connect button.
4. Tap **Connect** on one device and accept the invitation on the other.
5. Send a full snapshot, verify the toast, and confirm the peer receives the data.
6. Trigger **Send recent changes** after adding a log entry; ensure the delta completes quickly.
7. Export a >1 MB profile and send it via **Send export file**; watch the transfer progress bar reach 100%.
8. Cancel an in-flight transfer from **Send** > progress row and confirm the toast appears and the progress row is cleared.
9. Toggle airplane mode mid-transfer to confirm the UI reports a failure and allows a retry.
10. Disconnect and reconnect to ensure the state machine returns to `.idle` cleanly.

## Limitations

* Background execution: browsing pauses while the app is inactive to conserve battery; advertising remains opt-in via the
  Advanced toggle.
* Payload size: resource transfers are practical up to ~15 MB. Larger exports should be shared via the existing file export
  flow.
* Simulator support: discovery requires physical hardware. Use two devices or a device + simulator (simulator cannot
  advertise).
* Logging: structured `os.Logger` messages omit personally identifiable information and only include sanitized peer
  names.

