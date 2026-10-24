# Refonte Chat Liquid Glass : état (2026-10-24)

Rien n'a été compilé (Linux). Tout est relu à la main, non exécuté.

## Fait

- `OpenClawChatUI/ChatMotion.swift` (nouveau) : `OpenClawChatMotion` (même spring que `OpenClawMotion`: response 0,32 / damping 0,86; fondu 0,12 s sous Reduce Motion), `openClawChatAnimation(value:)`, `openClawChatGlass(cornerRadius:interactive:)` (glass iOS 26, `.regularMaterial` avant et sur macOS). Le package ne peut pas importer `OpenClawMotion` (cible app), d'où le miroir.
- Animations locales remplacées par le spring partagé : toggle carte de progression, activité des outils, bandeau Talk, « Show more » de la bulle utilisateur, panneau slash du composer, jauge d'effort, en-tête `ChatProTab` (`.snappy` supprimés).
- Surface du composer : glass via `openClawChatGlass` (iOS), ombre décorative retirée.
- `ChatProgressCardSurface` : surface opaque (`subtleCard` + bordure), plus de `glassEffect`.
- Point d'injection `OpenClawChatRichBlockRenderer` (`ChatRichBlockRenderer.swift`, `@Entry openClawChatRichBlockRenderer`) branché dans `ChatCodeBlockView` pour les fences complètes chart/svg/html; `nil` = bloc de code d'origine. `ChatProTab` fournit `WidgetCardView` (scripts désactivés). `ChatInlineWidgetView` est conservé pour les widgets canvas-URL.

## Ajouté le 2026-10-25 (non compilé, `swiftc -parse` OK)

- `OpenClawChatUI/ChatMessageSwipeActions.swift` (nouveau, **à ajouter à `apps/ios/SwiftSources.input.xcfilelist`**) : `chatMessageSwipeActions(onReply:onCopy:)`. Glisser vers la droite = répondre, vers la gauche = copier. Geste horizontal dominant uniquement (le scroll vertical n'est pas touché), un seul spring partagé, pas de déplacement sous Reduce Motion, inactif sur macOS.
- `ChatView.messageRow` : branche le swipe avec la même éligibilité que les boutons Répondre/Copier ; l'appui long reste le menu contextuel existant.
- Fondu mot par mot : déjà en place (`ChatStreamingReveal`, `ChatStreamingAssistantTextBody`), désactivé sous Reduce Motion. Aucun changement.

## Non fait / à traiter

- Boutons du composer (pièce jointe, envoi, dictée, Talk) non restylés individuellement : seule la surface du composer est en glass.
- En-tête : toujours la toolbar système (`sharedBackgroundVisibility(.hidden)`), inchangée.
- Panneau slash : passé sur `openClawChatGlass(cornerRadius: 16)` (ombre et bordure décoratives retirées). Fait le 2026-10-25.
- `TalkWaveformView` : `.easeOut`/`.linear` conservés (animation de signal, pas de transition d'UI).
- Les `.font(.system…)` existants sont inchangés (le test ne scanne que `ChatFileAttachment` et `ChatMessageReactions`).
- Ajouter un test du renderer et vérifier sur appareil.
