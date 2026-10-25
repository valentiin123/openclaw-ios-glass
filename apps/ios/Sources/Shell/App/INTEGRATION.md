# Shell racine natif (AppShell*) : intégration

Dossier : `apps/ios/Sources/Shell/App/`. Les types sont préfixés `AppShell*` pour ne pas entrer en collision
avec `Shell/ShellTab.swift` et `Shell/ShellTabBar.swift` (autre travail : barre d'onglets flottante
personnalisée). Les deux approches sont **alternatives** : n'en branchez qu'une.

Statut : syntaxe vérifiée (`swiftc -parse`) uniquement. Rien n'a été compilé ni exécuté.

## Structure

La barre contient exactement 3 onglets, de gauche à droite : Agents, Accueil, Activité.

| Onglet | Écran hébergé | Notes |
| --- | --- | --- |
| Agents | `AgentsBoardScreen` | Inchangé. |
| Accueil (`overview`, clé « Home ») | `CommandCenterTab` dans une `NavigationStack(path: homePath)` | Sélectionné au lancement (`AppShellTab.launchTab`). Uniquement la vue d'ensemble. Sessions poussées (swipe-back). Écrans « Plus » en feuille. |
| Activité (`activity`) | `OpenClawGlassSegmented` (Activité / Automatisations) au-dessus de `NativeDestinationRouter` | Sections : `activity` (`activityPagePath`) et `automations` (`cronJobsPagePath`). La dernière section est restaurée au retour sur l'onglet. |

Hors barre : le chat système (« Talk to OpenClaw » du menu Plus) et les Réglages s'ouvrent dans une
seule couverture plein écran (`coverKind` : `.chat` ou `.settings`). Les Réglages s'ouvrent depuis
l'engrenage de l'Accueil : `SettingsHubScreen` complet avec un bouton fermer (`AppShell.Settings.Close`).
Les anciens landings `settings` / `gateway` (et `desktop` / `terminal`) ouvrent ces Réglages depuis l'Accueil.
Un landing `gateway` affiche l'écran Gateway direct (`SettingsProTab(directRoute: .gateway)`), seul
consommateur d'une demande de configuration Gateway, avec un bouton retour vers le hub.

`TabView` + `Tab(value:)`, `.tabViewStyle(.sidebarAdaptable)`, `.tabBarMinimizeBehavior(.onScrollDown)`.
La barre Liquid Glass est dessinée par le système. Le glass n'est posé que sur les contrôles
(`OpenClawGlassSegmented`, bouton Done). Le contenu reste sur les surfaces opaques existantes.

## Fichiers

- `AppShellModel.swift` : `AppShellTab`, `AppShellAgentsSection`, `AppShellMoreItem`, `AppShellHomeRoute`,
  `AppShellLanding` (mapping depuis `RootTabs.SidebarDestination`), `AppShellNavigation` (`@Observable`).
- `AppShellSupport.swift` : `AppShellContext`, `AppShellSwipeBackEnabler`, `AppShellDoneButton`.
- `AppShellRootView.swift` : le `TabView`.
- `AppShellTabs.swift` : Chat, Agents, listes natives, Réglages.
- `AppShellOverviewView.swift` : Overview, liste « Plus », feuille d'un écran secondaire.

## Branchement dans `RootTabs.swift` (RootTabs reste l'hôte)

`RootTabs` conserve tout son cycle de vie : onboarding, feuilles (`presentedSheet`), toasts Gateway,
`handleOpenChatRequest`, deep links, `chatOwnerTaskIdentity`, tâches de rafraîchissement. Seul le rendu change.

1. **État.** Supprimer `selectedSidebarDestination`, `selectedSettingsRoute`, `activeSettingsRoute`,
   `sidebarNavigationPath`, `isSidebarVisible`, `isSidebarDrawerLayout`, `splitSidebarVisibility`,
   `isSidebarDetailRootVisible`, `selectedSettingsRouteRequestID`, `didResolveSidebarLayout`
   et `initialSidebarVisibilityOverride`. Ajouter :

   ```swift
   @State private var shell = AppShellNavigation(
       landing: AppShellLanding(legacy: RootTabs.initialDestination(
           arguments: ProcessInfo.processInfo.arguments)))
   ```

2. **Rendu.** Dans `body`, remplacer `self.sidebarSplitContent` par :

   ```swift
   AppShellRootView(navigation: self.shell, context: self.shellContext)
   ```

   avec

   ```swift
   private var shellContext: AppShellContext {
       AppShellContext(
           sidebarModel: self.sidebarModel,
           acceptsGatewaySetupRequests: !self.showOnboarding,
           gatewaySetupRequest: self.gatewaySetupRequest,
           onGatewaySetupRequestHandled: self.handleGatewaySetupRequest,
           onSettingsRouteChange: self.handleSettingsRouteChange,
           onApprovalNotificationsRoute: self.openNotificationSettings)
   }
   ```

   `RootSidebarShell`, `RootSidebar`, `RootSidebarGatewayControl`, `sidebarDetail*`, `sidebarHeaderAction`
   et `SidebarNavigationMarginAnchor` ne sont plus référencés.

3. **Tâches du sidebar à conserver** (à reporter sur le nouveau contenu) : les trois `.task(id:)` de
   `sidebarSplitContent` (`sidebarRefreshID`, `:events`, `sessionObserverTaskIdentity`). Les attacher à
   `AppShellRootView(...)`. Remplacer `isSidebarVisible` dans `SessionObserverTaskIdentity` par
   `self.shell.selection == .overview`.

4. **Appels existants.**

   | Avant | Après |
   | --- | --- |
   | `selectSidebarDestination(d)` | `self.shell.land(legacy: d)` |
   | `selectSidebarDestination(.chat)` | `self.shell.openChat()` |
   | `selectSettingsRoute(r)` | `self.shell.openSettings(route: r)` |
   | `selectSidebarSession(s)` (cas `.chat`) | `appModel.openChat(sessionKey:)` puis `self.shell.openChat()` |
   | `activeSettingsRoute` | `self.shell.activeSettingsRoute` |
   | `handleSettingsRouteChange` | inchangé (appelé via le contexte) |
   | `uiTestReadinessMarker` : `selectedSidebarDestination.rawValue` | `shell.selection.rawValue` (valeurs différentes) |
   | gateway setup deeplink : `selectSidebarDestination(.gateway)` | `self.shell.openSettings(route: .gateway)` |

   `handleSidebarSettingsNavigationPathChange` peut devenir un `onChange(of: shell.settingsPath)` qui appelle
   `handleSettingsRouteChange(shell.activeSettingsRoute)`.

5. **Point d'entrée.** `OpenClawApp.swift` reste inchangé (`RootTabs()`). Environnements requis : `NodeAppModel`,
   `AppAppearanceModel`, `GatewayConnectionController`, `VoiceWakeManager`, déjà injectés.

6. **Projet.** `SwiftSources.input.xcfilelist` doit être régénéré (`scripts/ios-write-swift-filelist.mts`)
   pour lister les 5 fichiers de `Sources/Shell/App/`. Je n'ai pas modifié ce fichier.

## Types injectés depuis NodeAppModel

Aucun nouveau type n'est requis côté modèle. Le shell lit uniquement via les écrans hébergés
(`@Environment(NodeAppModel.self)`). Le seul objet transmis par le hôte est `RootSidebarModel`
(`AppShellContext.sidebarModel`, utilisé par `CommandCenterTab`), plus l'état de demande de configuration Gateway.

## Pertes de fonctionnalités à valider

- La liste de sessions du tiroir, les groupes et le sélecteur de Gateway (`RootSidebarGatewayControl`)
  n'ont pas d'équivalent dans ce shell. Les sessions sont accessibles via Overview > Sessions,
  la Gateway via Réglages. À confirmer produit.
- `Desktop` et `Terminal` (WebView) ne sont pas dans le shell, par exigence « sans WebView ».
  Leurs anciennes destinations atterrissent sur Réglages.
- `SettingsHubScreen` peut afficher un tableau de bord embarqué (`EmbeddedDashboardContent`) quand
  l'opérateur est connecté en admin. C'est du code existant que je n'ai pas modifié.

## Gestes

- Swipe-back : `AppShellSwipeBackEnabler` réactive le geste pour les écrans qui masquent la barre de navigation.
- Pull-to-refresh : fourni par les écrans hébergés (`refreshable`).
- Re-sélection d'un onglet : retour à la racine (`userSelected`).
- Reduce Motion : `OpenClawMotion.perform(reduceMotion:)` et `openClawAnimation`.
