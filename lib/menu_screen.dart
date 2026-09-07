// Le tableau de bord : la première chose qu'on voit en ouvrant LudoPoly.
//
// Rien à régler ici. Quatre entrées, la principale en évidence, et l'on
// part jouer. Les réglages existent toujours — ils sont derrière
// « Options », pas sur le chemin de celui qui veut simplement jouer.

import 'package:flutter/material.dart';

import 'game/app_background.dart';
import 'game/background_config.dart';

/// Ce que le menu peut lancer.
enum MenuChoice {
  /// Le plateau seul, sans le panneau : on joue, rien d'autre.
  play,

  /// Le plateau ET le centre de commandes, comme l'écran de travail.
  system,

  /// Le plateau, panneau ouvert sur la page des règles.
  howToPlay,

  /// L'écran de réglages de la partie.
  options,
}

// Les couleurs du menu sont celles du décor : le bleu saphir de la spec,
// l'ambre pour l'entrée principale, le cyan pour le titre.
const Color _tile = BgPalette.tile;
const Color _accent = BgPalette.amber;
const Color _mint = BgPalette.cyan;

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.onChoose,
    this.background = const BackgroundConfig(),
  });

  final ValueChanged<MenuChoice> onChoose;

  /// Le décor choisi dans Options : le menu le porte aussi.
  final BackgroundConfig background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Même décor que le plateau : image du Studio si elle existe,
      // dégradé sinon.
      body: AppBackground.menu.wrap(
        config: background,
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 34),
                    _MenuTile(
                      key: const Key('menu-play'),
                      title: 'Jouer',
                      subtitle: 'Le plateau, et rien d\'autre',
                      primary: true,
                      onTap: () => onChoose(MenuChoice.play),
                    ),
                    _MenuTile(
                      key: const Key('menu-system'),
                      title: 'Système',
                      subtitle: 'Plateau à gauche, paramètres à droite',
                      onTap: () => onChoose(MenuChoice.system),
                    ),
                    _MenuTile(
                      key: const Key('menu-how'),
                      title: 'Comment jouer',
                      subtitle: 'La règle du jeu, expliquée',
                      onTap: () => onChoose(MenuChoice.howToPlay),
                    ),
                    _MenuTile(
                      key: const Key('menu-options'),
                      title: 'Options',
                      subtitle: 'Joueurs, ordinateur, cases spéciales',
                      onTap: () => onChoose(MenuChoice.options),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le titre et sa devise.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _tile.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _mint.withValues(alpha: 0.6)),
          ),
          child: const Icon(Icons.casino, color: _accent, size: 26),
        ),
        const SizedBox(height: 14),
        const Text(
          'LUDOPOLY',
          style: TextStyle(
            color: _mint,
            fontSize: 46,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'TOUT SE JOUE JUSQU\'AU DERNIER PION',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 11,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Une entrée du menu : un grand pavé, un titre, une ligne d'explication.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// L'entrée mise en avant : celle qu'on vient chercher neuf fois sur dix.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? _accent : _tile;
    final fg = primary ? const Color(0xFF3A2B00) : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Material(
        // Les pavés secondaires laissent voir le décor : opaques, ils
        // faisaient quatre rectangles morts sur un fond travaillé.
        color: primary ? bg : bg.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        elevation: primary ? 6 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: primary
                    ? const Color(0xFFF6D97A)
                    : _mint.withValues(alpha: 0.22),
                width: primary ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(title,
                    style: TextStyle(
                      color: fg,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontSize: 12,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
