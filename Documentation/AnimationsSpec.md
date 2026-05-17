# LudoPoly — Spec d'animations Studio ↔ Jeu

Convention de production des assets animés (GIF) que Studio (`LudoPolyAnimations`) livre au jeu (`LudoPoly`). Cette spec est **contractuelle** entre Studio (artiste / générateurs) et Flutter (runtime).

---

## 1. Unités et anchor

- **Unité** : 1 cell = **100 px** design (= 1 case du plateau côté Flutter).
- **Anchor logique** = **les pieds du pion au repos** (point de contact avec la case). C'est ce point qui sera aligné sur le centre de la case côté Flutter.
- **Position de l'anchor dans le canvas** :
  - En X : centré, `canvas_width / 2`.
  - En Y : Studio libre selon les besoins de l'anim (saut, danse, fly-out…), mais doit **transmettre la position** via sidecar JSON.

---

## 2. Format de sortie

- **GIF** pour toutes les anims (loop ou one-shot).
- **PNG** pour les states statiques (rare).
- **Pas de WebM** (mauvais support transparence Flutter web).
- **Fond transparent obligatoire** — palette binaire (sentinel index transparent), pas de semi-alpha sur les bords.
- **Pas d'espaces** dans les noms de fichiers (bug Flutter web `%2520`).
- **Marge minimum** : 5 px de transparence sur tous les bords (sécurité anti-rounding).
- **Loop** :
  - Anim cyclique → GIF `loop=0` (infinie).
  - Anim one-shot → GIF `loop=1`, **la dernière frame est l'état post-anim définitif** (pas un état intermédiaire de boucle).
- **FPS** : cible **20 fps** (50 ms/frame). Durée max indicative : 2 s (loop), 1.5 s (one-shot).

---

## 3. Canvas par émotion

Dimensions **en multiples de 50 px** (= 0.5 cell). Studio choisit le **plus petit canvas** qui contient toute l'anim sans cropper (marge 5 px incluse). Si une émotion fait varier la taille selon la variante (#1..#5), prendre la **plus grande** et l'appliquer aux 5 (canvas homogène par émotion).

| Émotion | Cible | Comment penser le canvas |
|---|---|---|
| `idle` | ~150×200 px (1.5×2 cells) | Tight, pion + respiration. Anchor ~80 % du bas. |
| `scared` | 150×200 px | Comme idle, micro-tremblement. |
| `selected` | 150×200 px | Idle + halo léger. |
| `jump` | 150×300 px (1.5×3 cells) | Saut vertical, apogée ~1.5 cell au-dessus des pieds. Anchor ~90 % du bas. |
| `surprise` | 150×250 px | Sursaut vertical court. |
| `win` | 300×300 px (3×3 cells) | Danse / lévitation / particules. Anchor au centre vertical. |
| `captured` | 300×300 px | Explosion / fade / fly-out. Anchor au centre vertical. |

Valeurs **indicatives ±20 %**. La taille exacte est fixée par Studio au plus juste de l'anim.

### Anim `jump` spécifique
- Pion au repos centré horizontalement, pieds à l'anchor.
- Trajectoire : parabole vers le haut puis redescente, **réatterrit à la même position** (anchor inchangé).
- Flutter anime la position case→case ; le GIF anime seulement le saut vertical local.

### Combo "stack" (cas combo 1)
- Studio fournit `Stack_badge_<color>.png` (4 fichiers, un par couleur) — canvas 200×200, transparent, contenant la zone où Flutter écrira `×N`.
- Flutter overlay le nombre via texte stylé centré.

### Combo "fan radial" (cas combo 2)
- **Aucun asset spécifique**. Flutter réutilise les `idle` standards avec offsets de position.
- Studio doit s'assurer que les `idle` de toutes les couleurs sont **calibrés sur la même hauteur visible** (anchor cohérent inter-couleurs).

---

## 4. Naming

```
Token_standard_<color>_<emotion>_<variant>.gif
Token_standard_<color>_<emotion>_<variant>.json   (sidecar anchor — optionnel)
```

- `<color>` : `red | green | blue | yellow`
- `<emotion>` : `idle | scared | selected | jump | surprise | win | captured` (extensible)
- `<variant>` : `1..5` (5 variantes par émotion par couleur)
- `standard` : type de pion (anticipe d'autres types : boss, mini…).

**Selectors** (assets non typés par couleur, un seul fichier partagé) :
```
Selector_<letter>_<style>.gif
```

**Badges stack** :
```
Stack_badge_<color>.png
```

---

## 5. Sidecar JSON (anchor + métadonnées)

À côté du GIF, fichier JSON optionnel portant les métadonnées que le GIF ne peut pas embarquer.

**Forme complète** :
```json
{
  "anchor_px": [200, 480],
  "loop": true,
  "fps_override": null
}
```

- `anchor_px` : `[X, Y]` en pixels dans le canvas natif (origine `(0,0)` = coin haut-gauche du fichier). Si absent, Flutter assume `[canvas_w/2, canvas_h * 0.6]`.
- `loop`, `fps_override` : optionnels, Flutter ignore si absents.

**Résolution Flutter** :
- Si `Token_standard_blue_jump_1.json` existe → utilisé pour cette variante.
- Sinon, fallback sur `Token_standard_blue_jump.json` (couvre les 5 variantes de l'émotion).
- Sinon, fallback sur les valeurs par défaut.

Cela évite de dupliquer 5 fichiers JSON identiques quand l'anchor est partagé entre variantes.

---

## 6. Render Flutter ↔ Studio

Au render, Flutter :
1. Charge le GIF, lit ses dimensions natives `(W_native, H_native)`.
2. Lit `anchor_px = [Ax, Ay]` du sidecar JSON (ou applique le fallback).
3. Calcule `scale = cell_runtime_px / 100` (100 = 1 cell design).
4. Positionne le coin haut-gauche du canvas à :
   ```
   (case_center_x − Ax * scale,
    case_center_y − Ay * scale)
   ```

**Hit zone** = rectangle séparé et fixe, `1.0 × 1.0` cell autour du centre de la case (indépendant de la taille du GIF).

---

## 7. Livrable — arborescence

Studio livre dans le repo `LudoPolyAnimations` :

```
AnimStock/
  Tokens/
    GIF/
      Token_standard_<color>_<emotion>_<variant>.gif
      Token_standard_<color>_<emotion>_<variant>.json   (si nécessaire)
  Selectors/
    GIF/
      Selector_<letter>_<style>.gif
  Badges/
    PNG/
      Stack_badge_<color>.png
```

---

## 8. Preview Studio (debug viewport)

Le viewport Studio affiche, sur toggle, un **grid de preview** pour aider l'artiste à valider l'anchor et le canvas :

- Lignes solides tous les **100 px** (= 1 cell).
- Lignes pointillées tous les **25 px** (= 1/4 cell) pour les détails.
- **Origine de la grid** : sur l'anchor (= pieds du sprite au repos pour Studio ; côté Flutter, sur le centre de la case).
- **Coords** affichées en cells (`-1, 0, +1, +2…`), pas en px.
- **Marqueur d'anchor** : croix 1 px rouge à `(0, 0)`.
- **Case d'arrivée** : carré gris semi-transparent (~20 % alpha) entre `(-0.5, -0.5)` et `(+0.5, +0.5)` cells.

---

## 9. Points NON couverts (à trancher au cas par cas)

- **Soft-alpha / glows** : GIF impossible. Si besoin → APNG ou WebP animé (pas WebM). À discuter avant production.
- **Types de pion non-`standard`** : à définir au moment de leur introduction.
- **Liste fermée des émotions** : la liste section 3 est ouverte ; toute nouvelle émotion doit être ajoutée ici et validée par Flutter.
