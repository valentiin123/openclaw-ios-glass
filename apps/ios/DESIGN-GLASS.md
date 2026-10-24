# Liquid Glass: design system addendum

Complète `DESIGN.md`. Source du code : `Sources/Design/OpenClawGlassSystem.swift`.

## Principes

- Glass uniquement pour la navigation et les contrôles (barres, boutons, segmented, pills flottantes).
- Le contenu (cartes, lignes, formulaires, métriques) reste opaque et sobre : `ProCard` / `OpenClawGlassCard`.
- Une seule animation : `OpenClawMotion.spring`. Sous Reduce Motion, tout passe par `OpenClawMotion.reducedFade` (fondu de 0,12 s), sans échelle ni déplacement.
- Pas d'ombre ni de halo décoratif.

## Mouvement

| Token | Rôle |
| --- | --- |
| `OpenClawMotion.spring` | Spring partagé (response 0,32 / damping 0,86) |
| `OpenClawMotion.reducedFade` | Remplacement sous Reduce Motion |
| `OpenClawMotion.animation(reduceMotion:)` | Choisit l'un ou l'autre |
| `OpenClawMotion.appear(reduceMotion:)` | Transition d'insertion (opacité + échelle) |
| `OpenClawMotion.edge(_:reduceMotion:)` | Transition depuis un bord (bannières, toasts) |
| `OpenClawMotion.perform(reduceMotion:_:)` | `withAnimation` avec le spring partagé |

Modificateurs :

- `.openClawAnimation(value:)` : remplace `.animation(_, value:)`.
- `.openClawEntrance(index:enabled:)` : entrée courte (fondu + 8 pt), décalage de 40 ms par index.

## Glass

- `.openClawGlass(in:tint:interactive:)` et `.openClawGlassCapsule(tint:interactive:)` : `glassEffect` sur iOS 26, matériau fin en repli.
- `openClawGlassButton(prominent:tint:)`, `OpenClawGlassControlGroup` : inchangés.
- `OpenClawGlassSegmented` : contrôle segmenté, sélection en capsule glass qui se déplace via `glassEffectID`.

## Composants

- `OpenClawGlassCard` : carte sobre, entrée animée optionnelle (`entranceIndex`).
- `OpenClawEmptyState` : état vide animé (icône, titre, message, actions).
- `OpenClawStatusPill` : indicateur de statut sans halo ni glass.
- `OpenClawPressButtonStyle` / `.openClawPress` : retour de pression pour contenu tappable non glass.

## Règles

1. Ne jamais mettre de glass derrière du texte à lire.
2. Entourer les contrôles glass voisins d'un `OpenClawGlassControlGroup`.
3. Toute animation nouvelle passe par `OpenClawMotion`; pas de `.easeInOut` ou spring ad hoc.
4. Les polices restent `OpenClawType.*` (garde-fous de typographie en test).
