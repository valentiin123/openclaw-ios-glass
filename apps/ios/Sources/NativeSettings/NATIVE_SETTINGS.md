# NativeSettings: native SwiftUI replacements for the Settings WebView pages

Nothing outside `apps/ios/Sources/NativeSettings/` references these files yet. Integration is a small, explicit step (below).

## Files

| File | Purpose |
| --- | --- |
| `NativeSettingsSupport.swift` | `NativeSettingsDestination`, JSON/Gateway helpers, `NativeSettingsLoader`, shared rows/pages |
| `NativeSettingsRouter.swift` | `NativeSettingsRouter`: destination -> screen, path lookup |
| `NativeAppearanceScreen.swift` | Appearance (local `AppAppearanceModel`) |
| `NativeNotificationsScreen.swift` | Notifications (UserNotifications, local) |
| `NativePermissionsScreen.swift` | Device permissions (local, via `IOSDeviceSettingsPermissions`) |
| `NativeTalkVoiceScreen.swift` | Talk & Voice (local toggles + Gateway read-only summary) |
| `NativeChannelsScreen.swift` | Channels (Gateway `channels.status`, read-only) |
| `NativeSkillsScreen.swift` | Skills (Gateway `skills.status`, `skills.update` enable/disable) |

## Integration points (to do outside this folder)

1. `apps/ios/Sources/Native/NativeDestinations.swift`, `NativeDestinationRouter`:
   - In `hasNativeScreen(for:)`, also return `true` when `NativeSettingsRouter.hasNativeScreen(forPath: path)`.
   - In `body`, before the `default:` branch, add:
     ```swift
     default:
         if let native = NativeSettingsRouter.screen(
             forPath: self.path,
             headerSidebarAction: self.headerSidebarAction)
         {
             native
         } else {
             DashboardPageScreen(...)
         }
     ```
2. `apps/ios/Sources/RootTabs.swift` (`.notificationSettings(path)` sheet around line 689): the sheet currently presents `DashboardPageScreen` for notifications. Replace with
   `NativeSettingsRouter(destination: .notifications, embedded: false)` wrapped with a Done toolbar button
   (the screen's `NativeSettingsPage` adds only the sidebar item, not a close button).
3. `DashboardPageScreen.root`: optional early return of `NativeSettingsRouter.screen(forPath:)` so every entry point benefits.
4. Mapped Dashboard paths (from `DashboardRouteMap`): `/settings/appearance`, `/settings/device/permissions`,
   `/settings/channels`, `/skills`. Notifications and Talk & Voice have **no verified route constant**; call the router with the
   destination directly.
5. `embedded: true` skips the screen's own `NavigationStack` (use inside an existing stack / `navigationDestination`).
6. Environment required: `NodeAppModel` (all Gateway screens), `AppAppearanceModel` (Appearance).

## Gateway methods

Verified in `src/gateway/methods/core-descriptors.ts` and/or `packages/gateway-protocol/src/schema`:

- `channels.status` (operator.read; params `probe?`, `timeoutMs?`, `channel?`; result `channelOrder`, `channelLabels`, `channelAccounts`, `statusIssues`...)
- `skills.status` (operator.read; params `agentId?`, `sessionKey?`, `refresh?`; entry shape taken from `OpenClawKit/SkillManagement.swift` `SkillStatus`)
- `skills.update` (operator.admin; params `skillKey` + `enabled?`)
- `talk.config` (params `includeSecrets?`; result `config.talk.{provider,speechLocale,interruptOnSpeech,silenceTimeoutMs}`)
- `voicewake.get` (operator.read; iOS decodes `{ "triggers": [String] }` in `VoiceWakePreferences.decodeGatewayTriggers`)

Not verified / not used: `skills.list` (no match in the repo), `config.get` / `config.patch` result shapes beyond the
parity fixture (`config`, `raw`, `hash`, `valid`, `issues`) and `voicewake.set` params (no schema found). No write path
through `config.patch` is implemented.

## Not reproduced from the web pages

- Skills: ClawHub search/install, archive upload, API key and env editing, install options, per-agent selection.
- Channels: login/logout/start/stop, pairing approval, per-channel config editing, probe controls.
- Talk & Voice: editing provider/voice/locale/silence (Gateway values are read-only), trigger-word editing (`voicewake.set` unverified), TTS provider selection.
- Notifications: Gateway-side push categories and `push.test`.
- Permissions: Accessibility, Screen Recording, Event Posting (macOS-only); Location mode editing.

## Design rules followed

`OpenClawType` only, `String(localized:)` for strings built in code, opaque `List` surfaces (glass only through shared
components), 44pt rows, `accessibilityElement(children: .combine)` on rows, shared spring / Reduce Motion through existing
components, annotated closures and typed `let`s to avoid type-checker blowups.
