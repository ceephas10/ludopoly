// Le tableau de bord : la première chose qu'on voit en ouvrant LudoPoly.
//
// Rien à régler ici. Le logo respire en haut, les entrées se rangent en
// dessous, et le décor se voit à travers — les pavés sont translucides et
// posés sur du verre dépoli, pas des rectangles opaques collés par-dessus.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'game/app_background.dart';
import 'game/background_config.dart';
import 'game/brand.dart';
import 'game/menu_music.dart';

/// Ce que le menu peut lancer.
enum MenuChoice {
  /// Le plateau seul : on joue, rien d'autre.
  play,

  /// Le panneau seul : centre de commandes, règles, paramètres.
  system,

  /// La règle du jeu, sur sa propre page.
  howToPlay,

  /// L'écran de réglages de la partie.
  options,
}

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
      body: AppBackground.menu.wrap(
        config: background,
        SafeArea(
          child: Stack(
            children: [
              _musique(),
              LayoutBuilder(
            builder: (context, c) {
              // Sur un écran court, le logo se fait discret pour laisser la
              // place aux entrées ; sur un grand, il prend ses aises.
              final tall = c.maxHeight > 640;
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LudoPolyLogo(scale: tall ? 1.0 : 0.78),
                        SizedBox(height: tall ? 44 : 30),
                        _MenuTile(
                          key: const Key('menu-play'),
                          icon: Icons.play_arrow_rounded,
                          title: 'Jouer',
                          subtitle: 'Le plateau, et rien d\'autre',
                          primary: true,
                          onTap: () => onChoose(MenuChoice.play),
                        ),
                        _MenuTile(
                          key: const Key('menu-how'),
                          icon: Icons.menu_book_rounded,
                          title: 'Comment jouer',
                          subtitle: 'La règle du jeu, expliquée',
                          onTap: () => onChoose(MenuChoice.howToPlay),
                        ),
                        _MenuTile(
                          key: const Key('menu-options'),
                          icon: Icons.tune_rounded,
                          title: 'Options',
                          subtitle: 'Joueurs, ordinateur, arrière-plan',
                          onTap: () => onChoose(MenuChoice.options),
                        ),
                        _MenuTile(
                          key: const Key('menu-system'),
                          icon: Icons.terminal_rounded,
                          title: 'Système',
                          subtitle: 'Centre de commandes et paramètres',
                          onTap: () => onChoose(MenuChoice.system),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// LE BOUTON DE LA MUSIQUE, en haut à droite de l'accueil.
  ///
  /// Un interrupteur, pas un aller simple : couper la musique sans pouvoir
  /// la remettre serait une impasse. L'icône dit l'état, pas l'action —
  /// haut-parleur barré quand c'est coupé.
  Widget _musique() {
    return Positioned(
      top: 8,
      right: 8,
      child: ValueListenableBuilder<bool>(
        valueListenable: MenuMusic.instance.wanted,
        builder: (context, on, _) => Tooltip(
          message: on ? 'Couper la musique' : 'Remettre la musique',
          child: Material(
            key: const Key('menu-music'),
            color: Colors.white.withValues(alpha: on ? 0.14 : 0.06),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => MenuMusic.instance.setWanted(!on),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  size: 22,
                  color: Colors.white.withValues(alpha: on ? 0.92 : 0.55),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une entrée du menu : une icône, un titre, une ligne d'explication, un
/// chevron. Le tout sur du verre dépoli, pour que le décor reste visible.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// L'entrée mise en avant : celle qu'on vient chercher neuf fois sur dix.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? const Color(0xFF3A2B00) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          // Le flou derrière le pavé : le décor transparaît sans rendre le
          // texte illisible. C'est ce qui « marie » les boutons au fond au
          // lieu de les poser dessus.
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: primary
                ? BgPalette.amber
                : Colors.white.withValues(alpha: 0.10),
            child: InkWell(
              onTap: onTap,
              splashColor: BgPalette.cyan.withValues(alpha: 0.2),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primary
                        ? const Color(0xFFFFE49A)
                        : Colors.white.withValues(alpha: 0.22),
                    width: primary ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: primary
                            ? const Color(0x33000000)
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 21, color: fg),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                color: fg,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              )),
                          const SizedBox(height: 1),
                          Text(subtitle,
                              style: TextStyle(
                                color: fg.withValues(alpha: 0.72),
                                fontSize: 12,
                              )),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 22, color: fg.withValues(alpha: 0.6)),
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
