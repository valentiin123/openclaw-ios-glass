# AgentsHub: écrans natifs agents et sous-agents

Dossier autonome `apps/ios/Sources/AgentsHub/`. Aucun fichier existant n'a été modifié, aucun commit ni push.
Rien n'a été compilé (Linux, SwiftUI indisponible) : voir « Non vérifié ».

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `AgentsHubModels.swift` | Types purs : `AgentsHubRunStatus`, `SubagentNode`, `FlatSubagentRow`, `SubagentTreeBuilder` (arbre, aplatissement, anti-cycle, profondeur 16). |
| `AgentsHubViewModel.swift` | `AgentsHubGateway` (accès injecté) et `AgentsHubViewModel` (`@MainActor @Observable`). |
| `AgentsHubSupport.swift` | Ressort unique (`AgentsHubMotion.spring`), modificateur Reduce Motion, teinte et badge de statut, formatage de durée. |
| `AgentsHubViews.swift` | Écrans SwiftUI : liste des agents, détail d'un agent, arbre des sous-agents, lancement, arrêt, résultat. |

## Méthodes Gateway utilisées (vérifiées dans `OpenClawChatGatewayRequests`)

| Usage | Méthode | Constructeur existant |
| --- | --- | --- |
| Liste des agents | `agents.list` | `agentsList()` via `OpenClawChatAgentsListResponse.load` |
| Identité (nom, emoji, avatar) | `agent.identity.get` | `agentIdentity(agentID:)` (appelé par `load`) |
| Sessions d'un agent | `sessions.list` | `sessionsList(limit:search:archived:agentID:includeGlobal:...)` |
| Enfants d'une session | `sessions.list` + `spawnedBy` | `sessionsList(..., spawnedBy:)` |
| Création d'un sous-agent | `sessions.create` (+ `parentSessionKey`) | `createSession(key:agentID:label:parentSessionKey:worktree:)` |
| Arrêt d'un run | `chat.abort` | `abortRun(sessionKey:agentID:runID:)` |
| Envoi de la tâche | `chat.send` | via `OpenClawChatTransport.sendMessage` (closure à câbler) |
| Résultat | `chat.history` | via `OpenClawChatTransport.requestHistory(sessionKey:)` (closure optionnelle) |

Aucune méthode `subagents.*` n'a été trouvée dans OpenClawKit : le lancement passe par `sessions.create` avec parent, l'arrêt par `chat.abort` sur chaque `activeRunIds`.

## Points d'intégration à brancher

1. **Gateway** : construire `AgentsHubGateway`.
   - `request` : exécute un `OpenClawChatGatewayRequest` sur la connexion courante (même mécanisme que `OpenClawChatAgentsListResponse.load`, `request: (OpenClawChatGatewayRequest) async throws -> Data`).
   - `sendMessage` : appeler `OpenClawChatTransport.sendMessage(sessionKey:agentID:expectedSessionRoutingContract:message:thinking:idempotencyKey:attachments:)` avec une clé d'idempotence générée.
   - `fetchResultText` (optionnel) : dernier texte assistant via `requestHistory(sessionKey:)`. Sans lui, on retombe sur `lastMessagePreview`.
2. **ViewModel** : créer un `AgentsHubViewModel(gateway:)` côté app (`@State` ou `@Environment`) à la racine de la destination.
3. **Navigation** : présenter la vue racine d'`AgentsHubViews.swift` dans un `NavigationStack` depuis une nouvelle destination (voir `RootSidebar.swift` / `RootTabsNavigation.swift`). Le fichier de navigation existant n'a pas été touché : l'ajout d'une entrée est à faire à l'intégration.
4. **Déclaration** : ajouter le dossier à `project.yml` / `SwiftSources.input.xcfilelist` si les sources ne sont pas globbées.
5. **Droits** : `chat.abort` et `sessions.create` peuvent exiger des scopes opérateur. Utiliser `connection.allows(...)` comme dans `ChatSessionSidebar+ContextMenu.swift` pour désactiver les boutons.
6. **Rafraîchissement live** : non branché. À faire via l'événement `sessions.changed` (cf. `ChatGatewayPayloadCodec`), en rappelant `loadTree`.

## Design

Glass limité aux contrôles, contenu sur surfaces opaques, un seul ressort désactivé sous Reduce Motion, couleurs sémantiques (rouge = échec, orange = attente, vert = terminé), statut toujours accompagné d'un glyphe et d'un texte, cibles de 44 pt, polices système pour Dynamic Type.

## Non vérifié

- Aucune compilation (SwiftUI/Observation indisponibles sous Linux) : erreurs de syntaxe, d'isolation d'acteur ou de visibilité (`internal` vs `public` des types OpenClawChatUI) possibles.
- Le décodage de `OpenClawChatSessionsListResponse` et `OpenClawChatCreateSessionResponse` depuis `Data` suppose le même format que le transport existant.
- Les champs `status` / `subagentRunState` sont des `String?` libres : le mapping de `AgentsHubRunStatus` repose sur les valeurs vues dans le code (`running`, `active`), pas sur une énumération du protocole.
- Le paramètre `spawnedBy` de `sessions.list` filtre bien les enfants directs : déduit de la signature, non testé contre un Gateway.
- Comportement de `chat.abort` sur un run de sous-agent, VoiceOver, Dynamic Type et Reduce Motion : à tester sur appareil.
