# LudoPoly — instructions projet

## Architecture du repo

Un **seul** repo Git contient deux projets indépendants :

| Dossier | Projet | Stack |
|---|---|---|
| racine (`lib/`, `pubspec.yaml`, ...) | App principale LudoPoly | Flutter / Dart |
| `Animations/` | Prototypes d'animations de pions | React + Vite + TypeScript |

Les deux évoluent en parallèle, partagent la même histoire Git mais sont fonctionnellement indépendants.

## Convention de commit — scopes obligatoires

Chaque commit DOIT être préfixé par son scope :

- `flutter: ...` — modif dans l'app Flutter (`lib/`, `pubspec.yaml`, `test/`, `assets/`, etc.)
- `anim: ...` — modif dans `Animations/`
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
