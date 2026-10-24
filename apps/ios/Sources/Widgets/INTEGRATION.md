# Widgets : points d'intégration

Module : `apps/ios/Sources/Widgets/` (cible app iOS, iOS 26.2). Rien n'a été compilé (Linux) ; voir « Limites ».

## API publique
- `WidgetCardView(payload:title:network:)` : point d'entrée (carte inline, menu Copier/Partager/Plein écran, états chargement/erreur).
- `WidgetPayload` : `.html(String, allowsScripts:)`, `.svg(String)`, `.chart(WidgetChartSpec)`.
- `WidgetChartSpec` (Codable) : `kind` bar|line|area|pie|sparkline (synonymes acceptés : column, donut, ...; `type` accepté à la place de `kind`), `title`, `xLabel`, `yLabel`, `series[{name, points[{x,y}]}]`; `decode(json:)`, `sanitized` (max 8 séries, 500 points). Décodage tolérant : `x` texte ou nombre, `y` nombre ou texte numérique, `series` ou `points`/`data` à plat, ou `labels` + `values`.
- `WidgetPayloadDetector.payload(language:body:allowsScripts:)` : fences ```chart / ```svg / ```html.
- `WidgetNetworkPolicy` : `.none` (défaut) ou `.allowedHosts([...])` (HTTPS uniquement, injecté dans la CSP).

## Pourquoi l'affichage actuel est probablement mauvais (lecture du code, non observé sur appareil)
1. `ChatInlineWidgetView` (OpenClawChatUI) ne gère que `kind=canvas, render=url` servi par le Gateway ; pas de HTML/SVG inline ni de données structurées -> pas de graphiques natifs.
2. Hauteur fixe = `preferredHeight` borné 160...1200, pas la hauteur réelle du contenu.
3. Erreur = simple texte « Widget unavailable », sans bouton Réessayer, ni plein écran, ni zoom.
4. `ChatProgressCardSurface` applique `.glassEffect` au contenu (contredit DESIGN.md : verre réservé aux contrôles) et `ChatProgressCardMenuAnchor` emballe la carte dans un ScrollView désactivé (contournement fragile).
5. Les barres ne sont reconnues que via des balises `<progress>` parsées par regex.

## Intégration (hors périmètre, à faire par le propriétaire du chat)
1. `OpenClawChatUI` est un package partagé : il ne peut pas importer `Widgets` (cible app). Ajouter dans `ChatMessageViews` un point d'injection, p.ex. une closure d'environnement `@Entry var openClawWidgetBuilder: ((WidgetPayload, String?) -> AnyView)?`, puis l'app fournit `WidgetCardView`. Alternative : déplacer ce module dans OpenClawChatUI (cible min iOS 18 : `.glass` et `glassEffect` demandent `#available(iOS 26)`).
2. Brancher `WidgetPayloadDetector` dans le rendu des blocs de code markdown (`ChatMarkdown*`, `ChatCodeHighlighter`) pour les fences chart/svg/html.
3. Conserver `ChatInlineWidgetView` pour les widgets canvas-URL du Gateway (TLS pin, CSP) : ce module ne les remplace pas.
4. `allowsScripts` ne doit être vrai que si l'utilisateur/le Gateway l'autorise explicitement (`sandbox == "scripts"`).
5. Retirer `glassEffect` de `ChatProgressCardSurface` au profit d'une surface opaque (`ProCard`).
6. `project.yml` inclut `Sources` entier : pas de changement ; régénérer le projet et mettre à jour `SwiftSources.input.xcfilelist`.
7. Ajouter les chaînes (`Widget`, `Copy image`, `Share`, `Full screen`, `Retry`, etc.) à `Resources/Localizable.xcstrings` (fr inclus).
8. Étendre `Tests/OpenClawTypographyTests.swift` (règle AGENTS.md) et ajouter un test du détecteur/décodeur chart.

## Limites non vérifiées
- Aucune compilation ni exécution : erreurs de syntaxe/concurrence Swift 6 possibles (Bindings mutés depuis le Coordinator, `@Entry`, etc.).
- `ForEach(id: \.x)` plante/duplique si deux points d'une série ont le même libellé ; à remplacer par des identifiants uniques.
- La logique `decidePolicyFor` de la WebView (autoriser `about:blank`, annuler le reste) doit être testée sur appareil ; l'export snapshot et la hauteur auto aussi.
- CSP via balise meta : n'applique pas `sandbox` ; l'isolation repose sur origine opaque + JS désactivé par défaut.
- Zoom du plein écran, VoiceOver, Dynamic Type, Reduce Motion : implémentés mais non testés.
