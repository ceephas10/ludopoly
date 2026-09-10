// LA MUSIQUE DU MENU.
//
// Elle vit HORS du plateau : elle tourne sur l'accueil, sur « Comment
// jouer » et sur « Options », et elle s'éteint dès qu'on entre sur le
// plateau. Le jeu a ses propres sons — le dé, les pas, le cri — et une
// musique par-dessus les couvrirait.
//
// Un seul exemplaire pour toute l'application : les écrans vont et
// viennent, la musique ne doit pas repartir du début à chaque fois.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class MenuMusic {
  MenuMusic._();
  static final MenuMusic instance = MenuMusic._();

  /// `audioplayers` préfixe tout seul par `assets/`.
  static const String _asset = 'audio/menu_music.mp3';

  /// Assez présente pour qu'on l'entende, assez basse pour qu'elle reste
  /// un fond. Elle n'a personne à couvrir sur le menu, mais elle ne doit
  /// pas non plus faire sursauter à l'ouverture.
  static const double _level = 0.5;

  /// La descente avant l'extinction, quand on entre sur le plateau.
  static const Duration _fade = Duration(milliseconds: 500);

  /// Coupée dans les tests : le harnais n'a pas de greffon audio, et
  /// construire un lecteur y lève une erreur asynchrone qu'aucun `try` ne
  /// rattrape.
  static bool muted = false;

  /// L'utilisateur veut-il de la musique ? C'est le bouton du menu qui
  /// écrit ici, et le bouton lui-même qui écoute — d'où le notificateur.
  final ValueNotifier<bool> wanted = ValueNotifier<bool>(true);

  /// SOMMES-NOUS SUR LE PLATEAU ? Si oui, la musique se tait, un point.
  ///
  /// Sans ce verrou, [nudge] la relançait : il est appelé au moindre
  /// contact avec l'écran, et sur le plateau on touche sans arrêt — le dé,
  /// les pions, les cartes. La musique repartait donc au premier geste de
  /// la partie, juste après s'être éteinte.
  ///
  /// Le fondu d'extinction ne suffisait pas : une fois terminé, plus rien
  /// ne distinguait « on vient de sortir du menu » de « on est sur
  /// l'accueil, silencieux ».
  bool _surLePlateau = false;

  /// LA MUSIQUE DEVRAIT-ELLE JOUER EN CET INSTANT ?
  ///
  /// C'est la décision, pas son exécution : elle ne dépend ni du greffon
  /// audio ni du bon vouloir du navigateur. Deux conditions, et deux
  /// seulement — le joueur en veut, et l'on n'est pas sur le plateau.
  bool get devraitJouer => wanted.value && !_surLePlateau;

  /// À appeler en entrant sur le plateau et en le quittant. L'entrée
  /// éteint la musique ; la sortie la rend au menu, sauf si le joueur l'a
  /// coupée avec le bouton.
  void surLePlateau(bool oui) {
    if (_surLePlateau == oui) return;
    _surLePlateau = oui;
    if (oui) {
      fadeOutAndStop();
    } else {
      play();
    }
  }

  AudioPlayer? _player;
  Timer? _fadeTimer;
  bool _dead = false;

  /// Lance la musique, ou la reprend. Sans effet si elle tourne déjà, ou
  /// si l'utilisateur l'a coupée.
  Future<void> play() async {
    if (muted || _dead || !devraitJouer) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    try {
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(_level);
      // `resume` sur un lecteur qui n'a pas de source ne fait rien : on
      // pose la source la première fois, et seulement la première.
      if (p.source == null) {
        await p.play(AssetSource(_asset), volume: _level);
      } else if (p.state != PlayerState.playing) {
        await p.seek(Duration.zero);
        await p.resume();
      }
    } catch (e) {
      // PAS de condamnation ici. Le navigateur REFUSE de jouer un son
      // avant le premier geste de l'utilisateur : l'ouverture de la page
      // tombe donc systématiquement dans ce `catch`. C'était le bug —
      // la musique ne partait qu'après avoir touché le bouton, qui est
      // justement un geste.
      //
      // On garde donc l'envie, et [nudge] réessaiera au premier contact.
      if (!_grumbled) {
        _grumbled = true;
        debugPrint('[musique] pas encore autorisée ($e) — on réessaiera '
            'au premier geste');
      }
    }
  }

  /// On ne se plaint qu'une fois : le refus se répète à chaque tentative.
  bool _grumbled = false;

  /// À appeler au PREMIER GESTE de l'utilisateur, où qu'il touche.
  ///
  /// C'est la règle des navigateurs : rien ne sonne avant qu'on ait
  /// touché la page. Sans ce rattrapage, la musique de l'accueil ne
  /// démarrait jamais — sauf en touchant son propre bouton.
  void nudge() {
    if (muted || _dead || !devraitJouer) return;
    if (_player?.state == PlayerState.playing) return;
    if (_fadeTimer != null) return; // on est en train de s'éteindre
    play();
  }

  /// Baisse le son PROGRESSIVEMENT puis coupe. C'est la demande : en
  /// entrant sur le plateau la musique décroît, elle ne s'arrête pas net.
  void fadeOutAndStop({Duration over = _fade}) {
    if (muted || _dead) return;
    final p = _player;
    if (p == null) return;
    _fadeTimer?.cancel();
    // Vingt paliers : assez fin pour qu'on entende une descente et non un
    // escalier, assez grossier pour ne pas noyer la frame.
    const paliers = 20;
    final pas = Duration(
        microseconds: (over.inMicroseconds / paliers).round().clamp(1, 1 << 30));
    var reste = paliers;
    _fadeTimer = Timer.periodic(pas, (t) async {
      reste--;
      try {
        if (reste <= 0) {
          t.cancel();
          _fadeTimer = null;
          await p.stop();
          await p.setVolume(_level); // prête pour la prochaine fois
        } else {
          await p.setVolume(_level * reste / paliers);
        }
      } catch (_) {
        t.cancel();
        _fadeTimer = null;
      }
    });
  }

  /// Le bouton du menu. `false` coupe tout de suite ; `true` relance.
  void setWanted(bool v) {
    wanted.value = v;
    if (v) {
      play();
    } else {
      // Coupure NETTE : on vient d'appuyer sur stop, on n'attend pas une
      // demi-seconde pour être obéi.
      _fadeTimer?.cancel();
      _fadeTimer = null;
      _player?.stop();
    }
  }

  @visibleForTesting
  void disposeForTest() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _player?.dispose();
    _player = null;
    _dead = false;
    _surLePlateau = false;
    wanted.value = true;
  }
}
