// « Comment jouer » : la règle du jeu, et rien d'autre.
//
// Une page de lecture, pas un écran de jeu. Le plateau n'y a rien à faire :
// on vient ici pour comprendre, pas pour jouer.

import 'package:flutter/material.dart';

import 'game/app_background.dart';
import 'game/background_config.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({
    super.key,
    required this.onExit,
    this.background = const BackgroundConfig(),
  });

  final VoidCallback onExit;
  final BackgroundConfig background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground.board.wrap(
        config: background,
        SafeArea(
          child: Column(
            children: [
              // La barre : le titre, et le retour au menu.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '🎲 COMMENT JOUER À LUDOPOLY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const Key('how-home'),
                        customBorder: const CircleBorder(),
                        onTap: onExit,
                        child: const Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(Icons.home_outlined,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                      children: const [_Rules()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- mise en forme -------------------------------------------------------

const Color _ink = Colors.white;
const Color _dim = Color(0xCCFFFFFF);
const Color _accent = BgPalette.amber;

/// Un titre de section.
Widget _h(String text) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(text,
          style: const TextStyle(
            color: _accent,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.25,
          )),
    );

/// Un sous-titre, pour les étapes et les cartes.
Widget _sub(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text,
          style: const TextStyle(
            color: _ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.3,
          )),
    );

/// Un paragraphe.
Widget _p(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(color: _dim, fontSize: 13.5, height: 1.45)),
    );

/// Une liste à puces.
Widget _list(List<String> items) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ',
                      style: TextStyle(color: _accent, fontSize: 13.5)),
                  Expanded(
                    child: Text(i,
                        style: const TextStyle(
                            color: _dim, fontSize: 13.5, height: 1.45)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

/// Un encadré : ce qu'il ne faut pas rater.
Widget _note(String text) => Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: _accent, width: 3)),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(text,
          style: const TextStyle(color: _ink, fontSize: 13, height: 1.45)),
    );

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _h('1. 🎯 Le but du jeu'),
        _p('L\'objectif de LudoPoly est de faire avancer tes pions autour du '
            'plateau pour les amener dans ta maison avant tes adversaires.'),
        _p('Pendant la partie, tu peux :'),
        _list([
          'déplacer tes pions grâce au dé ;',
          'capturer les pions adverses ;',
          'utiliser les cases spéciales ;',
          'tirer des cartes Chance ;',
          'conserver certaines cartes Chance pour les utiliser au meilleur '
              'moment ;',
          'utiliser les effets spéciaux pour ralentir tes adversaires ou '
              'accélérer tes propres pions.',
        ]),
        _p('Le joueur qui réussit à faire rentrer tous ses pions dans sa '
            'maison remporte la partie.'),

        _h('2. ▶️ Comment se déroule un tour ?'),
        _p('Lorsque c\'est ton tour :'),
        _sub('Étape 1 — Lance le dé 🎲'),
        _p('Tu lances le dé et obtiens une valeur. Cette valeur indique de '
            'combien de cases ton pion peut avancer.'),
        _sub('Étape 2 — Choisis ton pion'),
        _p('Tu choisis parmi tes pions celui que tu souhaites déplacer. Le '
            'jeu indique automatiquement les déplacements possibles.'),
        _sub('Étape 3 — Déplace ton pion'),
        _p('Ton pion avance du nombre de cases indiqué par le dé. Pendant son '
            'déplacement, plusieurs choses peuvent se produire :'),
        _list([
          'ton pion peut arriver sur une case normale ;',
          'il peut capturer un adversaire ;',
          'il peut arriver sur une case Étoile ;',
          'il peut arriver sur une case Chance ;',
          'il peut tomber sur un Vortex ;',
          'une carte Chance peut produire un effet.',
        ]),
        _sub('Étape 4 — Le jeu applique les règles'),
        _p('Lorsque ton pion arrive sur une case spéciale, LudoPoly applique '
            'automatiquement l\'effet correspondant.'),

        _h('3. 🏠 La maison et la ligne droite'),
        _p('Après avoir fait le tour du plateau, ton pion doit rejoindre ta '
            'dernière ligne droite, puis avancer jusqu\'aux cases de ta '
            'maison.'),
        _note('Tu dois respecter exactement le nombre de cases nécessaires. '
            'Ton pion ne doit pas dépasser sa destination.'),
        _p('Une fois arrivé au bout de sa progression, ton pion entre dans ta '
            'maison.'),

        _h('4. 🌀 Les cases Vortex — « trou noir »'),
        _p('Chaque joueur possède ses propres cases Vortex. Un Vortex est une '
            'case spéciale qui permet de téléporter un pion vers une autre '
            'partie du plateau.'),
        _note('⚠️ Seul le joueur auquel appartient le Vortex peut l\'utiliser.'),
        _p('Il existe deux Vortex différents.'),
        _sub('🟢 Le bon Vortex'),
        _p('Il se trouve sur la première case après la boîte de départ. '
            'Lorsque ton pion arrive sur ton Vortex, il est envoyé directement '
            'sur la première case de l\'adversaire située en diagonale.'),
        _p('Cette case est de ta couleur, et seul ton joueur peut utiliser ce '
            'Vortex. Le déplacement est automatique.'),
        _sub('🔴 Le mauvais Vortex'),
        _p('Il se trouve sur la première case de ta dernière ligne droite. '
            'Lorsque ton pion tombe dessus, il revient sur la première case de '
            'la dernière ligne droite de l\'adversaire située en diagonale.'),
        _note('⚠️ Le bon Vortex permet d\'avancer rapidement. Le mauvais '
            'Vortex peut faire revenir ton pion en arrière.'),

        _h('5. ⭐ Les cases Étoile'),
        _p('Les cases Étoile sont des cases de protection du plateau. Elles '
            'permettent au pion qui s\'y trouve de bénéficier de la protection '
            'prévue par les règles du jeu.'),
        _p('Les cases Chance sont placées 2 cases avant les cases Étoile de '
            'protection.'),

        _h('6. 🍀 Les cases Chance'),
        _p('Il existe 4 cases Chance sur le plateau. Lorsqu\'un pion arrive '
            'sur une case Chance, le joueur reçoit une carte Chance.'),
        _p('Les cartes Chance sont divisées en deux catégories :'),
        _list([
          '⚡ Cartes Chance immédiates — l\'effet est exécuté immédiatement.',
          '🃏 Cartes Chance différées — la carte est conservée par le joueur '
              'afin d\'être utilisée plus tard.',
        ]),

        _h('7. 🃏 Les cartes Chance immédiates'),
        _p('Les cartes immédiates fonctionnent comme un talon de cartes. Au '
            'début de la partie, le talon est mélangé. Les cartes sont ensuite '
            'utilisées une par une.'),
        _p('Lorsque toutes les cartes ont été utilisées, le talon est '
            'retourné — il n\'est pas mélangé — et les cartes recommencent à '
            'être utilisées dans cet ordre.'),
        _sub('👤 Cartes concernant les pions'),
        _list([
          '↩️ Reculez de 3 cases — le pion concerné recule de 3 cases.',
          '↪️ Avancez de 3 cases — le pion concerné avance de 3 cases.',
          '🚪 Tous vos pions sortent d\'un coup — tous tes pions pouvant '
              'sortir de leur zone de départ sortent immédiatement.',
          '🎯 Placez votre pion juste devant la sortie — le pion est '
              'automatiquement placé sur la case située juste devant la '
              'sortie.',
          '🏠 Retournez votre pion dans votre boîte de départ.',
          '🛡️ Pion invulnérable pendant 2 tours — il ne peut pas être '
              'capturé pendant 2 tours.',
          '❄️ Pion figé pendant 2 tours — il ne peut pas effectuer '
              'normalement ses déplacements pendant 2 tours.',
          '⚔️ Capture vers l\'avant — ton pion avance jusqu\'au premier pion '
              'adverse situé sur ton chemin à venir et le capture.',
          '⚔️ Capture vers l\'arrière — ton pion recule jusqu\'au premier pion '
              'adverse situé sur le chemin déjà parcouru et le capture.',
        ]),

        _h('8. 🎲 Cartes Chance concernant les dés'),
        _p('Certaines cartes modifient les résultats du dé.'),
        _list([
          '➗ Demi-dé pendant 2 tours — le dé ne peut donner que 1, 2 ou 3. '
              'L\'effet commence à partir du tour suivant.',
          '✖️ Double-dé pendant 2 tours — les résultats possibles sont 2, 4, '
              '6, 8, 10 ou 12. L\'effet commence à partir du tour suivant.',
          '🎲🎲 Deux dés pendant 2 tours — le joueur joue avec deux dés. Le '
              'déplacement total peut donc être compris entre 2 et 12 cases. '
              'L\'effet commence à partir du tour suivant.',
        ]),

        _h('9. 🃏 Les cartes Chance différées'),
        _p('Les cartes différées ne sont pas forcément utilisées '
            'immédiatement. Chaque joueur possède son propre talon de cartes '
            'différées.'),
        _note('Chaque joueur peut conserver jusqu\'à 4 cartes différées.\n'
            '⚠️ Un joueur ne peut utiliser qu\'une seule carte différée à la '
            'fois pendant son tour.'),

        _h('10. ⏱️ Quand utiliser une carte différée ?'),
        _p('Les cartes portent une indication qui explique quand elles peuvent '
            'être utilisées.'),
        _list([
          '🔵 AVANT — la carte doit être jouée avant de lancer le dé.',
          '🟠 APRÈS — la carte doit être jouée après le lancer du dé.',
          '🟣 AVANT / APRÈS — la carte peut être jouée avant ou après le '
              'lancer du dé.',
        ]),

        _h('11. 👤 Cartes différées — pions'),
        _list([
          '🛡️ Pion invulnérable pendant 2 tours — AVANT. Avant de lancer ton '
              'dé, tu peux rendre un de tes pions invulnérable pendant 2 '
              'tours. Il ne peut alors pas être capturé pendant cette période.',
          '❄️ Pion adverse figé pendant 2 tours — AVANT. Avant ton lancer, tu '
              'peux choisir un pion adverse. Ce pion est figé pendant 2 tours.',
          '🚫 Empêcher la sortie d\'un pion adverse — tu désignes un pion '
              'adverse. Lors du tour de son propriétaire, si ce pion est en '
              'position de sortir, il ne sort pas. Il doit continuer son '
              'parcours et refaire le tour avant de pouvoir ressortir selon '
              'les règles normales.',
        ]),

        _h('12. 🎲 Cartes différées — dés'),
        _p('Il existe 6 cartes de dés, avec des valeurs allant de 1 à 6. '
            'Lorsque tu en possèdes une, tu peux utiliser sa valeur à la place '
            'd\'un lancer de dé.'),
        _note('Cette carte se joue AVANT le lancer. La valeur de la carte '
            'devient alors la valeur utilisée pour ton déplacement.'),

        _h('13. ⚔️ Cartes différées — captures'),
        _sub('🏠 Retour du pion capturé — APRÈS'),
        _p('Lorsqu\'une carte de capture est utilisée selon cette règle, le '
            'pion capturé est placé dans la boîte de départ du joueur '
            'concerné.'),
        _p('Pour pouvoir ressortir, le joueur devra obtenir 6, conformément à '
            'la règle prévue pour la sortie de ses pions.'),

        _h('14. 👥 Cartes différées — joueurs'),
        _p('Certaines cartes peuvent agir directement sur les joueurs.'),
        _list([
          '👉 Le joueur à votre droite ne joue pas pendant 2 tours — AVANT. '
              'Le joueur situé à ta droite est privé de ses 2 prochains tours.',
          '🎯 Le joueur de votre choix ne joue pas pendant 2 tours — AVANT. '
              'Tu peux choisir n\'importe quel adversaire. Ce joueur ne joue '
              'pas pendant 2 tours.',
        ]),

        _h('15. 🧠 Stratégie'),
        _p('LudoPoly ne consiste donc pas uniquement à lancer le dé. Tu dois '
            'également réfléchir à la meilleure manière d\'utiliser tes '
            'cartes. Par exemple :'),
        _list([
          'Ton pion est sur le point d\'être capturé ? Utilise une carte '
              'd\'invulnérabilité.',
          'Un adversaire est sur le point de sortir un pion ? Utilise une '
              'carte pour le bloquer.',
          'Tu dois absolument obtenir une valeur précise ? Utilise une carte '
              'Dé.',
          'Un adversaire est très avancé ? Utilise une carte qui le fait '
              'reculer, le bloque ou affecte son tour.',
        ]),

        _h('16. 🔄 Résumé d\'un tour'),
        _list([
          '1️⃣ C\'est ton tour.',
          '2️⃣ Vérifie tes cartes différées — certaines doivent être '
              'utilisées avant le dé.',
          '3️⃣ Lance ton dé, ou utilise une carte Dé lorsque cela est '
              'autorisé.',
          '4️⃣ Choisis ton pion — le jeu te montre les déplacements possibles.',
          '5️⃣ Déplace ton pion.',
          '6️⃣ Une case spéciale est-elle atteinte ? 🍀 Chance → tirer ou '
              'utiliser la carte · ⭐ Étoile → appliquer la protection · '
              '🌀 Vortex → téléportation · ⚔️ Adversaire → capture selon les '
              'règles · 🏠 Maison → progression vers l\'arrivée.',
          '7️⃣ Vérifie les effets — une carte ou une règle peut modifier la '
              'situation.',
          '8️⃣ Le tour se termine. C\'est ensuite au joueur suivant de jouer.',
        ]),

        _h('17. 🏆 Comment gagner ?'),
        _p('Pour gagner, tu dois réussir à faire avancer tous tes pions '
            'jusqu\'à leur destination finale et les faire entrer dans ta '
            'maison.'),
        _p('Utilise intelligemment tes dés 🎲, tes cartes Chance 🃏, tes '
            'Vortex 🌀, les cases de protection ⭐, les captures ⚔️ et les '
            'cartes défensives 🛡️.'),
        _note('Le meilleur joueur n\'est pas forcément celui qui obtient les '
            'meilleurs dés. C\'est celui qui sait quand avancer, quand '
            'attaquer et quand utiliser ses cartes.'),

        const SizedBox(height: 18),
        const Center(
          child: Text('🎮 BIENVENUE DANS LUDOPOLY !',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _accent,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Lance les dés, déplace tes pions, utilise tes cartes, profite '
            'des Vortex et sois le premier à terminer ton parcours !',
            textAlign: TextAlign.center,
            style: TextStyle(color: _dim, fontSize: 13, height: 1.45),
          ),
        ),
      ],
    );
  }
}
