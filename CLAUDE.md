# LudoPoly — instructions projet

## Architecture

**Deux** repos Git distincts, en relation **producer/consumer** :

| Repo | Emplacement local | Stack | Rôle |
|---|---|---|---|
| `LudoPoly` | `~/Desktop/LudoPoly` | Flutter / Dart | **Consomme** les anims |
| `LudoPolyAnimations` | `~/Desktop/LudoPolyAnimation` | React + Vite + TS | **Produit** les anims |

- Le **Studio Animations** conçoit/exporte toutes les anims (dés qui roulent, pions qui sautent, etc.) et dépose les sorties (PNG, GIF, WebP) dans son propre `AnimStock/`.
- Le **Flutter** ne fait que `Image.asset(...)` sur ces fichiers. **Aucune animation custom côté Flutter** (pas de CustomPaint animé, pas de particles) — toute anim manquante est une demande à passer au Studio.

### Le lien `AnimStock/`

À la racine du repo Flutter, `AnimStock/` est un **lien symbolique** (gitignoré) vers l'`AnimStock/` du repo Animations :

```bash
cd ~/Desktop/LudoPoly && ln -sfn ~/Desktop/LudoPolyAnimation/AnimStock AnimStock
```

C'était une *junction* sous Windows. **Sans ce lien, tous les assets du `pubspec.yaml` manquent** et le build échoue — c'est la première chose à vérifier sur une nouvelle machine.

### Convention des assets d'animation

- Path : `AnimStock/<Categorie>/<FORMAT>/<nom_en_snake_case>.{png,gif,webp}`
  (ex : `AnimStock/Dices/PNG/Dice_White_3D.png`, `AnimStock/Tokens/WEBP/Token_standard_yellow_impatient_#5.webp`).
- Catégories : `Tokens/`, `Dices/`, `Selectors/`, `Twemoji/`. Sous-dossiers de format : `PNG/`, `WEBP/`, `GIF/`.
- **Pas d'espaces** dans les noms (bug Flutter web : double URL-encoding).
- Déclaration : ajouter le dossier dans `pubspec.yaml` → `assets: - AnimStock/<Categorie>/<FORMAT>/`.
- **Ajout/renommage d'un asset → relancer `flutter run`** (le bundle est figé au démarrage). Modifier un asset existant → hot restart suffit.

## Convention de commit — scopes obligatoires

Chaque commit DOIT être préfixé par son scope :

- `flutter: ...` — modif dans l'app Flutter (`lib/`, `pubspec.yaml`, `test/`, `assets/`, etc.)
- `docs: ...` — modif dans `Documentation/`
- `repo: ...` — modif transverse (`.gitignore`, `README.md`, `CLAUDE.md`, config repo)

Le scope `anim: ...` appartient au repo `LudoPolyAnimations` et ne s'utilise **que là-bas**.

### Règle absolue : pas de mélange de scopes

Un commit = un seul scope. Si une session touche par accident un fichier d'un autre scope, **ne pas le stager**. Toujours `git add <fichier précis>`, **jamais** `git add -A` ou `git add .`.

### Sessions et scopes

- Une session "Flutter" ne touche **jamais** au repo Animations.
- Une session "Animations" ne touche **jamais** aux fichiers Flutter.
- Si un fichier hors scope apparaît modifié dans `git status`, le signaler à l'utilisateur sans le toucher.

## Build & Run (macOS)

### Flutter (LudoPoly)

Le repo n'a **pas** de dossier `macos/` : la seule cible locale est le web.

```bash
cd ~/Desktop/LudoPoly
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

- Le premier build prend ~30 s avant que la page ne soit servie : recharger si l'écran est noir.
- Hot reload : `r` dans le terminal `flutter run` — Hot restart : `R`
- `-d chrome` n'est pas détecté tant que Chrome n'est pas dans `/Applications` (sinon exporter `CHROME_EXECUTABLE`).

### Studio Animations

```bash
cd ~/Desktop/LudoPolyAnimation
npm install
npm run dev          # http://localhost:3000
```

- Vite est en `port: 3000, strictPort: true` : **pas de repli** sur un autre port. S'il est occupé, le `predev` (`scripts/kill-port-3000.cjs`) tue le process qui l'écoute.
- Ne pas viser le port 5000 sur macOS : il est pris par le récepteur AirPlay de Control Center.
- Si Vite crashe sur `Cannot find module @rollup/rollup-darwin-x64` (binaire natif tronqué) :
  `rm -rf node_modules/@rollup/rollup-darwin-x64 && npm install`.

### Sur cette machine

Les deux serveurs sont déclarés dans `~/Desktop/.claude/launch.json` (noms `ludopoly-web` et `studio`) — `launch.json` est lu **au répertoire de travail racine**, pas dans les sous-projets.

## Specs et docs

- Règles du jeu : `Documentation/LudoKing_Rules.md`
- Specs LudoPoly : `Documentation/LudoPoly specs.pdf`
- Images de plateau de référence : `Documentation/Ludo King Board *.png/jpg`
