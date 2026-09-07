# Fonds d'écran

| Fichier | Où il s'affiche |
|---|---|
| `Background.png` | derrière le tableau de bord ET derrière le plateau |

Une seule image sert les deux écrans. Pour les séparer un jour, ajouter un
second fichier et pointer `AppBackground.board` dessus dans
`lib/game/app_background.dart`.

L'image est le décor, pas un filigrane : le dégradé saphir qui la précède
ne sert qu'à combler ce qu'elle ne couvre pas, et à tenir debout si elle
disparaît. Un vignettage léger passe par-dessus pour que le plateau
ressorte.

**Remplacer ou renommer une image ici impose de relancer `flutter run`** —
le bundle d'assets est figé au démarrage.
