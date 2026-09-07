# Fonds d'écran

| Fichier | Où il s'affiche |
|---|---|
| `Background.jpg` | derrière le tableau de bord ET derrière le plateau |

Une seule image sert les deux écrans. Pour les séparer un jour, ajouter un
second fichier et pointer `AppBackground.board` dessus dans
`lib/game/app_background.dart`.

Tant qu'un fichier est absent, l'écran retombe sur son dégradé : rien ne
casse, le fond est simplement uni.

**Ajouter ou renommer une image ici impose de relancer `flutter run`** — le
bundle d'assets est figé au démarrage.
