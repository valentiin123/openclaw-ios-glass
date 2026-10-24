# Écrans natifs Workboard et Instances

Nouveaux fichiers uniquement (aucun fichier existant modifié) :

- `Native/Instances/InstancesModels.swift`: décodage tolérant de `device.pair.list` et `presence.query`, enum `InstanceAction`.
- `Native/Instances/InstancesViewModel.swift`: chargement, actions, confirmations, renommage.
- `Native/Instances/NativeInstancesScreen.swift`: écran `NativeInstancesScreen`.
- `Native/Instances/NativeOperatorAccess.swift`: scopes opérateur annoncés + méthodes annoncées (même principe que `AgentsHubScreen.refreshCapabilities`), et `NativeJSON`.
- `Native/Instances/NativeControls.swift`: `nativeGlassButtonStyle`, `nativeMinimumTapTarget`, `NativeInlineNotice` (partagés par Workboard).
- `Native/Workboard/WorkboardModels.swift`, `WorkboardViewModel.swift`, `NativeWorkboardScreen.swift`.

## Point d'intégration (à faire par l'agent principal)

Dans `NativeDestinations.swift`, `NativeDestinationRouter.body` :

```swift
case DashboardRouteMap.devicesSettingsPath:
    NativeInstancesScreen(title: self.title, headerSidebarAction: self.headerSidebarAction)

case DashboardRouteMap.workboardPagePath:
    NativeWorkboardScreen(title: self.title, headerSidebarAction: self.headerSidebarAction)
```

Ils remplacent respectivement le `NativeListScreen` + `NativeLoaders.presence` et le `NativeUnavailableScreen` actuels.
`hasNativeScreen(for:)` contient déjà les deux chemins. `NativeLoaders.presence` devient inutilisé (peut rester).

Les deux écrans embarquent leur propre `NavigationStack` et lisent `NodeAppModel` via `@Environment`, comme `NativeListScreen`.

## Méthodes Gateway

Vérifiées (schémas + `core-descriptors.ts`) :

| Méthode | Scope | Params |
|---|---|---|
| `device.pair.list` | `operator.pairing` | `{}` |
| `device.pair.approve` | `operator.pairing` | `{requestId}` |
| `device.pair.reject` | `operator.pairing` | `{requestId}` |
| `device.pair.remove` | `operator.pairing` | `{deviceId}` |
| `device.pair.rename` | `operator.pairing` (2026.7) | `{deviceId, label}` (1-64 car.) |
| `presence.query` | `operator.read` (2026.9, profile-dependent) | `{action:"list", include:["devices"]}` |

Réponse de `device.pair.list` : `{pending: [...], paired: [...]}` (`src/gateway/device-pairing-list.types.ts`).

Workboard, **partiellement vérifié** : les handlers `workboard.*` sont fournis par un plugin absent de l'arbre source.
Seuls les appels suivants apparaissent dans `scripts/perf/workboard-read-measure.ts` :

- `workboard.boards.list {}` → `{boards:[{id,total,byStatus,...}]}`
- `workboard.cards.list {boardId}` → `{cards:[{id,status,...}]}`
- `workboard.cards.update {id, patch:{status}}`

Le scope requis par ces méthodes n'est déclaré nulle part. `operator.write` est **supposé** pour `cards.update`.
L'action de déplacement est désactivée tant que la Gateway ne l'annonce pas ET que le scope n'est pas présent.
Les champs des cartes suivent le type `WorkboardCard` du contrat (`packages/workboard-contract`), lus de façon tolérante.
