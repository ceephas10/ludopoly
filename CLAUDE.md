# LudoPoly — instructions projet

## Architecture du repo

Un **seul** repo Git, deux projets en relation **producer/consumer** :

| Dossier | Projet | Stack | Rôle |
|---|---|---|---|
| racine (`lib/`, `pubspec.yaml`, ...) | App LudoPoly | Flutter / Dart | **Consomme** les anims |
| `Animations/` | Atelier d'animations | React + Vite + TS | **Produit** les anims |

- Le **projet Animations** conçoit/exporte toutes les anims (dés qui roulent, pions qui sautent, etc.) et dépose les sorties (PNG, GIF, WebM) dans `Animations/AnimStock/<categorie>/`.
- Le **Flutter** ne fait que `Image.asset(...)` sur ces fichiers. **Aucune animation custom côté Flutter** (pas de CustomPaint animé, pas de particles) — toute anim manquante est une demande à passer au projet Animations.

### Convention des assets d'animation

- Path : `Animations/AnimStock/<categorie>/<nom_en_snake_case>.{png,gif,webm}` (ex : `Animations/AnimStock/Dices/Dice_White_3D.png`).
- **Pas d'espaces** dans les noms (bug Flutter web : double URL-encoding).
- Déclaration : ajouter le dossier dans `pubspec.yaml` → `assets: - Animations/AnimStock/<categorie>/`.
- **Ajout/renommage d'un asset → relancer `flutter run`** (le bundle est figé au démarrage). Modifier un asset existant → hot restart suffit.

## Convention de commit — scopes obligatoires

Chaque commit DOIT être préfixé par son scope :

- `flutter: ...` — modif dans l'app Flutter (`lib/`, `pubspec.yaml`, `test/`, `assets/`, etc.)
- `anim: ...` — modif dans `Animations/` (atelier d'anims + dépôt dans `AnimStock/`)
- `docs: ...` — modif dans `Documentation/`
- `repo: ...` — modif transverse (`.gitignore`, `README.md`, `CLAUDE.md`, config repo)

### Règle absolue : pas de mélange de scopes

Un commit = un seul scope. Si une session touche par accident un fichier d'un autre scope, **ne pas le stager**. Toujours `git add <fichier précis>`, **jamais** `git add -A` ou `git add .`.

### Sessions et scopes

- Une session "Flutter" ne touche **jamais** à `Animations/`.
- Une session "Animations" ne touche **jamais** aux fichiers Flutter à la racine.
- Si un fichier hors scope apparaît modifié dans `git status`, le signaler à l'utilisateur sans le toucher.

## Build & Run

### Flutter (racine)
```powershell
cd C:\Users\jmpir\Dev\LudoPoly
flutter run -d windows    # ou -d chrome
```
- Hot reload : `r` dans le terminal `flutter run`
- Hot restart : `R`

### Animations (React/Vite)
```powershell
cd C:\Users\jmpir\Dev\LudoPoly\Animations
npm run dev
```

## Specs et docs

- Règles du jeu : `Documentation/LudoKing_Rules.md`
- Specs LudoPoly : `Documentation/LudoPoly specs.pdf`
- Images de plateau de référence : `Documentation/Ludo King Board *.png/jpg`
