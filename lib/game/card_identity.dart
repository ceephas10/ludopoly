// L'IDENTITÉ VISUELLE d'une carte Chance : son pictogramme, son effet dit
// en trois mots, et sa couleur de famille.
//
// Le besoin : « il faut que chaque carte soit remarquée — quand je tombe
// sur une carte, je dois savoir tout de suite ce qu'elle fait ». Un code
// (`1`, `2`, `A`…) désigne une carte mais ne dit rien d'elle ; un nom
// complet se lit trop lentement sur un timbre-poste posé dans une base.
//
// D'où ce triplet, DÉDUIT de l'action et de la valeur de la carte — jamais
// saisi à la main. Une règle qui change dans `upgrades.dart` change donc
// l'étiquette du même coup : les deux ne peuvent pas diverger.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'upgrades.dart';

/// Les cinq familles d'effet, chacune avec sa couleur. C'est le premier
/// niveau de lecture : avant même de lire, la couleur dit le genre.
enum CardFamily {
  /// Le pion se déplace ou sort.
  motion(Color(0xFF34C759)),

  /// Le pion est protégé.
  guard(Color(0xFF2F9BE8)),

  /// L'adversaire est entravé.
  hinder(Color(0xFFE8453C)),

  /// On prend un pion adverse.
  capture(Color(0xFFF7941D)),

  /// Le dé lui-même est modifié.
  dice(Color(0xFF9B51E0));

  const CardFamily(this.color);
  final Color color;
}

/// Ce qui rend une carte reconnaissable d'un coup d'œil.
class CardIdentity {
  const CardIdentity({
    required this.family,
    required this.label,
    this.icon,
    this.dieValue,
  });

  final CardFamily family;

  /// L'effet en trois mots, en capitales — ce qu'on lit sur la carte.
  final String label;

  /// Le pictogramme, quand la carte n'est pas une carte-dé.
  final IconData? icon;

  /// Pour les cartes-dé : la face à dessiner. Rien ne dit « le dé jouera
  /// 2 » aussi vite qu'un dé montrant deux points.
  final int? dieValue;

  Color get color => family.color;
}

/// L'identité d'une carte, déduite de son action.
///
/// Le libellé est COURT — deux ou trois mots, souvent moins. Il se lit
/// sur une carte large d'une case, posée dans une base : « CAPTURE → MA
/// BOÎTE » y rentrait au chausse-pied et ne se lisait plus. Ce qui
/// identifie la carte n'est de toute façon pas ce texte mais son CODE,
/// la lettre ou le chiffre qui ne change jamais ; le libellé ne fait que
/// rappeler l'effet.
CardIdentity cardIdentity(ChanceCard c) {
  switch (c.action) {
    case CardAction.move:
      final n = c.value.abs();
      return c.value >= 0
          ? CardIdentity(
              family: CardFamily.motion,
              label: '+$n',
              icon: Icons.keyboard_double_arrow_right)
          : CardIdentity(
              family: CardFamily.motion,
              label: '−$n',
              icon: Icons.keyboard_double_arrow_left);

    case CardAction.teleport:
      return const CardIdentity(
          family: CardFamily.motion,
          label: 'AVANT SORTIE',
          icon: Icons.flag);

    case CardAction.releaseAll:
      return const CardIdentity(
          family: CardFamily.motion,
          label: 'TOUS DEHORS',
          icon: Icons.groups_2);

    case CardAction.returnToBase:
      return const CardIdentity(
          family: CardFamily.hinder,
          label: 'EN BOÎTE',
          icon: Icons.replay);

    case CardAction.setState:
      return c.pawnState == CardPawnState.invulnerable
          ? CardIdentity(
              family: CardFamily.guard,
              label: 'BOUCLIER ${c.value}T',
              icon: Icons.shield)
          : CardIdentity(
              family: CardFamily.hinder,
              label: 'FIGÉ ${c.value}T',
              icon: Icons.ac_unit);

    case CardAction.captureAhead:
      return const CardIdentity(
          family: CardFamily.capture,
          label: 'MANGE DEVANT',
          icon: Icons.my_location);

    case CardAction.captureBehind:
      return const CardIdentity(
          family: CardFamily.capture,
          label: 'MANGE DERRIÈRE',
          icon: Icons.undo);

    case CardAction.captureToBox:
      return const CardIdentity(
          family: CardFamily.capture,
          label: 'MANGÉ → BOÎTE',
          icon: Icons.inbox);

    case CardAction.modifyDice:
      switch (c.diceMode) {
        case CardDiceMode.limit:
          return CardIdentity(
              family: CardFamily.dice,
              label: 'DEMI-DÉ ${c.value}T',
              icon: Icons.exposure_neg_1);
        case CardDiceMode.double:
          return CardIdentity(
              family: CardFamily.dice,
              label: 'DOUBLE ${c.value}T',
              icon: Icons.exposure_plus_2);
        case CardDiceMode.twoDice:
          return CardIdentity(
              family: CardFamily.dice,
              label: '2 DÉS ${c.value}T',
              icon: Icons.filter_2);
        case null:
          return CardIdentity(
              family: CardFamily.dice,
              label: 'DÉ TRUQUÉ ${c.value}T',
              icon: Icons.casino);
      }

    case CardAction.setDice:
      // La carte-dé porte sa face, pas un pictogramme : « la carte qui
      // fait jouer 2 » se reconnaît au dé qui montre 2.
      return CardIdentity(
          family: CardFamily.dice, label: 'DÉ ${c.value}',
          dieValue: c.value);

    case CardAction.noExit:
      return const CardIdentity(
          family: CardFamily.hinder,
          label: 'NE SORT PAS',
          icon: Icons.block);

    case CardAction.skipTurn:
      return CardIdentity(
          family: CardFamily.hinder,
          label: 'SAUTE ${c.value}T',
          icon: Icons.timer_off);
  }
}

/// Le pictogramme d'une carte, à la taille demandée : une icône, ou une
/// face de dé si c'est une carte-dé.
class CardGlyph extends StatelessWidget {
  const CardGlyph({super.key, required this.card, this.size = 22, this.color});

  final ChanceCard card;
  final double size;

  /// Force la teinte. Par défaut, celle de la famille.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final id = cardIdentity(card);
    final tint = color ?? id.color;
    if (id.dieValue != null) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
            painter: MiniDieFace(value: id.dieValue!, color: tint)),
      );
    }
    return Icon(id.icon, size: size, color: tint);
  }
}

/// Une face de dé miniature, dessinée au vecteur : carré arrondi plein,
/// points évidés. Reste net du timbre-poste à la carte plein écran.
class MiniDieFace extends CustomPainter {
  const MiniDieFace({required this.value, required this.color});

  final int value;
  final Color color;

  /// Les points de chaque face, en coordonnées 0..1 sur la face.
  static const Map<int, List<Offset>> pips = {
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.28, 0.28), Offset(0.72, 0.72)],
    3: [Offset(0.26, 0.26), Offset(0.5, 0.5), Offset(0.74, 0.74)],
    4: [
      Offset(0.29, 0.29),
      Offset(0.71, 0.29),
      Offset(0.29, 0.71),
      Offset(0.71, 0.71)
    ],
    5: [
      Offset(0.27, 0.27),
      Offset(0.73, 0.27),
      Offset(0.5, 0.5),
      Offset(0.27, 0.73),
      Offset(0.73, 0.73)
    ],
    6: [
      Offset(0.28, 0.24),
      Offset(0.28, 0.5),
      Offset(0.28, 0.76),
      Offset(0.72, 0.24),
      Offset(0.72, 0.5),
      Offset(0.72, 0.76)
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH((size.width - u) / 2, (size.height - u) / 2, u, u),
        Radius.circular(u * 0.22));
    canvas.drawRRect(r, Paint()..color = color);
    final pipR = math.max(0.7, u * 0.095);
    final dot = Paint()..color = const Color(0xFF0A0A0A);
    for (final p in pips[value.clamp(1, 6)] ?? const <Offset>[]) {
      canvas.drawCircle(
          Offset(r.left + p.dx * u, r.top + p.dy * u), pipR, dot);
    }
  }

  @override
  bool shouldRepaint(covariant MiniDieFace old) =>
      old.value != value || old.color != color;
}
