# LudoPoly — Cahier des charges des règles

> Sections 1 à 16 : la spec d'origine, **inchangée**.
> Sections 17 à 30 : les règles et fonctionnalités **qui n'étaient pas encore
> établies**, ajoutées ici dans la même notation.
>
> Statut d'implémentation de chaque section : `lib/game/game_controller.dart`
> pour le moteur, `test/rules_test.dart` pour le cahier de tests.

---

## 1. Structure fondamentale du jeu

* 2 à 4 joueurs dans le mode classique.
* Chaque joueur possède 4 pions.
* Chaque joueur possède une couleur.
* Les 4 pions commencent dans leur base.
* Le déplacement se fait sur le parcours du plateau.
* Le but est de faire parvenir les 4 pions au centre / à la maison.
* Le premier joueur qui y arrive avec ses 4 pions gagne.

CE JEUX propose notamment le jeu contre ordinateur, le mode local/pass-and-play,
le multijoueur en ligne et le multijoueur privé.

## 2. Le dé

Le dé possède six valeurs :

    1 – 2 – 3 – 4 – 5 – 6

À chaque tour :

1. le joueur lance le dé ;
2. le résultat détermine les mouvements possibles ;
3. le joueur choisit un pion pouvant effectuer ce déplacement ;
4. le déplacement est effectué ;
5. le jeu détermine éventuellement une capture ;
6. le jeu détermine si le joueur bénéficie d'un tour supplémentaire.

**Si le joueur fait 1 à 5** — normalement, il effectue son déplacement puis le
tour passe au joueur suivant.

**Si le joueur fait 6** — le 6 permet notamment de sortir un pion de la base et
donne un tour supplémentaire.

## 3. Sortir un pion de la base

Un pion placé dans la base ne peut normalement pas commencer son parcours avec
un 1, 2, 3, 4 ou 5. Il faut obtenir 6.

    BASE
    🔴 🔴 🔴 🔴

    Dé = 6

    ↓

    Un 🔴 sort de la base
    et arrive sur sa case de départ.

Le moteur du jeu doit donc vérifier :

    SI pion.estDansLaBase
    ET dé != 6
    → ce pion ne peut pas être sélectionné

## 4. Déplacement

Une fois le pion sur le parcours :

    dé = 4

Le pion doit avancer de 4 cases, pas 3, pas 5. Il faut donc avoir une
représentation logique du plateau :

    CASE 0
    CASE 1
    CASE 2
    CASE 3
    CASE 4
    ...
    CASE 51

Puis retour au début du parcours.

## 5. Deux pions sur une même case normale

Sur une case normale, il ne faut pas permettre une situation durable du genre :

    🔴 + 🔵

Le moteur doit traiter l'arrivée du pion comme une collision/capture :

    Case 25

    avant :
    🔵

    Rouge avance de 6 :

    🔴 → → → → → → 🔵

    arrivée :

    🔴

    🔵 → BASE

Un pion qui arrive sur une case occupée par un pion adverse le capture et le
renvoie à sa base, tandis que les cases étoilées sont protégées.

    🔴 🔵     → sur une case normale, capture, pas empilement permanent.

    ★
    🔴 🔵     → pas de capture, règle de protection des cases étoilées.

## 7. Les cases étoilées

Les étoiles sont des cases protégées.

    🔴 arrive
           ↓
          ★
           ↓
    🔵 déjà présent

    → pas de capture

## 8. Une capture donne également un avantage

    🔴 → 🔵

    🔵 retourne à BASE

Le joueur qui a effectué la capture obtient un tour supplémentaire. Le moteur
doit donc gérer deux sources différentes de tour supplémentaire :

    Dé = 6
           ↓
    TOUR SUPPLÉMENTAIRE

    OU

    Capture réussie
           ↓
    TOUR SUPPLÉMENTAIRE

## 9. Trois 6 consécutifs

    consecutiveSixes = 0

    SI dé == 6
        consecutiveSixes++
    SINON
        consecutiveSixes = 0

    SI consecutiveSixes == 3
        appliquer la règle des trois 6
        terminer le tour

Il faut surtout éviter de coder cette règle directement dans l'animation : elle
doit être dans le moteur de règles, indépendamment de l'interface.

## 10. Entrée dans le couloir final

    🔴 → 🔴 → 🔴 → 🔴 → 🔴 → 🏠

Un pion rouge ne peut entrer que dans son propre couloir rouge. Un pion bleu ne
peut pas entrer dans le couloir rouge.

## 11. Impossible de dépasser la maison

    🔴 est à 2 cases de HOME
    Dé = 5

Le mouvement est simplement illégal. Il ne faut surtout pas faire :

    🔴 → HOME → sortie → autre case

Il faut donc une fonction logique du type :

    isLegalMove(player, token, dice)

## 12. Arrivée à HOME

    Distance = 3
    Dé = 3
    → 🏠

Puis :

    Pion 1 = HOME
    Pion 2 = HOME
    Pion 3 = HOME
    Pion 4 = HOME

    → joueur gagnant.

## 13. Ordre des joueurs

    Joueur 1 → Joueur 2 → Joueur 3 → Joueur 4 → Joueur 1

Mais si Joueur 1 obtient un bonus :

    Joueur 1 → 6 → Joueur 1 → 6 → Joueur 1

Le moteur ne doit donc jamais simplement faire `currentPlayer++`. Il doit
déterminer :

    shouldGetAnotherTurn()

## 14. Ce qu'il faut absolument séparer

    LUDO ENGINE
    │
    ├── Game / Player / Token / Dice / Board
    ├── Rules
    ├── TurnManager
    ├── CollisionManager
    ├── WinManager
    └── Animation

Et surtout : **les animations ne doivent jamais décider des règles.**

## 15. Deux pions sur la même case — règle centrale

    ARRIVÉE DU PION
           │
           ▼
    La case est-elle une étoile ?
           │
       ┌───┴───┐
      OUI     NON
       │        │
       ▼        ▼
    PAS DE    Case occupée ?
    CAPTURE       │
              ┌───┴────┐
             NON       OUI
              │          │
              ▼          ▼
           NORMAL    Même joueur ?
                        │
                   ┌────┴────┐
                  OUI        NON
                   │           │
                   ▼           ▼
              BLOC/STACK     CAPTURE

Cette règle doit être **configurable**, parce que toutes les variantes de Ludo
ne traitent pas l'empilement exactement de la même manière.

## 16. Cas à tester

| Situation | Résultat attendu |
|---|---|
| 1-5 avec tous les pions en base | aucun mouvement possible |
| 6 avec pion en base | sortie possible |
| 6 avec plusieurs pions | choix du pion |
| 6 + capture | tour supplémentaire selon règles |
| 3 × 6 | appliquer pénalité |
| arrivée sur étoile | aucune capture |
| arrivée sur adversaire | capture |
| arrivée sur même couleur | bloc/empilement selon règle |
| déplacement dépassant HOME | mouvement interdit |
| pion déjà HOME | impossible à déplacer |
| joueur avec 4 pions HOME | victoire |
| plusieurs joueurs | ordre des tours correct |
| déconnexion | état de partie conservé |
| double clic sur pion | un seul mouvement |
| clic pendant animation | action bloquée |
| deux commandes simultanées | une seule acceptée |
| changement de joueur pendant animation | interdit |
| capture + animation | état logique mis à jour avant animation |
| reconnexion | restauration exacte du plateau |

---

# Règles et fonctionnalités ajoutées

---

## 17. 🧱 Les blocs (barrière)

La section 15 s'arrêtait à « BLOC/STACK » sans dire ce qu'est un bloc. Voici la
règle complète.

**Deux pions ou plus de la même couleur sur une même case du parcours forment un
BLOC.** Un bloc est infranchissable pour l'adversaire :

    Case 20 :  🔴 🔴          ← BLOC rouge

    🔵 est en case 17, dé = 5

    17 → 18 → 19 → [20] ✖
                    │
                    └── le bleu ne peut NI s'y poser NI la traverser

    → ce pion n'est pas sélectionnable

Un **seul** pion ne fait pas bloc — c'est une cible :

    Case 20 :  🔴            ← un seul pion

    🔵 arrive → CAPTURE

Le bloc protège aussi la case départ. Un adversaire ne peut pas sortir de base
si sa case de départ est occupée par un bloc :

    Case départ 🔵 occupée par 🔴 🔴

    Dé = 6  →  la sortie est ILLÉGALE

Un bloc de ma **propre** couleur (ou de mon partenaire en 2v2) ne me bloque
jamais :

    🔵 🔵 sur la case 20
    un 3e 🔵 traverse et s'empile librement

Le moteur doit donc distinguer :

    SI case contient >= 2 pions d'une MÊME couleur adverse
        → BARRIÈRE : passage interdit, arrivée interdite
    SINON SI case contient 1 pion adverse ET case non protégée
        → CAPTURE
    SINON SI case contient des pions de MA couleur
        → EMPILEMENT autorisé

**Règle configurable** (§15) : un interrupteur « Blocs (barrière) » dans
l'onglet *Règles du jeu*. OFF = comportement historique (on traverse et on
s'empile). ON = barrière.

> **Implémenté.** `GameController.blockRule`, `_barriersFor()`,
> `_pathIsClear()`. Interrupteur dans le panneau *Règles du jeu*.
> Tests : groupe `🧱 Blocs (barrière)`.

## 18. 🏆 Classement 1er – 4e

La section 12 s'arrêtait au « joueur gagnant ». Or une partie de Ludo ne
s'arrête PAS au premier arrivé : les autres joueurs continuent pour les places
suivantes.

    Bleu rentre son 4e pion
           ↓
    ranking = [BLEU]           ← 1er, c'est le gagnant
           ↓
    LA PARTIE CONTINUE
           ↓
    Vert rentre son 4e pion
           ↓
    ranking = [BLEU, VERT]     ← 2e
           ↓
    Rouge rentre son 4e pion
           ↓
    ranking = [BLEU, VERT, ROUGE]
           ↓
    Il ne reste que JAUNE
           ↓
    ranking = [BLEU, VERT, ROUGE, JAUNE]   ← dernier d'office
    phase = gameOver

Un joueur classé est **sauté** dans l'ordre des tours :

    Joueur 1 (classé ✔) → Joueur 2 → Joueur 3 → Joueur 2 → ...

Le moteur ne doit donc pas faire :

    SI 4 pions HOME → fin de partie          ✖

mais :

    SI 4 pions HOME
        ranking.ajouter(couleur)
        SI ranking.taille >= nbJoueurs - 1
            classer le dernier joueur restant
            phase = gameOver

**Exception mode équipe (2v2)** : la partie s'arrête dès qu'une équipe a ses 8
pions au centre — un joueur classé continue de jouer les pions de son
partenaire.

> **Implémenté.** `GameController.ranking`, `rankOf()`, `hasFinished()`,
> `recomputeStandings()`, `_nextPlayer()` saute les joueurs classés.
> Le panneau affiche le podium `1er · blue gagne / 2e · green / …`.
> Tests : groupe `🏆 Victoire et classement 1er–4e`.

## 19. 🤖 Jeu contre ordinateur

La section 1 annonce le jeu contre ordinateur sans définir l'IA. Voici sa règle
de décision, par priorité décroissante :

    COUP DISPONIBLE ?
           │
           ▼
    1. CAPTURE possible ?          → jouer (score 900)  ← donne un tour bonus
    2. ARRIVÉE exacte à HOME ?     → jouer (score 1000)
    3. ENTRÉE dans le couloir ?    → jouer (score 600)
    4. SORTIE de base (dé = 6) ?   → jouer (score 400)
    5. Case d'arrivée SÛRE (★) ?   → jouer (score 500)
    6. sinon → le pion le PLUS AVANCÉ (score 100 + progression)

L'IA passe par le **moteur**, jamais par l'animation :

    IA choisit
        ↓
    controller.pickAiPawn()
        ↓
    movePawn()                 ← le moteur décide capture / bonus / classement
        ↓
    l'animation SUIT

Répartition : le **premier joueur de l'ordre des tours est l'humain**, toutes
les autres couleurs sont pilotées par l'IA. Un délai de 650 ms sépare deux
coups d'IA pour que la partie reste lisible.

> **Implémenté.** `GameController.pickAiPawn()` / `_aiScore()` pour la
> décision, `_scheduleAiTurn()` / `_playAiTurn()` dans `main.dart` pour le
> pilotage. Interrupteur « Adversaires ordinateur » dans *Règles du jeu*.
> Tests : groupe `🤖 IA locale`.

## 20. 🔒 Verrou anti-bug pendant l'animation

Le tableau de la section 16 liste cinq cas d'entrée concurrente sans dire
comment les traiter. Règle unique qui les couvre tous : **un verrou levé
pendant toute la durée du glissement**.

    CLIC SUR UN PION
           │
           ▼
    verrou levé ?
       ┌───┴───┐
      OUI     NON
       │        │
       ▼        ▼
    IGNORÉ   1. le MOTEUR applique le coup
             2. verrou ← levé
             3. l'animation démarre
             4. fin d'animation → verrou ← baissé

Ce que le verrou couvre :

| Situation | Comportement |
|---|---|
| double clic sur pion | 2e clic ignoré → un seul mouvement |
| clic pendant animation | action bloquée |
| deux commandes simultanées | une seule acceptée |
| relance du dé pendant animation | bouton désactivé |
| changement de joueur pendant animation | interdit |
| capture + animation | l'état logique est déjà à jour quand l'explosion part |

L'ordre est non négociable : **le moteur d'abord, l'animation ensuite.** Quand
le pion commence à glisser, capture, tour supplémentaire et classement sont
déjà décidés.

> **Implémenté.** `_animating` dans `main.dart` : gardes en tête de
> `_movePawn`, `_rollDiceRandom`, `_endTurn`, désactivation du dé
> (`canRollDice`) et du bouton *Lancer le dé* (`busy`).

## 21. 🎯 Nombre de joueurs

La section 1 dit « 2 à 4 joueurs dans le mode classique ». LudoPoly va au-delà :

    1 joueur   → bac à sable / entraînement contre l'IA
    2 joueurs  → classique
    3 joueurs  → classique
    4 joueurs  → classique (plateau 15×15, 52 cases)
    5 joueurs  → plateau étendu
    6 joueurs  → plateau étendu

Le classement (§18) s'adapte : la partie s'arrête quand `nbJoueurs - 1` places
sont attribuées.

> **Déjà en place.** Sélecteur *Nb joueurs* 1–6 dans le panneau *Setup*,
> géométrie 5/6 joueurs dans `board5p_geometry.dart`.

## 22. 🌐 Multijoueur en ligne et privé — NON IMPLÉMENTÉ

La section 1 annonce le multijoueur en ligne et privé, et la section 16 teste
« déconnexion → état de partie conservé » et « reconnexion → restauration
exacte du plateau ». **Rien de tout cela n'existe aujourd'hui**, et cela ne peut
pas exister en 100 % local : il faut un serveur d'état partagé.

Spécification pour plus tard :

    CLIENT A ──┐
               ├──► SERVEUR D'ÉTAT ──► diffusion à tous les clients
    CLIENT B ──┘         │
                         └── seule source de vérité des règles

    Règle d'or : le CLIENT n'applique jamais une règle lui-même.
                 Il envoie une INTENTION, le serveur répond par un ÉTAT.

    DÉCONNEXION
           ↓
    l'état de la partie reste sur le SERVEUR
           ↓
    RECONNEXION
           ↓
    le client redemande l'état complet
           ↓
    plateau restauré à l'identique (pions, tour, dé, série de 6, classement)

Pré-requis côté moteur, qui manque encore : une **sérialisation** de
`GameState` + `GameController` (positions des 16 pions, joueur courant, valeur
du dé, `consecutiveSixes`, `ranking`, règles actives) en JSON, et sa relecture.

> **Non implémenté — hors périmètre 100 % local.** Aucun code réseau n'a été
> ajouté. Les deux lignes « déconnexion » et « reconnexion » du tableau §16
> restent donc non couvertes par les tests.

## 23. 🧪 Cahier de tests exécutable

La section 16 donne un tableau de situations. Il est désormais **exécutable** :

    flutter test test/rules_test.dart

Correspondance tableau §16 → test :

| Situation §16 | Couvert par |
|---|---|
| 1-5 avec tous les pions en base | `🎲 … aucun mouvement possible` |
| 6 avec pion en base | `🎲 … sortie possible` |
| 6 avec plusieurs pions | `🎲 … 4 pions sélectionnables` |
| 6 + capture → tour supplémentaire | `🎲 6 → tour supplémentaire`, `⚔️ … capture + rejeu` |
| 3 × 6 | `🔄 3 × 6 → tour perdu` |
| arrivée sur étoile | `⚔️ … AUCUNE capture` |
| arrivée sur adversaire | `⚔️ … capture + rejeu` |
| arrivée sur même couleur | `🧱 … un bloc de MA couleur ne me bloque pas` |
| déplacement dépassant HOME | `🏠 … mouvement interdit` |
| pion déjà HOME | `🏠 … impossible à déplacer` |
| joueur avec 4 pions HOME | `🏆 … 1er au classement` |
| plusieurs joueurs / ordre des tours | `🔄 Ordre des tours` |
| déconnexion / reconnexion | **non couvert** (voir §22) |
| double clic, clic pendant anim, commandes simultanées | verrou §20 (UI, non testé unitairement) |

> **Implémenté.** 27 tests, tous verts.

## 24. 📐 Où vit chaque règle

Traduction concrète de l'architecture §14 sur le code existant :

    lib/game/game_controller.dart   Rules + TurnManager + CollisionManager
                                    + WinManager + Dice + IA
    lib/game/game_state.dart        Game (les 16 pions)
    lib/game/pawn.dart              Token (base / ring / couloir / home)
    lib/game/player_color.dart      Player (couleur)
    lib/game/board_path.dart        Board (52 cases, départs, étoiles)
    lib/game/board5p_geometry.dart  Board 5/6 joueurs
    lib/main.dart                   Animation UNIQUEMENT + verrou d'entrée

Règle d'architecture à ne jamais enfreindre :

    main.dart  ne décide JAMAIS d'une règle.
               Il appelle le moteur, puis anime le résultat.

## 25. ↩️ Boutons Retour / Rejouer (undo / redo)

Outils de mise au point, en bas de la carte *Jeu manuel*. **Retour** annule la
dernière action et remet la partie exactement dans l'état d'AVANT ;
**Rejouer** la rétablit.

    ROUGE lance 4
           ↓
    son pion avance de 4 cases
           ↓
    le tour passe au VERT
           ↓
    [ Retour ]
           ↓
    le pion revient à sa case
    le tour revient à ROUGE
    le dé n'a pas encore été lancé

L'unité annulée est **le lancer et le déplacement joué avec** : un instantané
est pris juste AVANT chaque lancer, jamais entre le lancer et le choix du
pion. Les éditions manuelles (*Pions dans la Maison*) sont également
empilées.

Ce que l'instantané restaure :

| Élément | Restauré |
|---|---|
| position des 16 pions | oui — y compris un pion capturé, qui ressort de la base |
| joueur courant | oui |
| valeur du dé | oui (remise à « pas encore lancé ») |
| série de 6 | oui |
| classement / gagnant | oui — un rang acquis est retiré |

Chaque pression supplémentaire remonte d'un coup de plus (pile de 100 coups).
**Rejouer** redescend la pile coup par coup :

    coup A ─ coup B ─ coup C          état courant
       │       │        └── [Retour] ──► on remonte à B
       │       └─────────── [Retour] ──► on remonte à A
       └───────────────────[Rejouer]──► on redescend vers B, puis C

Règle du redo : **jouer un nouveau coup après une annulation vide la pile de
rétablissement.** On ne rejoue pas une branche qu'on vient d'abandonner.

    A ─ B ─ C
        └── [Retour] [Retour]  →  on est en A, {B, C} rétablissables
        └── nouveau coup D     →  {B, C} sont perdus, Rejouer est grisé

Les deux boutons sont grisés quand il n'y a rien à faire et pendant une
animation. `Redémarrer jeu` vide les deux piles.

L'IA est volontairement **non replanifiée** après un retour : sinon, revenir
sur le tour d'une couleur pilotée par l'ordinateur la ferait rejouer
immédiatement le coup qu'on vient d'annuler. Elle repart au lancer suivant.

> **Implémenté.** `GameSnapshot` / `PawnSnapshot`, `pushHistory()`,
> `stepBack()`, `stepForward()`, `clearHistory()` dans
> `game_controller.dart` ; `_stepBack()` / `_stepForward()` et les boutons
> *Retour* / *Rejouer* dans `main.dart`.
> Tests : groupes `↩️ Retour arrière (stepBack)` et
> `↩️ Undo / Redo sur une séquence jouée`.

## 26. 🐞 Le sélecteur du Jeu manuel doit suivre le tour réel

Bug constaté : « rouge fait 6, un pion sort ; ensuite rouge fait 3, et c'est un
pion **vert** qui sort ».

Cause : le sélecteur *Couleur* de la carte *Jeu manuel* restait figé sur la
couleur choisie, alors que le lancer venait de passer la main.

    Jeu manuel : [ROUGE] sélectionné
           ↓
    lancer 3  →  le moteur passe la main au VERT
           ↓
    Jeu manuel : [ROUGE] toujours affiché   ✖   mais c'est au VERT de jouer
           ↓
    les pions VERTS sont surlignés et cliquables
           ↓
    le clic suivant sort un pion VERT

Le moteur n'a jamais été en cause : un lancer ne déplace que les pions du
joueur courant (vérifié par les tests `🐞 Bug signalé`). C'était l'interface
qui mentait sur le joueur actif.

Règle : **le sélecteur de couleur reflète TOUJOURS le joueur dont c'est le
tour.** Il est resynchronisé après chaque lancer, chaque déplacement et chaque
Retour / Rejouer.

> **Corrigé.** `_syncManualPlayer()` dans `main.dart`, appelé depuis `_roll()`,
> `_movePawn()`, `_stepBack()` et `_stepForward()`.
> Tests : groupe `🐞 Bug signalé — « rouge 6 sort un pion, puis rouge 3 »`.

## 27. 🎞️ Rythme du déplacement

Deux défauts d'animation : le coup automatique partait avant qu'on ait pu lire
le dé, et le pion glissait d'un trait de sa case de départ à sa case d'arrivée
— on ne voyait pas les cases traversées.

### Pause de lecture du dé

Quand un seul pion est jouable, le moteur le désigne tout seul. Mais le dé doit
rester lisible avant que le pion ne bouge :

    LANCER
       ↓
    dé affiché + pion surligné      ← 550 ms, aucune commande acceptée
       ↓
    le pion part

### Le pion s'arrête sur chaque case

    Dé = 4, pion en case 10

    AVANT                          MAINTENANT
    10 ──────────────► 14          10 → 11 → 12 → 13 → 14
    un seul glissement             une étape de 190 ms par case
    (400 ms en diagonale)          (760 ms le long du parcours)

Le trajet suit le parcours réel — y compris le passage de la case 51 à la case
0, et l'entrée du ring dans le couloir final :

    ring:51 → homeColumn:0 → homeColumn:1 → … → 🏠

Durées : **190 ms par case**. Une sortie de base reste un saut unique de
**220 ms** — le pion est téléporté du bac à sa case départ, il ne parcourt pas
6 cases.

### Qui décide de quoi

Le moteur applique le coup **d'un bloc** et calcule séparément la liste des
cases traversées. L'interface ne fait que dessiner le pion sur ces cases-là,
l'une après l'autre, pendant que l'état logique est déjà à l'arrivée :

    moteur : movePawn()      → capture, bonus, classement : tout est décidé
    moteur : pathFor()       → [11, 12, 13, 14]  (pure géométrie)
    interface : dessine le pion sur 11, puis 12, puis 13, puis 14

L'animation ne décide toujours rien (§14). Un Retour / Rejouer coupe le trajet
en cours : aucun timer d'une position abandonnée ne peut retomber sur le
plateau.

> **Implémenté.** `PawnStep` et `GameController.pathFor()` pour le trajet ;
> `_travelStep`, `_stepDuration`, `_baseExitDuration`, `_dicePause`,
> `_scheduleAutoMove()` et `_cancelAnimations()` dans `main.dart`.
> Tests : groupe `🎞️ Trajet case par case (pathFor)`.

## 28. 🎲 Le dé central : une valeur, la couleur du joueur courant

Bug constaté : « bleu joue, le dé est bleu, bleu fait 5 ; ensuite le dé doit
devenir rouge et **rester sur 5** en attendant que rouge joue ».

Cause : le dé était stocké **par couleur** (`Map<PlayerColor, int>`). Quand la
main passait, le plateau affichait la valeur mémorisée du NOUVEAU joueur —
c'est-à-dire son ancien lancer, ou une face aléatoire s'il n'avait jamais
lancé. La valeur qui venait de sortir disparaissait de l'écran.

    AVANT                              MAINTENANT

    bleu lance 5                       bleu lance 5
       ↓                                  ↓
    dé bleu · 5                        dé bleu · 5
       ↓ la main passe au rouge           ↓ la main passe au rouge
    dé rouge · 2  ✖                    dé rouge · 5  ✔
    (vieux lancer du rouge)            (la valeur ne change qu'au
                                        prochain lancer)

Règle : **il n'y a qu'UN dé sur le plateau.** Il porte la dernière valeur
sortie, tous joueurs confondus, et prend la couleur du joueur dont c'est le
tour. La valeur ne change qu'au lancer suivant.

    lancer de bleu = 5   →   dé BLEU 5
    fin du tour de bleu  →   dé ROUGE 5      ← même valeur, autre couleur
    lancer de rouge = 3  →   dé ROUGE 3
    fin du tour de rouge →   dé VERT 3
    …

### Quand exactement le dé change-t-il de couleur ?

À l'ARRIVÉE du pion, pas au départ. Le moteur passe la main dès que le coup
est appliqué — c'est-à-dire au moment où le pion s'élance. Si le dé suivait
bêtement le joueur courant, il changerait de couleur pendant que le pion est
encore en train de compter ses cases :

    rouge lance 4
       ↓
    dé ROUGE 4   ─┐
                  │  le pion rouge compte : 1 … 2 … 3 … 4
    dé ROUGE 4   ─┘  ← le dé RESTE rouge pendant tout le trajet
       ↓
    le pion est arrivé
       ↓
    dé VERT 4        ← c'est seulement ICI que la couleur change,
                       pour prévenir le vert que c'est à lui

Le dé retient donc la couleur du pion qui compte (`_diceColorHold`) et ne la
relâche qu'à la fin du trajet.

Avant le tout premier lancer d'une partie, aucune valeur n'est sortie : le
plateau montre une face décorative tirée au hasard.

Deux détails d'affichage, qui donnaient l'impression que le dé ne suivait pas :

- Le dé est une image par couleur et par valeur (`Dice_5_red.png`). Au
  changement de couleur, Flutter vidait la case le temps de décoder la
  nouvelle image et le dé **disparaissait pendant une frame** —
  `gaplessPlayback` garde l'image précédente jusqu'à ce que la suivante soit
  prête.
- Conséquence de ce qui précède : à la PREMIÈRE apparition d'une face donnée,
  le dé gardait visiblement l'ancienne couleur le temps du chargement. Les
  **24 faces** (6 valeurs × 4 couleurs) sont désormais préchargées au
  démarrage, le changement de couleur est instantané.

> **Corrigé.** `GameController.lastRoll` (persiste après le passage de main,
> compris dans les instantanés donc restauré par Retour / Rejouer) ;
> `_shownDice`, `_shownDiceColor`, `_diceColorHold`, `_initialDiceFace` et
> `_precacheDice()` dans `main.dart` remplacent l'ancienne
> `Map<PlayerColor, int>`.
> Tests : groupe `🎲 Le dé affiché reste sur la dernière valeur sortie`.

## 30. 🎯 Le pion capturé reste visible pendant l'attaque

Bug constaté : quand un pion X est capturé par un pion Y, le pion X
disparaît tout de suite au lieu d'attendre que Y arrive sur sa case.

    X en case 20
    Y lance le dé, va vers la case 20
       ↓
    X disparaît immédiatement  ✖  (avant que Y n'arrive)
    
    vs
    
       ↓
    Y traverse les cases …
    X reste visible en case 20    ← c'est là qu'il faut le voir se faire capturer
       ↓
    Y arrive sur la case 20
       ↓
    X disparaît (retour à la base)  ✔

Cause : le moteur applique la capture tout de suite quand on appelle
`movePawn()` — l'état logique change, le pion passe à `location.base`. Le
rendu lisait directement `p.location`, donc le pion disparaissait avant la fin
de l'animation du trajet.

Solution : garder le pion affiché à son ancienne position pendant tout le
trajet de l'attaquant, comme on le fait avec `_travelStep`. La map
`_captureOverride` mappe chaque pion capturé à sa location précédente, ce qui
force l'affichage à l'ancienne place. À la fin du trajet, on retire l'override
et le pion s'affiche enfin à sa vraie position (la base).

Ordre de priorité dans `_pawnCenter()` :
1. Si en trajet → affiche la case du trajet (`travelStep`)
2. Si capturé → affiche l'ancienne case (`captureOverride`)
3. Sinon → affiche la vraie position du pion (`p.location`)

> **Corrigé.** `Map<Pawn, PawnLocation> _captureOverride` dans `main.dart` ;
> priorité d'affichage dans `_pawnCenter()` et `stackKey()` ; nettoyage du
> map à la fin du trajet et lors des annulations.

## 29. 🧩 Chaque pion garde sa place

Bug constaté : quand un pion d'une couleur X dépasse un pion d'une couleur Y,
ou le rejoint sur sa case départ, les pions de couleur X **semblent
s'échanger**.

Deux causes, toutes deux dans le rendu — le moteur n'a jamais bougé le mauvais
pion (§26).

### Cause 1 — les pions n'avaient pas d'identité

Les pions sont empilés dans un `Stack`, dans une liste construite à chaque
image. Sans clé, Flutter apparie ses enfants **par position dans la liste** :

    image N     [ pion A , pion B , pion C ]
                    │        │        │
    image N+1   [ pion B , pion A , pion C ]   ← A a changé de case,
                    │        │                   l'ordre a bougé
                    ▼        ▼
              l'animation de A est appliquée à B, et inversement

Le pion qui bougeait « donnait » son déplacement à son voisin : à l'écran, les
deux paraissaient permuter. Chaque pion porte maintenant une clé d'identité
(`pawn_red_2`), et Flutter suit le bon pion quel que soit l'ordre de la liste.

### Cause 2 — le décalage latéral dépendait du joueur courant

Quand plusieurs pions partagent une case, ils sont décalés latéralement pour
rester tous visibles. Ce décalage était calculé à partir d'un tri qui plaçait
le pion du joueur courant **en dernier** — donc à chaque changement de tour,
les pions d'une même case échangeaient leur place :

    case 13, tour du ROUGE :   [🔵][🔴]
    case 13, tour du BLEU  :   [🔴][🔵]   ✖  ils ont permuté sans bouger

Le décalage suit désormais un ordre **stable** (couleur, puis numéro de pion),
indépendant du tour. Le joueur courant passe toujours devant, mais c'est
désormais un simple ordre de peinture : il ne déplace plus personne.

    case 13, quel que soit le tour :  [🔵][🔴]   position fixe
    tour du rouge → 🔴 est peint par-dessus, sans changer de place

> **Corrigé.** Clés `ValueKey` sur les trois passes de rendu du pion
> (sélecteur, image, zone de clic), tri stable pour `stackOffsets`, tri par
> joueur courant réservé à l'ordre de peinture, et délai d'animation idle
> indexé sur l'identité du pion et non sur sa place dans la liste.
