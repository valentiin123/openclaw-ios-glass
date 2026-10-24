# Refonte Chat Liquid Glass : état (2026-10-24)

Rien n'a été compilé (Linux). Tout est relu à la main, non exécuté.

## Fait

- `OpenClawChatUI/ChatMotion.swift` (nouveau) : `OpenClawChatMotion` (même spring que `OpenClawMotion`: response 0,32 / damping 0,86; fondu 0,12 s sous Reduce Motion), `openClawChatAnimation(value:)`, `openClawChatGlass(cornerRadius:interactive:)` (glass iOS 26, `.regularMaterial` avant et sur macOS). Le package ne peut pas importer `OpenClawMotion` (cible app), d'où le miroir.
- Animations locales remplacées par le spring partagé : toggle carte de progression, activité des outils, bandeau Talk, « Show more » de la bulle utilisateur, panneau slash du composer, jauge d'effort, en-tête `ChatProTab` (`.snappy` supprimés).
- Surface du composer : glass via `openClawChatGlass` (iOS), ombre décorative retirée.
- `ChatProgressCardSurface` : surface opaque (`subtleCard` + bordure), plus de `glassEffect`.
- Point d'injection `OpenClawChatRichBlockRenderer` (`ChatRichBlockRenderer.swift`, `@Entry openClawChatRichBlockRenderer`) branché dans `ChatCodeBlockView` pour les fences complètes chart/svg/html; `nil` = bloc de code d'origine. `ChatProTab` fournit `WidgetCardView` (scripts désactivés). `ChatInlineWidgetView` est conservé pour les widgets canvas-URL.

## Non fait / à traiter

- Boutons du composer (pièce jointe, envoi, dictée, Talk) non restylés individuellement : seule la surface du composer est en glass.
- En-tête : toujours la toolbar système (`sharedBackgroundVisibility(.hidden)`), inchangée.
- Panneau slash : encore `.regularMaterial` + ombre.
- `TalkWaveformView` : `.easeOut`/`.linear` conservés (animation de signal, pas de transition d'UI).
- Les `.font(.system…)` existants sont inchangés (le test ne scanne que `ChatFileAttachment` et `ChatMessageReactions`).
- Ajouter un test du renderer et vérifier sur appareil.
