# Règles du jeu — Ludo King

> Ce document décrit les règles **spécifiques à Ludo King** (app mobile/web par Gametion).
> Certaines diffèrent du Ludo traditionnel (plateau physique).

---

## 1. Présentation

- 2 à 6 joueurs
- Chaque joueur possède **4 pions** d'une couleur (bleu, rouge, vert, jaune — étendu à 6 couleurs en variantes)
- Le plateau est en forme de croix avec un parcours de **52 cases** communes + une **colonne maison** de 5 cases colorées par joueur
- Objectif : amener ses 4 pions de la base (yard) jusqu'au centre du plateau (home)

---

## 2. Mise en place

- Les 4 pions de chaque joueur démarrent dans leur **base** (coin coloré du plateau)
- Le joueur qui obtient le plus haut lancé commence ; le tour passe ensuite dans le sens horaire

---

## 3. Règles du dé

| Situation | Règle |
|---|---|
| **Sortir un pion de la base** | Il faut obligatoirement un **6** |
| **Lancer un 6** | Le joueur rejoue immédiatement (tour bonus) |
| **3 six consécutifs** | Le tour est **annulé** : aucun déplacement n'est effectué et le pion bougé sur le 3e six **retourne à la base**. Le dé passe au joueur suivant |
| **Aucun mouvement possible** | Le tour est perdu, le dé passe au joueur suivant |

---

## 4. Déplacement

- Les pions avancent dans le **sens horaire** sur le parcours commun
- Le nombre de cases correspond exactement au chiffre du dé
- Un pion sort de la base sur la **case de départ** (case colorée fléchée) de sa couleur lorsqu'un 6 est lancé
- Après un tour complet du plateau (~51 cases communes), le pion entre dans sa **colonne maison** (5 cases de sa couleur menant au centre)

---

## 5. Capture (couper / manger un pion)

- Si un pion atterrit sur une case occupée par un pion **adverse**, le pion adverse est **renvoyé à sa base**
- L'adversaire devra relancer un 6 pour le ressortir
- **Bonus** : capturer un pion adverse donne un **tour bonus** (relance du dé)
- On ne peut **pas** capturer un pion sur une case protégée (voir §6)

---

## 6. Cases protégées (Safe Zones)

Le plateau comporte **8 cases protégées** au total :

| Type | Nombre | Description |
|---|---|---|
| **Cases de départ** | 4 | Cases colorées avec une flèche — une par joueur |
| **Cases étoilées (★)** | 4 | Cases marquées d'une étoile, réparties sur le parcours |

### Règles des cases protégées

- Un pion posé sur une case protégée **ne peut pas être capturé**
- **Plusieurs pions** (même de couleurs différentes) peuvent coexister sur une même case protégée, sans limite de nombre
- La **colonne maison** (5 cases colorées avant le centre) est également protégée : seuls les pions de la couleur correspondante peuvent y entrer

---

## 7. Blocs (Barricades)

- Quand **2 pions de la même couleur** se retrouvent sur la même case, ils forment un **bloc**
- Un bloc **ne peut pas être traversé ni capturé** par les pions adverses
- Pour déplacer un bloc : il faut lancer un **nombre pair** — le bloc avance alors de **la moitié** de ce nombre (ex : dé = 6 → bloc avance de 3)
- Un bloc peut aussi être séparé : le joueur choisit de ne déplacer qu'un seul des deux pions

---

## 8. Entrée au centre (Home)

- Pour faire entrer un pion au centre (home), il faut lancer le **nombre exact** de cases restantes
- Si le dé dépasse le nombre nécessaire, le pion **ne bouge pas** et le coup est perdu (ou un autre pion est joué)
- Quand un pion atteint le centre, le joueur obtient un **tour bonus**

---

## 9. Victoire

- Le **premier joueur** à amener ses **4 pions au centre** remporte la partie
- Dans certains modes, un classement 1er/2e/3e/4e est établi

---

## 10. Modes de jeu

### Classic Mode

- 2 à 4 joueurs
- Règles standard décrites ci-dessus
- Il faut un **6 pour sortir** un pion de la base
- Il faut amener les **4 pions** au centre pour gagner
- Peut se jouer en ligne, contre l'IA, ou en local (pass-and-play)

### Quick Mode

- **2 joueurs** uniquement
- Tous les pions sont **déjà sortis** de la base au début (pas besoin de 6)
- Il suffit d'amener **2 pions** (sur 4) au centre pour gagner
- Partie limitée dans le temps : si le chrono expire, le joueur avec le score le plus élevé gagne
- Mode conçu pour des parties rapides (~5 min)

### Master Mode

- Destiné aux joueurs expérimentés
- Gameplay plus stratégique et compétitif
- Variantes de règles renforcées (tactique, anticipation)

### Team Mode (Mode en équipe / 2v2)

- **4 joueurs obligatoirement**, organisés en **2 équipes de 2**
- Les coéquipiers sont en **diagonale** sur le plateau (cases opposées)
  - Configuration LudoPoly : **Bleu + Vert** vs **Jaune + Rouge**
- **1 dé par tour** (comme en mode normal), rotation horaire des 4 joueurs inchangée
- **Pas de capture entre coéquipiers** : un pion qui atterrit sur une case occupée par un pion de son **partenaire** **ne le mange pas** (ils peuvent cohabiter). La capture ne concerne **que les pions de l'équipe adverse**.
- **Aide au partenaire** : si un joueur a déjà ses **4 pions** au centre, à son tour il continue de lancer le dé mais joue avec les **pions de son coéquipier** restés en jeu
- **Condition de victoire** : la **première équipe** à amener ses **8 pions** (4 + 4) au centre gagne
- Toutes les autres règles standard (blocks, cases protégées, 6 pour sortir, tours bonus) restent en vigueur

### Autres modes

| Mode | Description |
|---|---|
| **Online Multiplayer** | Matchmaking contre des joueurs du monde entier |
| **Vs Computer** | Contre l'IA (difficulté ajustable) |
| **Pass & Play** | Multijoueur local sur un seul appareil |
| **Friends / Facebook** | Invitation d'amis via Facebook ou lien |

---

## 11. Récapitulatif des tours bonus

Un joueur **relance le dé** (tour bonus) dans les cas suivants :

1. Il lance un **6**
2. Il **capture** un pion adverse
3. Il fait **entrer un pion au centre** (home)

> Exception : 3 six consécutifs → tour annulé, pas de bonus.

---

## 12. Résumé des différences Ludo King vs Ludo traditionnel

| Aspect | Ludo traditionnel | Ludo King |
|---|---|---|
| Sortie de base | 6 uniquement (ou 1 selon variantes) | **6 uniquement** |
| 3 six consécutifs | Tour perdu (règle variable) | Tour annulé + **pion renvoyé à la base** |
| Blocs | Non standard | **Oui** : 2 pions = bloc infranchissable, déplacement pair/moitié |
| Cases protégées | 4 étoiles (variable) | **8 cases** : 4 départs + 4 étoiles |
| Capture → bonus | Pas toujours | **Oui**, toujours un tour bonus |
| Entrée home → bonus | Pas toujours | **Oui**, toujours un tour bonus |
| Entrée home | Jet exact (souvent) | **Jet exact obligatoire** |
| Mode Quick | N'existe pas | 2 joueurs, pions déjà sortis, 2 pions suffisent |
| Multijoueur en ligne | N'existe pas | Oui, matchmaking mondial |
| Jusqu'à 6 joueurs | 4 max | **6 joueurs** possibles |

---

## Sources

- [Ludo King Complete Wiki Guide — ludokingindia.com](https://www.ludokingindia.com/)
- [Republic World — How to play Ludo King](https://www.republicworld.com/tech/gaming/how-to-play-ludo-king)
- [Sportskeeda — Ludo King Rules, Features, and Tricks](https://www.sportskeeda.com/esports/win-every-ludo-king-game-ludo-king-rules-features-and-tricks-to-win-more)
- [Zupee — Important Ludo Rules](https://www.zupee.com/ludo/ludo-rules/)
- [RK Ludo — How to Use Safe Squares](https://blog.rkludo.com/how-to-use-safe-squares-in-ludo/)
- [Ask.com — Ludo King vs Traditional Ludo](https://www.ask.com/entertainment/ludo-king-vs-traditional-ludo-key-differences)
- [Ludo Empire — Game Modes Differences](https://ludoempire.com/blog/differences-between-the-ludo-game-modes/)
- [Wikipedia — Ludo](https://en.wikipedia.org/wiki/Ludo)
