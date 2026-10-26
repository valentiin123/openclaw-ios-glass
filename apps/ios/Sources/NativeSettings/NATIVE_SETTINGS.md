# NativeSettings: native SwiftUI replacements for the Settings WebView pages

These screens are used by `Settings/SettingsHubScreen.swift` (the hub pushes `NativeSettingsRouter(destination:embedded:true)` directly) and by `Native/NativeDestinations.swift` (via `NativeSettingsRouter.screen(forPath:)`).

Design: the hub has five groups.

- Connection: Gateway, Approvals, Gateway status
- Appearance
- Notifications (+ Permissions)
- Agents: Talk & Voice, Channels, Skills
- About: Diagnostics, Licenses, About

Content sits on opaque list surfaces. Liquid Glass is only used through shared controls (`OpenClawGlassButton`, `OpenClawGlassSegmented`). One shared spring (`OpenClawMotion`), Reduce Motion honored, 44 pt targets, Dynamic Type (the row stacks its pill under the text at accessibility sizes), VoiceOver labels via combined accessibility elements, swipe actions and context menus (copy) where useful. Every screen accepts `onClose` to show a Done button when presented as a sheet.

Shared gestures and feedback (`Native/Glass/`):

- `GlassToastModel` + `glassToastHost(_:)`: one glass capsule toast ("Copied") with the shared spring, a VoiceOver announcement and a success haptic. `NativeSettingsPage` owns one toast per page and injects it into the environment.
- `glassCopySwipe(_:)` / `glassCopyMenu(_:)` / `glassActionsMenu(copying:actions:)`: trailing swipe and long-press menu. `nativeSettingsCopySwipe` / `nativeSettingsCopyMenu` delegate to them. Use `glassActionsMenu` when a row needs extra actions (Skills: Enable/Disable + Copy key; Permissions: Allow + Open iOS Settings).
- Pull-to-dismiss is intentionally NOT added to these pages: sheets already dismiss by drag, and the 140 pt grab zone of `chatPullToDismiss` would compete with `refreshable` on the lists. The Done button stays the primary way out.
- `NativeSettingsInlineState` cross-fades between loading, error and content (`phase` drives the animation because `NativeLoadState` is not Equatable).

## Files

| File | Purpose |
| --- | --- |
| `NativeSettingsSupport.swift` | `NativeSettingsDestination`, JSON/Gateway helpers, `NativeSettingsLoader`, shared rows/pages |
| `NativeSettingsRouter.swift` | `NativeSettingsRouter`: destination -> screen, path lookup |
| `NativeAppearanceScreen.swift` | Appearance (local `AppAppearanceModel`) |
| `NativeNotificationsScreen.swift` | Notifications (UserNotifications, local only) |
| `NativePermissionsScreen.swift` | Device permissions (local, via `IOSDeviceSettingsPermissions`) |
| `NativeTalkVoiceScreen.swift` | Talk & Voice: local toggles, Gateway values editable through `NativeTalkConfigWriter`, `voicewake.get/set` |
| `NativeTalkConfigWriter.swift` | Talk config write path: `config.get` for the hash, then a `config.patch` merge patch (see below) |
| `NativeChannelsScreen.swift` | Channels list (`channels.status`) |
| `NativeChannelDetailScreen.swift` | Channel detail: start / stop / logout |
| `NativeChannelPairingScreen.swift` | Pairing requests: list / approve / dismiss |
| `NativeSkillsScreen.swift` | Skills (`skills.status`, `skills.update` enable/disable) |
| `NativeSkillsSearchScreen.swift` | ClawHub search and install (`skills.search`, `skills.install`) |
| `NativeSkillSecretsScreen.swift` | Per-skill API key and env editor (`skills.update` with `apiKey` / `env`) |
| `NativeGatewayStatusScreen.swift` | Read-only Gateway host and health (`system.info`, `health`) |

## Gateway methods

Taken from `src/gateway/methods/core-descriptors.ts` and `packages/gateway-protocol/src/schema`. Scopes are only confirmed where noted.

| Method | Use | Notes |
| --- | --- | --- |
| `channels.status` | Channels list | operator.read; params `probe?`, `timeoutMs?`, `channel?` |
| `channels.start` / `stop` / `logout` | Channel detail | scope not re-verified |
| `channels.pairing.list` / `approve` / `dismiss` | Pairing screen | scope not re-verified |
| `skills.status` | Skills list | operator.read; params `agentId?`, `sessionKey?`, `refresh?` |
| `skills.update` | Enable/disable, API key, env | operator.admin; params `skillKey` + `enabled?`, `apiKey?`, `env?` |
| `skills.search` / `skills.install` | ClawHub | scope not re-verified |
| `talk.config` | Talk summary | params `includeSecrets?`; result `config.talk.{provider,speechLocale,interruptOnSpeech,silenceTimeoutMs}` |
| `config.get` / `config.patch` | Talk write path | operator.admin |
| `voicewake.get` / `voicewake.set` | Trigger words | `get` is operator.read; `set` is used by `NativeTalkVoiceScreen`, params still to document |
| `system.info` / `health` | Gateway status | operator.read |

### Gateway scopes

- Talk write (`config.patch`): `operator.admin`. Without it `NativeTalkConfigError.missingAdminScope` is raised. A changed hash raises `.conflict`.
- `skills.update`: `operator.admin`.
- `channels.status`, `skills.status`: `operator.read`.

### Talk config write path

`NativeTalkConfigWriter` sends a merge patch after `config.get` (for the hash): `null` removes a key, objects merge recursively. Editable values: provider, voice (`talk.providers.<provider>.<voiceId|voice>`), `speechLocale` (BCP 47), `silenceTimeoutMs`, `interruptOnSpeech`. A confirm step precedes the write.

## Not reproduced from the web pages

Settings parity with the web Control UI is partial. An audit compared the web routes (`config-sections.ts`, `app-route-paths.ts`) with the native screens. It read only a few files in full; the rest comes from file names and a grep of gateway methods, so treat it as a map, not a guarantee.

Missing, by estimated value:

1. Model providers and auth (`models.authStatus`, `models.authSetApiKey`, `models.authLogout`, `models.probe`, `models.authRefresh`). Only the chat uses `models.authStatus`.
2. APNs test in Notifications (`push.test`).
3. Gateway logs (`logs.tail`).
4. Updates (`update.status`, `update.run`).
5. TTS provider selection and Talk catalog (`tts.*`, `talk.catalog`). The Talk provider is free text today.
6. Agents (`agents.update`; `agents.list` is only used by the chat).
7. Tools (`tools.catalog`, `tools.effective`).
8. Device management (approve / reject / remove / rename / token revoke; only `device.pair.list` is used).
9. Secrets store (`secrets.store.*`).
10. Exec approval policy (`exec.approvals.get/set`).

Also missing: skills upload, library and per-agent selection; per-channel config editing and wizard; hooks, bindings and `cron.status`; `usage.status`; plugins, MCP, memory, infrastructure, security. A generic "Advanced" config form (`config.schema` + `config.patch`) is deliberately not planned: large, with hash-conflict and restart risks.

Not applicable on iOS: Accessibility, Screen Recording and Event Posting permissions (macOS-only); Web Push (`push.web.*`).

The Settings hub still carries "Reset Onboarding" (`Design/SettingsProTabSections.swift`), a leftover of the upstream settings tab.

## Integration status

The original integration notes (route wiring in `NativeDestinations.swift`, `RootTabs.swift`, `DashboardPageScreen`) predate the native hub and are removed. `SettingsHubScreen` now pushes `NativeSettingsRouter` directly. Not re-verified: `.notifications`, `.talkVoice` and `.gatewayStatus` have no Dashboard route constant (`DashboardRouteMap`), so call the router with the destination directly.

`embedded: true` skips the screen's own `NavigationStack` (use inside an existing stack / `navigationDestination`). Environment required: `NodeAppModel` (all Gateway screens), `AppAppearanceModel` (Appearance).

## Design rules followed

`OpenClawType` only, `String(localized:)` for strings built in code, opaque `List` surfaces (glass only through shared components), 44pt rows, `accessibilityElement(children: .combine)` on rows, shared spring / Reduce Motion through existing components, annotated closures and typed `let`s to avoid type-checker blowups.
