# Refonte Chat Liquid Glass : notes et blocage de périmètre

## Constat (vérifié par lecture/grep le 2026-10-24)

`apps/ios/Sources/Chat/**` ne contient AUCUNE vue de l'écran Chat. Contenu :

- Transports et chargeurs : `IOSGatewayChatTransport*.swift`, `AppleReviewDemoChatTransport.swift`,
  `IOSSourceResourceLoader.swift`, `IOSMediaArtifactLoader.swift`
- Possesseur du view model : `IOSChatViewModelOwner.swift`
- Client TTS : `ChatMessageSpeechClient.swift`
- Seule vue SwiftUI : `SessionDashboardScreen.swift` (WebView du dashboard, pas le Chat)

L'UI Chat réelle est ailleurs, hors périmètre d'écriture :

- `apps/ios/Sources/Design/ChatProTab.swift` : hôte iOS (instancie `OpenClawChatView`, prompts de démarrage)
- `apps/ios/Sources/Design/ChatModelControlsMenu.swift` : menu modèle/réflexion
- `apps/shared/OpenClawKit/Sources/OpenClawChatUI/` : `ChatView.swift`, `ChatComposer*.swift`,
  `CleanChatComposerControls.swift`, `ChatMessageViews.swift`, `ChatToolActivityViews.swift`,
  `ChatMermaidBlockView.swift`, `ChatMessageReactions.swift`, `ChatCompletedWorkDisclosure.swift`,
  `VoiceNoteComposerViews.swift`, `ChatTalkActivityViews.swift`, `ChatTheme.swift`, etc.
  (cible partagée avec d'autres plateformes ; la Watch y est aussi référencée)

Déjà présent : `glassEffect` dans `CleanChatComposerControls.swift:35` et `ChatProgressCard.swift:21` ;
`.glass`/`.glassProminent`/`GlassEffectContainer` dans `Design/OpenClawProComponents.swift`.

## Décision

Aucun fichier Swift modifié : toute refonte réelle exige d'écrire hors de `apps/ios/Sources/Chat/**`,
ce qui est interdit par la consigne. Changer l'écran Chat en y touchant partiellement, ou en dupliquant
l'UI dans ce dossier sans la brancher, ne ferait que créer du code mort ou un risque de régression.

## Pour débloquer (à décider par le demandeur)

1. Élargir le périmètre d'écriture à `apps/ios/Sources/Design/ChatProTab.swift` et
   `apps/shared/OpenClawKit/Sources/OpenClawChatUI/**` (composer, messages, tool views, theme), ou
2. Accepter une surcouche iOS-only dans `Chat/` qui enveloppe `OpenClawChatView` (limitée : on ne
   peut pas restyler les bulles, le composer ni les cartes sans modifier OpenClawChatUI).

## Besoins de tokens de design anticipés (à valider côté Design/)

- Un spring unique partagé (ex. `OpenClawProMotion.spring`) avec repli sans animation si Reduce Motion
- Rayon/espacement du composer et des surfaces de contenu opaques (utiliser `OpenClawProMetric` si présent)
- Matériau « surface de contenu discrète » (opaque) distinct du verre de navigation

## Plan d'exécution proposé une fois le périmètre élargi

Verre réservé à : en-tête, composer, boutons (GlassEffectContainer + `.buttonStyle(.glass)`).
Contenu sur surfaces opaques. Un seul spring, `accessibilityReduceMotion` respecté. Revue fonction par
fonction : dictée, notes vocales, Talk, pièces jointes, Mermaid, sélection de texte, Listen/TTS,
réactions, « Worked for… », outils/raisonnement, outbox, couleurs de session, Dynamic Type, VoiceOver, 44 pt.
