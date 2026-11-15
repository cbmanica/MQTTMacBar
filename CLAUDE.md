# MQTTMacBar — Claude Code Guide

## Build commands

```bash
make build      # compile (no code signing)
make run        # build + launch
make kill       # stop running instance
make restart    # kill + build + launch
make install    # build + copy to ~/Applications (required for Launch at Login)
```

## File registration

Xcode auto-discovers all `.swift` files in `MQTTMacBar/`. Adding a new `.swift` file does **not** require editing `project.pbxproj`.

## Data flow

```
CocoaMQTT delegate
  → MqttManager.clientDidReceiveMessage
    → StatusBarController.clientDidReceiveMessage   (dispatched to main)
      → SubscriptionStats.recordMessage             (stats object)
      → StatusBarContentView.setContent             (menu bar display)
      → rebuildInfoItems                            (dropdown menu)

TopicDiscoveryManager (separate CocoaMQTT client)
  → ingestMessage → TopicNode tree → TopicPickerView (FlatNode flat list)

ConnectionSettingsView / TopicSubscriptionsView
  → UserDefaults (broker, port, useSSL, subscriptions)
  → KeychainManager (username, password)
  → onSave closure → StatusBarController.restartMqtt
```

## No-regress patterns

**Multi-monitor rendering** (`StatusBarContentView` in `StatusBarController.swift`)
- `StatusBarContentView` is a private `NSView` added as a subview of each `NSStatusBarButton`
- `layout()` fires with correct bounds for each monitor — do not replace with KVO on `button.frame`
- `button.attributedTitle` is kept as clear-colored text for width measurement only; `draw()` renders the visible version

**Flat-list tree** (`TopicPickerView.swift`)
- Uses `FlatNode` array + manual depth indentation instead of `DisclosureGroup` or `OutlineGroup`
- `DisclosureGroup` inside recursive custom view structs in `List` causes leaf nodes to escape hierarchy — do not revert
- `treeVersion: Int` param on `TopicRowView` forces SwiftUI to re-render grandparent rows when descendant counts change; must be kept

**Thread rule**
- `SubscriptionStats` must only be mutated on `DispatchQueue.main`
- `TopicDiscoveryManager.ingestMessage` must only be called on main (all callers already dispatch)

## Known Xcode quirks

- **SourceKit "No such module CocoaMQTT"** — indexer artifact only; `make build` always succeeds
- **Keychain prompts on every Debug rebuild** — ACLs tied to binary signature; gone with a stable signing identity or `make install`
- **Cross-file "Cannot find type"** — same indexer artifact; build succeeds

## Test target

No unit test target exists yet. To add one: Xcode → File → New → Target → macOS Unit Testing Bundle, name it `MQTTMacBarTests`. Once created, test files can be added to `MQTTMacBar/MQTTMacBarTests/`.

Testable pure logic lives in:
- `MessageDiff.swift` — `buildDiffLines`, `anyToString`, `prettyPrintJSON`
- `TopicNode.swift` — `descendantLeafCount`, `latestDescendantUpdate`
- `MqttManager.swift` — `static matchesTopic`, `static extractValue`
- `TopicSubscription.swift` — `Codable` round-trip

## Security notes

- TLS is opt-in via the "Use SSL/TLS" toggle in Connection Settings (stored as `mqttUseSSL` in UserDefaults, default `false`)
- Credentials (username/password) stored in macOS login keychain, not UserDefaults
- `TopicDiscoveryManager` limits topic depth to 10 levels to prevent memory exhaustion from malicious brokers
