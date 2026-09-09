// LudoPoly — Step 1: static board with 4 players at starting positions
// rendered from the GameState model, with a debug overlay for the 52-cell ring.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show rootBundle, HapticFeedback;
import 'game/ai_difficulty.dart';
import 'game/board_painter.dart';
import 'game/menu_music.dart';
import 'game/board_painter_5p.dart';
import 'game/app_background.dart';
import 'game/board_path.dart';
import 'game/brand.dart';
import 'game/card_art.dart';
import 'game/card_identity.dart';
import 'game/game_controller.dart';
import 'game/game_setup.dart';
import 'game/game_state.dart';
import 'game/pawn.dart';
import 'game/player_color.dart';
import 'how_to_play_screen.dart';
import 'menu_screen.dart';
import 'setup_screen.dart';
import 'game/upgrades.dart';
export 'game/player_color.dart';

void main() => runApp(const LudoPolyApp());

class LudoPolyApp extends StatefulWidget {
  const LudoPolyApp({super.key});

  @override
  State<LudoPolyApp> createState() => _LudoPolyAppState();
}

class _LudoPolyAppState extends State<LudoPolyApp> {
  @override
  void initState() {
    super.initState();
    // La musique commence avec l'accueil, avant tout choix.
    MenuMusic.instance.play();
  }

  /// Ce que l'on regarde : le menu, les réglages, ou une partie.
  MenuChoice? _screen;

  /// Les réglages de la partie. Ils SURVIVENT au retour au menu : on règle
  /// une fois dans Options, puis on joue autant qu'on veut.
  GameSetup _setup = const GameSetup();

  /// Chaque départ de partie change cette clé, donc reconstruit un plateau
  /// NEUF. Sans elle, revenir au menu puis rejouer reprendrait la partie
  /// précédente là où elle en était.
  int _game = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPoly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      // LE PREMIER GESTE, où qu'il tombe, réveille la musique.
      //
      // Les navigateurs interdisent tout son avant que l'utilisateur
      // n'ait touché la page. La musique de l'accueil ne partait donc
      // jamais — sauf en touchant son propre bouton, qui est un geste :
      // d'où « ça ne marche qu'en coupant puis remettant le son ».
      home: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => MenuMusic.instance.nudge(),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    switch (_screen) {
      case null:
        return MenuScreen(background: _setup.background, onChoose: (c) {
          // ON ENTRE SUR LE PLATEAU : la musique DESCEND puis s'éteint.
          // Ailleurs — Options, Comment jouer — on n'est pas encore dans
          // la partie : elle continue.
          if (c == MenuChoice.play || c == MenuChoice.system) {
            MenuMusic.instance.fadeOutAndStop();
          }
          setState(() {
            _screen = c;
            if (c != MenuChoice.options) _game++;
          });
        });

      case MenuChoice.options:
        return SetupScreen(
          onStart: (s) => setState(() {
            _setup = s;
            _screen = null; // réglé : on revient au menu
          }),
        );

      // « Comment jouer » : la règle du jeu, sur sa propre page. Pas de
      // plateau — on vient y comprendre, pas y jouer.
      case MenuChoice.howToPlay:
        return HowToPlayScreen(
          background: _setup.background,
          onExit: () => setState(() => _screen = null),
        );

      // « Jouer » : le plateau seul. « Système » : le plateau ET le
      // panneau, avec le chevron pour replier ce dernier sur le côté.
      case MenuChoice.play:
      case MenuChoice.system:
        return BoardScreen(
          key: ValueKey(_game),
          setup: _setup,
          // « Jouer » : aucun panneau, aucun chevron. Le joueur ne doit
          // même pas apercevoir la page des paramètres.
          showPanel: _screen != MenuChoice.play,
          // « Système » montre les deux : on règle en voyant l'effet sur
          // le plateau, et le chevron replie le panneau quand on veut le
          // plateau en grand.
          showBoard: true,
          initialPanelTab: 'commandes',
          // Les réglages changés dans le panneau reviennent ici : ils
          // s'appliquent donc aux écrans suivants, « Comment jouer »
          // compris.
          onExit: (s) => setState(() {
            _setup = s;
            _screen = null;
            // De retour à l'accueil : la musique reprend, sauf si le
            // joueur l'a coupée avec le bouton.
            MenuMusic.instance.play();
          }),
        );
    }
  }
}

/// Minuterie qui sait se METTRE EN PAUSE et repartir avec le temps qui lui
/// restait — pas depuis zéro.
///
/// C'est toute la difficulté du bouton Pause : si l'ordinateur avait déjà
/// « réfléchi » 700 ms de ses 900, la reprise ne doit lui en laisser que
/// 200. Une simple annulation suivie d'un rearmement ferait repartir le
/// délai entier, et l'on verrait le jeu hésiter à chaque reprise.
///
/// Elle implémente [Timer] : tout le code qui stocke des `Timer?` ou des
/// `Map<Pawn, Timer>` et appelle `.cancel()` / `.isActive` continue de
/// fonctionner sans une ligne de changement.
class PausableTimer implements Timer {
  PausableTimer(this._duration, this._onFire, {bool periodic = false})
      : _periodic = periodic {
    _arm(_duration);
  }

  final Duration _duration;
  final void Function() _onFire;
  final bool _periodic;

  Timer? _inner;
  final Stopwatch _watch = Stopwatch();
  Duration _remaining = Duration.zero;
  bool _cancelled = false;
  int _ticks = 0;

  /// Vrai quand la minuterie est gelée : elle attend, mais son compte à
  /// rebours ne court plus.
  bool get isPaused => !_cancelled && _inner == null;

  void _arm(Duration d) {
    _remaining = d;
    _watch
      ..reset()
      ..start();
    _inner = Timer(d, () {
      _ticks++;
      if (_periodic) {
        _onFire();
        // Le premier intervalle a pu être RACCOURCI par une reprise ;
        // les suivants reprennent la cadence pleine.
        if (!_cancelled) _armPeriodic();
      } else {
        _watch.stop();
        _onFire();
      }
    });
  }

  void _armPeriodic() {
    _remaining = _duration;
    _watch
      ..reset()
      ..start();
    _inner = Timer.periodic(_duration, (_) {
      _ticks++;
      _watch
        ..reset()
        ..start();
      _onFire();
    });
  }

  /// Gèle la minuterie en retenant ce qu'il lui restait à courir.
  void pause() {
    if (_cancelled || _inner == null) return;
    _watch.stop();
    final left = _remaining - _watch.elapsed;
    _remaining = left.isNegative ? Duration.zero : left;
    _inner!.cancel();
    _inner = null;
  }

  /// Repart pour le temps restant seulement.
  void resume() {
    if (_cancelled || _inner != null) return;
    _arm(_remaining);
  }

  @override
  void cancel() {
    _cancelled = true;
    _inner?.cancel();
    _inner = null;
    _watch.stop();
  }

  /// Une minuterie en pause reste ACTIVE : elle est en attente, pas morte.
  /// Le watchdog s'appuie là-dessus pour ne pas la croire perdue.
  @override
  bool get isActive => !_cancelled && (_inner?.isActive ?? true);

  @override
  int get tick => _ticks;
}

class Player {
  final String name;
  final PlayerColor color;
  const Player(this.name, this.color);
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    this.setup = const GameSetup(),
    this.showPanel = true,
    this.showBoard = true,
    this.initialPanelTab = 'commandes',
    this.onExit,
  });

  /// Les choix faits sur l'écran de réglages. Appliqués une fois, au
  /// démarrage. La valeur par défaut sert aux usages directs du plateau.
  final GameSetup setup;

  /// Le centre de commandes existe-t-il seulement ? « Jouer » le retire
  /// ENTIÈREMENT — ni panneau, ni chevron, aucun moyen de l'ouvrir : cet
  /// écran s'adresse au joueur, pas à celui qui règle le jeu.
  final bool showPanel;

  /// L'onglet du panneau à l'ouverture : `commandes`, `rules` ou
  /// `settings`.
  final String initialPanelTab;

  /// Le plateau est-il affiché ? « Système » ne montre QUE le panneau :
  /// centre de commandes, règles du jeu, paramètres.
  final bool showBoard;

  /// Retour au menu. Reçoit les réglages TELS QU'ILS SONT à cet instant :
  /// ce qu'on a changé dans le panneau survit donc au retour et s'applique
  /// aux écrans suivants. `null` = pas de bouton de retour.
  final ValueChanged<GameSetup>? onExit;

  static const players = <Player>[
    Player('Player 1', PlayerColor.blue),
    Player('Player 2', PlayerColor.red),
    Player('Player 3', PlayerColor.green),
    Player('Player 4', PlayerColor.yellow),
  ];

  @override
  State<BoardScreen> createState() => BoardScreenState();
}

/// État de l'écran de jeu. PUBLIC pour que les tests puissent piloter une
/// partie complète à travers la vraie interface — c'est la convention
/// Flutter (`ScaffoldState`, `FormState`).
class BoardScreenState extends State<BoardScreen>
    with TickerProviderStateMixin {
  final GameState _game = GameState.initial();

  /// Moteur de la partie. Exposé aux tests pour qu'ils puissent observer
  /// l'avancement d'une partie jouée via l'interface réelle.
  @visibleForTesting
  GameController get controller => _controller;

  /// Sièges IA, exposés aux tests pour éviter de dépendre des libellés du
  /// panneau. [aiOpponents] garde la sémantique historique « 1 humain +
  /// 3 IA » qu'utilisent les tests existants.
  @visibleForTesting
  Set<PlayerColor> get aiSeats => Set.unmodifiable(_aiSeats);

  @visibleForTesting
  void setAiSeats(Set<PlayerColor> seats) {
    _aiTimer?.cancel();
    setState(() => _aiSeats
      ..clear()
      ..addAll(seats));
    _scheduleAiTurn();
  }

  @visibleForTesting
  bool get aiOpponents => _aiSeats.isNotEmpty;

  /// Mode Accélérateur et niveau de l'ordinateur, exposés aux tests pour
  /// qu'ils vérifient le câblage sans dépendre des libellés du panneau.
  @visibleForTesting
  bool get aiTurbo => _aiTurbo;

  @visibleForTesting
  set aiTurbo(bool v) => setState(() => _aiTurbo = v);

  @visibleForTesting
  AiDifficulty get aiDifficulty => _controller.aiDifficulty;

  /// Le délai [d] tel qu'il sera RÉELLEMENT armé, mode Accélérateur
  /// compris. C'est le seul moyen d'observer l'accélération : les durées
  /// sont consommées par des minuteries, pas stockées.
  @visibleForTesting
  Duration paceForTest(Duration d, {bool? ai}) => _pace(d, ai: ai);

  @visibleForTesting
  PlayerColor get currentColor => _controller.currentColor;

  /// Les deux durées de la passation de main, exposées aux tests : elles
  /// portent un invariant qu'un réglage distrait casserait en silence.
  @visibleForTesting
  static Duration get diceReadHoldForTest => _diceReadHold;

  @visibleForTesting
  static Duration get aiRollDelayForTest => _aiRollDelay;

  @visibleForTesting
  set aiOpponents(bool v) => setAiSeats(
      v ? _controller.turnOrder.skip(1).toSet() : const {});
  late final GameController _controller = GameController(
    turnOrder: BoardScreen.players.map((p) => p.color).toList(),
    state: _game,
  );
  bool _showRing = false;
  bool _showGrid = false;
  /// Debug overlay: draw a red rectangle around every pawn GIF bbox to
  /// visualize their rendered footprint (`pawnWidth × pawnHeight`).
  bool _showCanvas = false;
  bool _showDetails = false;
  int _playerCount = 4;
  bool _assetsReady = false;
  /// Live status string shown on the loading screen — updated as `_bootstrap`
  /// probes the token assets so the user can see which file is loading /
  /// missing instead of staring at a blank "Loading tokens…".
  String _loadingStatus = 'Démarrage…';
  /// Per-color available idle-variant indices (e.g. `{blue: [1, 2]}`).
  /// Populated by `_bootstrap` after probing the asset bundle. Kept for
  /// future use (5/6-player extensions, runtime swap, debug overlay).
  // ignore: unused_field
  Map<PlayerColor, List<int>> _availableVariants = const {};

  /// Optional override of the board's logical width. When null the board
  /// fills the available room. Buttons in the command center set this to
  /// device preset sizes for testing different aspect ratios.
  double? _boardWidthOverride;

  /// Le centre de commandes est-il replié sur le côté ? Le chevron posé
  /// entre le plateau et le panneau bascule cet état ; replié, toute la
  /// largeur revient au plateau.
  bool _panelCollapsed = false;

  /// Manual-mode selection: which color to play next and which dice value
  /// to force. Independent of the controller's natural turn rotation.
  PlayerColor _manualPlayer = PlayerColor.blue;
  int _manualValue = 1;

  /// Right-panel tab. `'commandes'` = Centre de commandes (default),
  /// `'rules'` = Règles du jeu, `'settings'` = Settings.
  String _panelTab = 'commandes';

  /// Game rules state. **In-memory for now** — persistence across app
  /// reloads is TODO (was attempted with shared_preferences but hits a
  /// Flutter web path-resolution bug that maps `..\..\AppData\...` to a
  /// non-existent location). Default values match "classic" Ludo.
  bool _ruleStartWith1TokenOut = false;
  bool _ruleTeamMode = false;

  /// Sièges pilotés par l'IA locale. Chaque place de la partie peut être
  /// Humain ou IA, indépendamment des autres : toutes les combinaisons de
  /// 4 H + 0 IA à 0 H + 4 IA sont donc possibles — y compris la partie
  /// 100 % automatique, qui se déroule seule jusqu'au classement complet.
  final Set<PlayerColor> _aiSeats = {};

  /// Pause générale du plateau. Rien ne bouge, rien ne se lance, aucune
  /// minuterie ne court : voir [setPaused].
  bool _paused = false;

  @visibleForTesting
  bool get paused => _paused;

  /// Déclenche le lancer du joueur, comme un clic sur le dé. Les tests
  /// s'en servent pour vérifier que la pause rend la commande INERTE.
  @visibleForTesting
  void rollDiceForTest() => _rollDiceRandom();

  /// Force une valeur de dé, comme le fait la carte Jeu manuel. Les tests
  /// s'en servent pour provoquer un coup à option unique.
  @visibleForTesting
  void rollManualForTest(int value) => _roll(value);

  /// La couleur sélectionnée dans « Jeu manuel » — celle que visent aussi
  /// les cartes appliquées à la main.
  @visibleForTesting
  PlayerColor get manualPlayerForTest => _manualPlayer;

  /// Toutes les minuteries du JEU. Elles sont gelées d'un bloc à la pause
  /// et repartent avec leur temps restant à la reprise.
  final Set<PausableTimer> _timers = {};

  /// Arme une minuterie unique, inscrite au registre de la pause.
  Timer _after(Duration d, void Function() cb) {
    final t = PausableTimer(d, cb);
    _timers.add(t);
    if (_paused) t.pause(); // née pendant la pause : elle naît gelée
    return t;
  }

  /// Arme une minuterie répétée, inscrite au registre de la pause.
  Timer _every(Duration d, void Function() cb) {
    final t = PausableTimer(d, cb, periodic: true);
    _timers.add(t);
    if (_paused) t.pause();
    return t;
  }

  /// Met le plateau en pause, ou le relance.
  ///
  /// À la pause : chaque minuterie retient le temps qui lui RESTAIT, et
  /// l'état logique n'est pas touché — aucun tour n'est sauté, aucune
  /// action n'est rejouée. Un pion à mi-parcours reste figé sur la case
  /// qu'il avait atteinte, et son trajet reprend à cette case.
  void setPaused(bool value) {
    if (_paused == value) return;
    setState(() {
      _paused = value;
      _timers.removeWhere((t) => !t.isActive); // purge des minuteries mortes
      for (final t in _timers) {
        value ? t.pause() : t.resume();
      }
    });
    debugPrint(value ? '[pause] plateau gelé' : '[pause] reprise');
  }

  /// Mode Rapide — sans attente de tour. Chaque couleur d'ordinateur mène
  /// SON tour en continu, en parallèle des autres, pendant que l'humain
  /// réfléchit. Voir [GameController.fastMode] pour le versant règles.
  bool _ruleFastMode = false;

  /// Couleurs dont un coup est en cours d'animation.
  ///
  /// En mode ordinaire le verrou reste GLOBAL ([_animating]) : une seule
  /// commande à la fois, comme depuis toujours. En mode Rapide il devient
  /// PAR COULEUR — c'est précisément ce qui autorise plusieurs pions à
  /// glisser en même temps.
  final Set<PlayerColor> _busySeats = {};

  /// Minuteries du mode Rapide, une par couleur d'ordinateur. Chacune mène
  /// son tour sans rien savoir des autres.
  final Map<PlayerColor, Timer> _fastTimers = {};

  /// Bascule le mode Rapide. Prend effet immédiatement, y compris en pleine
  /// partie : on coupe tout ce qui est en vol, on remet les sièges à plat,
  /// puis on redémarre la boucle qui correspond au nouveau mode.
  void setFastMode(bool on) {
    setState(() {
      _cancelAnimations();
      _ruleFastMode = on;
      _controller.fastMode = on;
      _controller.resetSeats();
      if (on) {
        // Chaque siège repart d'un tour propre, dé compris.
        _controller.diceValue = 0;
        _controller.phase = _controller.phase == TurnPhase.gameOver
            ? TurnPhase.gameOver
            : TurnPhase.rolling;
      }
      _syncManualPlayer();
    });
    if (on) {
      _startFastLoops();
    } else {
      _scheduleAiTurn();
    }
  }

  /// Améliorations LudoPoly — interrupteurs des cases Vortex et Chance.
  /// Basculables en pleine partie : les cases se dessinent (ou s'effacent)
  /// immédiatement, et les effets ne s'appliquent qu'aux atterrissages
  /// suivants. Les effets DÉJÀ posés (invulnérable, dé modifié…) vont au
  /// bout de leur durée même si l'on éteint.
  void setVortexEnabled(bool on) =>
      setState(() => _controller.upgrades.vortexEnabled = on);

  void setChanceEnabled(bool on) =>
      setState(() => _controller.upgrades.chanceEnabled = on);

  /// Joue une carte différée pour le joueur courant. Une carte-dé remplace
  /// le lancer : on enchaîne alors sur le tour normal avec sa valeur, ce
  /// qui fait passer le coup par le moteur comme n'importe quel lancer.
  @visibleForTesting
  void playDeferredCard(ChanceCard card,
      {Pawn? targetPawn, PlayerColor? targetPlayer}) {
    if (_paused) return;
    final me = _deferredSeat;
    if (_lockedFor(me)) return;
    final forced = _controller.playDeferredCard(me, card,
        targetPawn: targetPawn, targetPlayer: targetPlayer);
    setState(() {
      final notices = _controller.upgrades.takeNotices();
      for (final n in notices) {
        debugPrint('[amélioration] $n');
      }
      if (notices.isNotEmpty) _autoNotice = notices.join('\n');
    });
    if (forced != null) _roll(forced);
  }

  /// Le verrou qui s'applique à [c].
  bool _lockedFor(PlayerColor c) =>
      _ruleFastMode ? _busySeats.contains(c) : _animating;

  /// Vrai dès qu'une animation est en vol, quelle que soit la couleur.
  /// C'est ce que regardent les commandes GLOBALES — Retour, Rejouer, fin
  /// de tour — qui ne doivent pas s'exécuter au milieu d'un coup.
  bool get _anyBusy => _animating || _busySeats.isNotEmpty;

  /// Mode Accélérateur : divise par [_turboFactor] toutes les temporisations
  /// d'un tour d'ORDINATEUR. Jamais celles d'un tour humain — un joueur doit
  /// garder le temps de lire le dé et de suivre son pion.
  bool _aiTurbo = false;

  /// Diviseur du mode Accélérateur. 2 : deux fois plus rapide, pas
  /// instantané — on doit continuer à VOIR l'ordinateur jouer.
  static const int _turboFactor = 2;

  /// Applique le mode Accélérateur à [d] si le tour en cours est celui d'un
  /// ordinateur. Passe [ai] explicitement quand la couleur concernée n'est
  /// plus celle du tour courant (le moteur a pu passer la main entre-temps).
  Duration _pace(Duration d, {bool? ai}) {
    final isAi = ai ?? _isAiColor(_controller.currentColor);
    if (!_aiTurbo || !isAi) return d;
    return Duration(microseconds: d.inMicroseconds ~/ _turboFactor);
  }

  /// Verrou anti-bug. Vrai pendant qu'un pion glisse : tant qu'il est levé,
  /// AUCUNE commande n'est acceptée (double clic sur un pion, relance du dé,
  /// fin de tour, changement de joueur). Le moteur a déjà appliqué le coup
  /// quand l'animation démarre — le verrou empêche juste d'en empiler un
  /// deuxième par-dessus.
  bool _animating = false;

  /// Timer du coup joué par l'IA, annulé à chaque reset/redémarrage pour
  /// éviter qu'un coup programmé n'arrive sur une partie déjà réinitialisée.
  Timer? _aiTimer;

  /// Contrôle périodique qui relance l'IA si un chemin a oublié de le
  /// faire — voir [_startAiWatchdog].
  Timer? _aiWatchdog;

  /// Per-pawn slide duration tracked for the LAST move. Read by the
  /// AnimatedPositioned wrapping each pawn in BoardView — that widget
  /// interpolates left/top smoothly when the pawn's cell changes between
  /// rebuilds. Only the moving pawn's Positioned animates; the rest of
  /// the board does NOT rebuild during the slide.
  final Map<Pawn, Duration> _moveDuration = {};
  /// Active explosions on the board (capture markers). Each carries its
  /// own AnimationController; popped from the list when done.
  final List<ExplosionFx> _explosions = [];

  /// Durée du glissement d'UNE case à la suivante. Le pion s'arrête
  /// visiblement sur chaque case du trajet : un 6 prend donc 6 × cette
  /// durée. Assez lent pour qu'on suive le pion case par case.
  static const Duration _stepDuration = Duration(milliseconds: 190);

  /// Sortie de base : le pion est téléporté du bac à sa case départ, ce
  /// n'est pas un parcours — un saut court suffit.
  /// La SORTIE DE BASE. Plus long qu'un pas ordinaire, et volontairement :
  /// c'est le seul moment où un pion quitte sa boîte pour entrer en jeu,
  /// et il traverse une grande diagonale pour y arriver. Expédié en 220 ms
  /// il téléportait ; en 480 ms il se déplace.
  static const Duration _baseExitDuration = Duration(milliseconds: 480);

  /// Temps pendant lequel un pion RESTE VISIBLE sur la case spéciale qui
  /// vient de l'emporter — vortex, trou noir ou carte. Sans cette pause on
  /// ne voyait jamais qu'il y était passé : il semblait sauter d'un bout à
  /// l'autre du plateau sans raison.
  static const Duration _specialCellHold = Duration(milliseconds: 620);

  /// Temps d'affichage du dé AVANT qu'un coup automatique (un seul pion
  /// jouable) ne parte. Sans cette pause on ne voit jamais le chiffre.
  static const Duration _dicePause = Duration(milliseconds: 550);


  /// Durée de l'animation de lancer du Studio — MESURÉE sur les fichiers
  /// `Dice_<couleur>_throw_<valeur>.webp` : 20 images, 500 ms, sans
  /// répétition. Elles s'arrêtent d'elles-mêmes sur la face sortie ; on
  /// repasse ensuite au PNG net. Un test vérifie que cette valeur suit les
  /// fichiers si le Studio les refait.
  ///
  /// Le découpage : 300 ms de culbute, 100 ms de PALIER où le dé montre
  /// son volume, 100 ms de bascule à plat. C'est le palier qui fait qu'on
  /// voit un objet se poser, et non une image se figer.
  static const Duration _diceThrowDuration = Duration(milliseconds: 500);

  @visibleForTesting
  static Duration get diceThrowDurationForTest => _diceThrowDuration;

  /// Temps pendant lequel le dé GARDE la couleur et le chiffre du joueur
  /// qui vient de jouer, APRÈS que son pion s'est posé. Sans cette pause,
  /// le dé passait au joueur suivant à la seconde même de l'arrivée : on
  /// voyait l'ancien chiffre sous la nouvelle couleur, et celui qui venait
  /// de lancer n'avait jamais le temps de lire son propre résultat.
  ///
  /// INVARIANT : [_aiRollDelay] doit rester PLUS LONG que cette pause.
  /// Les deux minuteries sont armées au même instant ; si l'ordinateur
  /// était le plus court, il relancerait le dé pendant que le joueur
  /// précédent lit encore le sien.
  static const Duration _diceReadHold = Duration(milliseconds: 1200);

  /// Pause pendant laquelle l'attaquant ET le pion qu'il vient de capturer
  /// restent affichés ENSEMBLE sur la même case. Elle ne commence qu'une
  /// fois l'attaquant VISUELLEMENT arrivé ; le pion capturé n'a pas bougé
  /// d'un pixel avant cet instant, et ne quitte la case qu'à la fin.
  static const Duration _captureHold = Duration(milliseconds: 340);

  /// Temps que prend une IA avant de saisir le dé. C'est aussi le blanc
  /// que l'on voit entre deux ordinateurs qui s'enchaînent : sans lui, les
  /// couleurs défilent d'un bloc et on ne suit plus qui joue.
  ///
  /// Il est délibérément plus long que [_diceReadHold] : l'adversaire ne
  /// doit JAMAIS commencer son tour pendant que le joueur précédent lit
  /// son propre résultat. Voir l'invariant décrit là-bas.
  static const Duration _aiRollDelay = Duration(milliseconds: 1500);

  /// Reprise de l'IA après un Retour / Rejouer. Plus long que
  /// [_aiRollDelay] : il faut avoir le temps d'appuyer plusieurs fois de
  /// suite sur Retour sans que l'ordinateur ne reparte entre deux clics.
  static const Duration _aiResumeDelay = Duration(milliseconds: 1600);

  /// Temps entre le lancer d'une IA et le départ de son pion. Il rend le
  /// chiffre lisible avant que quoi que ce soit ne bouge — l'équivalent
  /// pour l'IA de [_dicePause] côté humain.
  static const Duration _aiMoveDelay = Duration(milliseconds: 700);

  /// Durée d'UNE case pendant le retour à contre-sens du pion capturé. Il
  /// rembobine son parcours — de la case où il s'est fait manger jusqu'à sa
  /// flèche d'entrée — avant de rentrer dans sa base. Nettement plus rapide
  /// qu'un déplacement joué : c'est un rembobinage, pas un coup.
  static const Duration _returnStep = Duration(milliseconds: 55);

  /// Durée TOTALE maximale d'un rembobinage. Au-delà, le pas se resserre :
  /// le retour reste lisible mais ne traîne jamais au point de sembler
  /// détaché de la capture qui l'a provoqué.
  static const Duration _returnBudget = Duration(milliseconds: 850);

  /// Position VISUELLE d'un pion pendant son trajet. Tant qu'une entrée est
  /// présente, le plateau dessine le pion sur cette case-là et non sur sa
  /// position réelle (le moteur, lui, a déjà appliqué tout le coup).
  final Map<Pawn, PawnStep> _travelStep = {};

  /// Combien de SAUTS ce pion a faits. Le compteur ne sert qu'à dire « une
  /// nouvelle case » à l'animation de saut : elle repart de zéro dès qu'il
  /// change, et n'a besoin de rien d'autre.
  final Map<Pawn, int> _hopSeq = {};

  /// Les pions en train de SORTIR DE LEUR BASE. Leur trajet n'est pas un
  /// pas : c'est une entrée en scène, et le plateau la dessine autrement
  /// — arc plus haut, freinage plus long.
  final Set<Pawn> _baseExit = {};

  /// Le pion se pose sur une case : le son fourni, et une petite secousse.
  ///
  /// Le fichier est celui que l'utilisateur a choisi
  /// (`UIAlert_Notification lasolisa 5`, LaSonotheque.fr), reconverti en
  /// PCM 16 bits — le 24 bits d'origine ne se décode pas partout sur le
  /// web — et renommé sans espaces, comme tous les assets du projet.
  ///
  /// La secousse reste : elle ne coûte rien et, sur Android, c'est elle
  /// qu'on sent sous le doigt avant même d'entendre le son.
  /// Témoin des sons, POUR LES TESTS.
  ///
  /// Le harnais n'a pas de greffon audio : on ne peut donc pas écouter ce
  /// qui sort. Ce qu'on PEUT vérifier — et c'est tout l'objet de la
  /// plainte « les sons ne coïncident pas » — c'est QUAND chaque son
  /// part. Ce témoin est appelé avant la coupure du son, sinon les tests,
  /// qui sont muets, ne verraient jamais rien.
  @visibleForTesting
  static void Function(String son)? onSoundForTest;

  void _stepBeat() {
    onSoundForTest?.call('pas');
    if (_muted) return;
    _stepSound.play();
    HapticFeedback.selectionClick();
  }

  /// Le pion QUITTE sa boîte : la chaîne, et une secousse plus franche —
  /// c'est un événement, pas un pas de plus.
  void _baseExitBeat() {
    onSoundForTest?.call('sortie');
    if (_muted) return;
    _baseExitSound.play();
    HapticFeedback.mediumImpact();
  }

  /// Ouvre les canaux et décode les quatre sons AVANT la première partie.
  ///
  /// Muet en test : le harnais n'a pas de greffon natif, et l'attente ne
  /// prouverait rien.
  Future<void> _warmSounds() async {
    if (_muted) return;
    final t = DateTime.now();
    await Future.wait([
      _diceSound.warmUp(),
      _stepSound.warmUp(),
      _baseExitSound.warmUp(),
      _captureSound.warmUp(),
    ]);
    debugPrint('[son] 4 banques prêtes en '
        '${DateTime.now().difference(t).inMilliseconds} ms');
  }

  /// Le dé part : le choc des dés. Une secousse légère avec — c'est le
  /// geste du joueur, pas un impact.
  void _diceBeat() {
    onSoundForTest?.call('de');
    if (_muted) return;
    _diceSound.play();
    HapticFeedback.lightImpact();
  }

  /// Un pion vient de se faire manger : le cri. Une seule fois par coup,
  /// même si le coup en renvoie deux — le lecteur en entend deux, mais
  /// c'est l'appelant qui décide combien de fois il déclenche.
  void _captureBeat() {
    onSoundForTest?.call('capture');
    if (_muted) return;
    _captureSound.play();
    HapticFeedback.heavyImpact();
  }

  /// Les voix du son de pas. Une par pion en mouvement ne suffirait pas :
  /// c'est le MÊME pion qui redéclenche le son tous les 190 ms, alors que
  /// le fichier dure 400 ms. Il faut donc plusieurs voix pour que le pas
  /// suivant n'arrête pas le précédent.
  final _Sfx _stepSound = _Sfx('audio/pawn_step.wav', voices: 4);

  /// LA CAPTURE : le cri. Deux voix, parce qu'un même coup peut renvoyer
  /// deux pions à la fois — et qu'on doit alors entendre deux cris.
  final _Sfx _captureSound = _Sfx('audio/capture.wav');

  /// LA SORTIE DE BASE : la chaîne. Pour TOUTES les couleurs — le son ne
  /// dépend pas de qui sort, seulement de ce qui se passe.
  final _Sfx _baseExitSound = _Sfx('audio/base_exit.wav');

  /// LE LANCER DU DÉ. Le seul des quatre qui soit un MP3 : il est arrivé
  /// ainsi, il pèse 33 Ko au lieu des 350 Ko qu'un PCM coûterait, et tous
  /// les navigateurs comme Android le lisent. Une seule voix : on ne
  /// lance pas deux dés en même temps.
  final _Sfx _diceSound = _Sfx('audio/dice_roll.mp3', voices: 1);

  /// Coupe le son des pas. Les tests le lèvent : le son passe par un
  /// greffon natif, et 400 lectures par suite de tests ne prouvent rien —
  /// elles échoueraient d'ailleurs, faute de greffon dans le harnais.
  static bool _muted = false;

  @visibleForTesting
  static set muteStepSounds(bool v) => _muted = v;

  /// Pions capturés mais visiblement encore à leur ancienne position. Le moteur
  /// a déjà rendu le pion capturé, mais on le MONTRE en train de se faire
  /// capturer — à sa place d'avant la capture — pendant que le pion attaquant
  /// fait son trajet. Une fois que l'attaquant arrive sur cette case, le pion
  /// disparaît (on l'enlève de cette map).
  final Map<Pawn, PawnStep> _captureOverride = {};

  /// Timer du trajet en cours et du coup automatique en attente.
  /// Trajets en cours, une minuterie PAR PION : en mode Rapide plusieurs
  /// pions avancent en même temps, un timer unique les écraserait.
  final Map<Pawn, Timer> _travelTimers = {};
  Timer? _autoMoveTimer;

  /// Fin de trajet (verrou + pause de capture) et explosion différée. Ils
  /// étaient anonymes — impossibles à annuler, ils survivaient au dispose
  /// et à l'annulation d'un coup. Suivis pour être coupés proprement.
  final Map<Pawn, Timer> _travelEndTimers = {};
  Timer? _explosionTimer;

  /// Minuterie de [_diceReadHold] : elle rend la main au joueur suivant.
  Timer? _diceReadTimer;

  /// Le dé roule-t-il en ce moment ? Le temps de l'animation de lancer, le
  /// plateau affiche le WebP animé du Studio au lieu de la face fixe.
  bool _diceRolling = false;
  Timer? _diceThrowTimer;

  /// Incrémenté à CHAQUE lancer. Il sert de clé à l'image du dé : sans lui,
  /// rejouer la même couleur et la même valeur réutilise l'image déjà
  /// décodée, qui reste figée sur sa dernière frame — l'animation ne
  /// repartait donc pas d'un lancer à l'autre.
  int _throwSeq = 0;

  /// Timers des retours à contre-sens des pions capturés, indexés par pion.
  /// Il peut y en avoir plusieurs en vol (deux pions mangés d'un coup), et
  /// ils survivent au tour suivant — c'est de l'habillage, ça ne bloque pas
  /// la partie. Indexés par pion pour pouvoir en couper UN seul : celui qui
  /// repart de sa base ne doit plus rembobiner.
  final Map<Pawn, Timer> _returnTimers = {};

  /// Last hover info text (token or dice), shown next to the Détails toggle.
  String? _hoverInfo;

  /// Face affichée AVANT le premier lancer de la partie. Purement
  /// décoratif : dès qu'un dé est lancé, c'est `_controller.lastRoll` qui
  /// commande.
  int _initialDiceFace = math.Random().nextInt(6) + 1;

  /// Valeur montrée par le dé central. Il n'y a QU'UN dé sur le plateau :
  /// il garde la dernière valeur sortie et change simplement de couleur
  /// quand la main passe. Bleu fait 5 → le dé reste sur 5 et devient rouge
  /// en attendant que rouge joue.
  int get _shownDice =>
      _controller.lastRoll > 0 ? _controller.lastRoll : _initialDiceFace;

  /// Couleur RETENUE pendant qu'un pion parcourt ses cases. Le moteur
  /// passe la main dès que le coup est appliqué, c'est-à-dire au DÉBUT de
  /// l'animation ; sans cette retenue le dé et le Yard clignotant
  /// sauteraient au joueur suivant alors que le pion est encore en train
  /// de compter. `null` = pas de trajet en cours, on suit le joueur
  /// courant.
  PlayerColor? _activeColorHold;

  /// Couleur du siège ACTIF : celle du pion qui compte ses cases tant
  /// qu'il n'est pas arrivé, sinon celle du joueur dont c'est le tour.
  /// Elle commande les DEUX indicateurs de tour : la couleur du dé
  /// central et le Yard qui clignote.
  /// Sort du cache d'images l'animation de lancer sur le point d'être
  /// jouée, pour qu'elle reparte de sa première frame. Voir le long
  /// commentaire dans [_roll].
  void _evictThrowAnimation(PlayerColor c, int value) {
    final v = value.clamp(1, 6);
    // La couleur affichée peut être celle qu'on retient encore du coup
    // précédent : on évince les deux, c'est deux entrées de cache.
    for (final name in {c.name, _activeColor.name}) {
      AssetImage('AnimStock/Dices/WEBP/Dice_${name}_throw_$v.webp').evict();
    }
  }

  PlayerColor get _activeColor =>
      _activeColorHold ?? _controller.currentColor;

  /// One idle-animation index (1..5) per pawn, drawn once at startup.
  late final Map<Pawn, int> _pawnAnimIdx;

  /// Returns the WebP asset path for [pawn]'s currently assigned idle anim.
  /// Filename convention (Studio's): `Token_standard_<color>_idle_#<n>.webp`.
  /// If no variant is available for this color, returns an empty string —
  /// `_PawnAnimatedGif` then renders an empty placeholder.
  String _pawnAsset(Pawn pawn) {
    final idx = _pawnAnimIdx[pawn];
    if (idx == null || idx <= 0) return '';
    return 'AnimStock/Tokens/WEBP/'
        'Token_standard_${pawn.color.name}_idle_#$idx.webp';
  }

  /// Active player colors derived from [_playerCount].
  ///   1 → blue alone
  ///   2 → blue + green (diagonal — opposite bases on the 4-player board)
  ///   3 → blue + red + green
  ///   4+ → all four
  List<PlayerColor> get _activeColors {
    switch (_playerCount.clamp(1, 4)) {
      case 1:  return const [PlayerColor.blue];
      case 2:  return const [PlayerColor.blue, PlayerColor.green];
      case 3:  return const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
      ];
      default: return const [
        PlayerColor.blue,
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ];
    }
  }

  /// Filter [BoardScreen.players] to the currently-active colors.
  List<Player> get _activePlayers => BoardScreen.players
      .where((p) => _activeColors.contains(p.color))
      .toList();

  void _onChangePlayerCount(int n) {
    setState(() {
      _playerCount = n;
      final order = _activeColors;
      _controller.turnOrder = order;
      if (_controller.currentPlayerIdx >= order.length) {
        _controller.currentPlayerIdx = 0;
      }
      // If the manually-selected color is no longer active, fall back to the
      // first active one.
      if (!order.contains(_manualPlayer)) {
        _manualPlayer = order.first;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _applySetup();
    _bootstrap();
    // Le dé change de couleur à chaque passage de main. Sans préchargement,
    // la 1re fois qu'une face (valeur × couleur) apparaît, Flutter doit
    // d'abord la charger : le dé garde visiblement l'ancienne couleur
    // pendant ce temps. 24 images à précharger, une fois pour toutes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheDice());
    _startAiWatchdog();
    _applyAiSeatsFromUrl();
  }

  /// Les réglages TELS QU'ILS SONT maintenant. Relus sur le moteur, pas
  /// sur `widget.setup` : c'est ce qui permet à un changement fait dans le
  /// panneau de survivre au retour au menu.
  GameSetup get _currentSetup => GameSetup(
        playerCount: _playerCount,
        aiSeats: Set<PlayerColor>.from(_aiSeats),
        difficulty: _controller.aiDifficulty,
        teamMode: _controller.teamMode,
        vortex: _controller.upgrades.vortexEnabled,
        chance: _controller.upgrades.chanceEnabled,
        aiTurbo: _aiTurbo,
        // Le décor n'est pas réglable depuis le plateau : on rend celui
        // qu'on a reçu, sans le perdre au passage.
        background: widget.setup.background,
      );

  /// Applique les choix de l'écran d'accueil. Une seule fois, avant tout
  /// le reste : le contrôleur doit connaître l'ordre des tours et les
  /// sièges d'ordinateur avant que la moindre minuterie ne parte.
  void _applySetup() {
    _panelCollapsed = false;
    _panelTab = widget.initialPanelTab;
    final s = widget.setup;
    _playerCount = s.playerCount;
    _controller.turnOrder = _activeColors;
    if (!_activeColors.contains(_manualPlayer)) {
      _manualPlayer = _activeColors.first;
    }
    _aiSeats
      ..clear()
      ..addAll(s.aiSeats.where(_activeColors.contains));
    _controller.aiDifficulty = s.difficulty;
    _controller.teamMode = s.teamMode && s.playerCount == 4;
    _controller.upgrades.vortexEnabled = s.vortex;
    _controller.upgrades.chanceEnabled = s.chance;
    _aiTurbo = s.aiTurbo;
  }

  /// Sièges IA depuis l'URL : `?ai=all` ou `?ai=red,green,yellow`.
  ///
  /// D'abord un outil de REPRODUCTION : le pane de test ne transmet pas les
  /// clics à l'app (rendu canvaskit), ce paramètre permet de lancer une
  /// partie contre l'ordinateur sans toucher au panneau — et accessoirement
  /// de partager une configuration par lien.
  void _applyAiSeatsFromUrl() {
    // `?upgrades=1` allume Vortex + Chance dès le chargement — même canal
    // de test que `?ai=` : le pane du navigateur ne transmet pas toujours
    // les clics à l'app canvaskit.
    final upg = Uri.base.queryParameters['upgrades'];
    if (upg == '1' || upg == 'true') {
      _controller.upgrades
        ..vortexEnabled = true
        ..chanceEnabled = true;
      debugPrint('[amélioration] Vortex + Chance activés depuis l\'URL');
    }
    // `?home=all` range les 16 pions au centre : c'est le seul moyen de
    // REGARDER le placement dans les triangles sans jouer quatre parties.
    if (Uri.base.queryParameters['home'] == 'all') {
      setState(() {
        for (final p in _game.allPawns) {
          p.location = PawnLocation.home;
        }
      });
      return;
    }
    final param = Uri.base.queryParameters['ai'];
    if (param == null || param.isEmpty) return;
    final seats = <PlayerColor>{};
    if (param == 'all') {
      seats.addAll(_controller.turnOrder);
    } else {
      for (final name in param.split(',')) {
        for (final c in PlayerColor.values) {
          if (c.name == name.trim()) seats.add(c);
        }
      }
    }
    if (seats.isEmpty) return;
    debugPrint('[ai] sièges depuis l\'URL : '
        '${seats.map((c) => c.name).join(', ')}');
    setState(() => _aiSeats
      ..clear()
      ..addAll(seats));
    // `?fast=1` bascule aussi le mode Rapide — même motif que les sièges :
    // le pane de test ne transmet pas les clics à l'app canvaskit.
    final fast = Uri.base.queryParameters['fast'];
    if (fast == '1' || fast == 'true') {
      setFastMode(true);
    } else {
      _scheduleAiTurn();
    }
  }

  @override
  void dispose() {
    _aiWatchdog?.cancel();
    _revealTimer?.cancel();
    _cancelAnimations();
    // Chaque lecteur tient un canal natif : les rendre tous.
    _stepSound.dispose();
    _captureSound.dispose();
    _baseExitSound.dispose();
    _diceSound.dispose();
    super.dispose();
  }

  Future<void> _precacheDice() async {
    if (!mounted) return;
    for (final color in PlayerColor.values) {
      for (int v = 1; v <= 6; v++) {
        if (!mounted) return;
        await precacheImage(
          AssetImage('AnimStock/Dices/PNG/Dice_${v}_${color.name}.png'),
          context,
          onError: (e, _) =>
              debugPrint('[dice] préchargement raté : Dice_${v}_$color'),
        );
      }
    }
    debugPrint('[dice] 24 faces préchargées');
  }

  /// Move pawn #0 of every active color from its base slot onto its ring
  /// start cell. Idempotent: a pawn already on the ring stays put.
  void _applyRuleStartWith1TokenOut() {
    for (final color in _activeColors) {
      final pawns = _game.pawnsByColor[color];
      if (pawns == null || pawns.isEmpty) continue;
      final firstInBase = pawns.firstWhere(
        (p) => p.location == PawnLocation.base,
        orElse: () => pawns.first,
      );
      if (firstInBase.location != PawnLocation.base) continue;
      firstInBase.location = PawnLocation.ring;
      firstInBase.position = GameController.startIdx(color);
    }
  }

  /// Probe the asset bundle to discover which idle variants exist per
  /// color (Studio's filename: `Token_standard_<color>_idle_#<n>.gif`),
  /// then assign each pawn a DISTINCT variant within its color pool.
  ///
  /// Resilient: missing files are logged but DON'T block startup.
  /// Detailed: every probe + every assignment is `debugPrint`-ed AND
  /// surfaced in `_loadingStatus` so the boot screen shows what's
  /// happening instead of a blank "Loading tokens…".
  Future<void> _bootstrap() async {
    debugPrint('[bootstrap] ==== start ====');
    final t0 = DateTime.now();
    final rng = math.Random();
    _pawnAnimIdx = {};

    // Group pawns by color for the later distribution pass.
    final byColor = <PlayerColor, List<Pawn>>{};
    for (final p in _game.allPawns) {
      byColor.putIfAbsent(p.color, () => []).add(p);
    }

    // ─── Probe idle variants per color ────────────────────────────────
    const maxVariantsToProbe = 5;
    final available = <PlayerColor, List<int>>{};
    int probedTotal = 0;
    int foundTotal = 0;
    for (final color in PlayerColor.values) {
      final found = <int>[];
      for (int i = 1; i <= maxVariantsToProbe; i++) {
        probedTotal++;
        final asset = 'AnimStock/Tokens/WEBP/'
            'Token_standard_${color.name}_idle_#$i.webp';
        _setLoading('Sondage ${color.name} idle #$i…');
        try {
          await _GifFrames.load(asset);
          found.add(i);
          foundTotal++;
          debugPrint('[bootstrap]   $asset → OK');
        } catch (e) {
          debugPrint('[bootstrap]   $asset → MISSING ($e)');
        }
      }
      available[color] = found;
      debugPrint('[bootstrap] ${color.name}: ${found.length} variant(s) '
          'disponibles → $found');
    }
    _availableVariants = available;
    _setLoading('Tokens trouvés : $foundTotal / $probedTotal');

    // ─── Les sons, PRÉPARÉS MAINTENANT ────────────────────────────────
    //
    // C'est le vrai retard qu'on entendait. Le premier `play()` faisait
    // tout le travail : créer les lecteurs, ouvrir un canal natif par
    // voix, décoder le fichier. Le tout dure facilement une demi-seconde,
    // et l'on entendait donc le dé APRÈS son animation, puis le pion
    // APRÈS son pas — chaque son avec un tour de retard sur son geste.
    //
    // On paie ce prix ici, pendant que l'écran de chargement est déjà à
    // l'écran pour les pions. Ensuite, `play()` n'a plus qu'à rembobiner
    // et lancer : quelques millisecondes, imperceptibles.
    _setLoading('Sons…');
    await _warmSounds();

    // ─── Assign each pawn a distinct anim from its color's pool ───────
    for (final entry in byColor.entries) {
      final pool = List<int>.from(available[entry.key] ?? const [])
        ..shuffle(rng);
      if (pool.isEmpty) {
        for (final p in entry.value) {
          _pawnAnimIdx[p] = 0; // no asset
        }
        debugPrint('[bootstrap] ${entry.key.name}: AUCUN asset → '
            'pions rendus en placeholder');
      } else {
        for (int i = 0; i < entry.value.length; i++) {
          _pawnAnimIdx[entry.value[i]] = pool[i % pool.length];
        }
        debugPrint('[bootstrap] ${entry.key.name}: anims = '
            '${entry.value.map((p) => _pawnAnimIdx[p]).toList()}');
      }
    }

    final dt = DateTime.now().difference(t0).inMilliseconds;
    debugPrint('[bootstrap] ==== done in ${dt}ms '
        '($foundTotal/$probedTotal tokens) ====');
    if (!mounted) return;
    setState(() {
      _loadingStatus = '$foundTotal token(s) chargés en ${dt}ms';
      _assetsReady = true;
    });
  }

  void _setLoading(String msg) {
    debugPrint('[loading] $msg');
    if (!mounted) return;
    setState(() => _loadingStatus = msg);
  }

  /// Roll the dice and auto-move if a single pion can play.
  ///
  /// One function, one rule. The trigger is THE ROLL — random / manual /
  /// debug all funnel through here, none knows about "mode".
  /// [forPlayer] optionally pins a specific color before rolling (used
  /// by the manual picker; null = roll for whoever the controller says
  /// is currently up).
  void _roll(int value, {PlayerColor? forPlayer}) {
    if (_controller.phase == TurnPhase.gameOver) return;
    // Quelqu'un relance : la pause de lecture du coup précédent n'a plus
    // lieu d'être, sinon le dé afficherait le nouveau chiffre sous
    // l'ancienne couleur.
    _diceReadTimer?.cancel();
    _activeColorHold = null;
    // Le dé roule. L'animation du Studio s'arrête seule sur la face sortie ;
    // ce minuteur ne fait que rendre la main au PNG net ensuite.
    _diceThrowTimer?.cancel();
    // ── POURQUOI ON VIDE LE CACHE ICI ────────────────────────────────
    //
    // Le WebP de lancer a `repetitionCount == 0` : il joue UNE fois puis
    // s'arrête. Flutter le garde ensuite dans son `ImageCache`, TERMINÉ.
    // Redemander le même fichier rend ce flux déjà fini : l'image
    // apparaît directement sur sa dernière frame, sans animation.
    //
    // La `ValueKey` posée sur le widget n'y change rien — elle recrée
    // l'État, pas le flux, et c'est le flux qui est épuisé. D'où le bug
    // constaté : le dé s'animait quand la valeur ou la couleur changeait
    // (autre fichier, donc autre entrée de cache) et restait figé dès
    // qu'on retombait sur la même face de la même couleur.
    //
    // On évince donc l'entrée avant chaque lancer. L'éviction se règle en
    // une microtâche, donc bien avant la frame que `setState` déclenche.
    _evictThrowAnimation(forPlayer ?? _controller.currentColor, value);
    _diceRolling = true;
    _throwSeq++;
    // LE LANCER : ici, et nulle part ailleurs. Tout ce qui jette le dé
    // passe par cette ligne — le doigt du joueur, l'ordinateur, le lancer
    // manuel du panneau — donc chaque lancer sonne, et un seul son par
    // lancer.
    _diceBeat();
    _diceThrowTimer = _after(_pace(_diceThrowDuration), () {
      if (!mounted) return;
      setState(() => _diceRolling = false);
    });
    // Point de retour : l'instantané est pris AVANT le lancer, donc le
    // bouton Retour annule le lancer ET le déplacement joué avec.
    _controller.pushHistory(
        '${(forPlayer ?? _controller.currentColor).name} · dé $value');
    Pawn? autoMove;
    // Non nul si le LANCER LUI-MÊME a passé la main : aucun coup jouable,
    // ou troisième 6. Ces deux cas changeaient de joueur dans le même
    // instant que l'affichage du chiffre.
    PlayerColor? passedFrom;
    setState(() {
      if (forPlayer != null) {
        // Mode manuel : on force la main à [forPlayer] et on repart d'un
        // tour propre. Ce forçage est RÉSERVÉ au mode manuel — l'appliquer
        // à un lancer normal remettrait `consecutiveSixes` à zéro à chaque
        // lancer, et la règle des trois 6 (§9) ne pourrait jamais se
        // déclencher.
        final idx = _controller.turnOrder.indexOf(forPlayer);
        if (idx >= 0) _controller.currentPlayerIdx = idx;
        _manualValue = value;
        _controller.phase = TurnPhase.rolling;
        _controller.diceValue = 0;
        _controller.consecutiveSixes = 0;
      }
      // La couleur est lue AVANT roll() : roll() peut passer la main (aucun
      // coup jouable, ou 3 six), et le dé affiché doit rester celui du
      // joueur qui vient de lancer.
      _autoNotice = null; // un nouveau lancer efface le message précédent
      // La couleur est lue AVANT roll() : un troisième 6 annule le tour et
      // passe la main, et la trace attribuerait alors le lancer au joueur
      // SUIVANT — c'est ce qui produisait des lignes « 0 pion jouable »
      // incompréhensibles.
      final roller = _controller.currentColor;
      _controller.roll(value);
      // Trace demandée : sur un 6, dire EXACTEMENT quels pions sont
      // jouables et d'où, pour vérifier que celui posé sur la flèche
      // d'entrée figure bien parmi les choix.
      if (value == 6) _logSixOptions(roller);
      // Améliorations : le lancer lui-même peut produire des annonces —
      // un joueur qui saute son tour, par exemple. Sans cette purge elles
      // restaient en tampon et ressortaient plus tard, collées au coup
      // d'un autre joueur.
      final rollNotices = _controller.upgrades.takeNotices();
      for (final n in rollNotices) {
        debugPrint('[amélioration] $n');
      }
      if (rollNotices.isNotEmpty) _autoNotice = rollNotices.join('\n');
      // Le lancer a-t-il passé la main tout seul ? On RETIENT alors la
      // couleur de celui qui vient de lancer : sans ça, son chiffre
      // s'affiche aussitôt sous la couleur du joueur suivant, et il ne
      // voit jamais ce qu'il a tiré.
      if (_controller.currentColor != roller) {
        passedFrom = roller;
        _activeColorHold = roller;
      }
      // The ONLY rule, applied to every roll:
      // 1 pion movable → play it.
      if (_controller.phase == TurnPhase.moving) {
        final m = _controller.movablePawns();
        // Un seul pion jouable → il part tout seul, mais SEULEMENT après
        // que le dé a été affiché un instant (voir _scheduleAutoMove).
        if (m.length == 1) autoMove = m.single;
      }
      // BUG CORRIGÉ — le sélecteur de couleur du Jeu manuel restait figé sur
      // la couleur choisie alors que le lancer venait de passer la main.
      // On voyait « rouge » sélectionné pendant que c'était au vert de jouer,
      // et le clic suivant sortait un pion vert. Le sélecteur suit désormais
      // toujours le tour réel.
      _syncManualPlayer();
    });
    final pending = autoMove;
    _openDrawnCardIfAny();
    if (pending != null) _scheduleAutoMove(pending);
    // La main rendue par le lancer lui-même : on laisse le chiffre et la
    // couleur du lanceur affichés le temps qu'il les lise, puis le dé
    // passe au joueur suivant. L'ordinateur, lui, attend de toute façon
    // [_aiRollDelay] — plus long que cette pause — avant de saisir le dé.
    final held = passedFrom;
    if (held != null) {
      _diceReadTimer?.cancel();
      _diceReadTimer = _after(_pace(_diceReadHold, ai: _isAiColor(held)), () {
        if (!mounted) return;
        if (_activeColorHold != held) return;
        setState(() => _activeColorHold = null);
      });
    }
  }

  /// La carte IMMÉDIATE qui attend qu'on lui désigne un pion. Elle s'ouvre
  /// avec la liste des pions visés, et n'agit qu'une fois le choix fait.
  ({ChanceCard card, Pawn onPawn})? _pendingChoice;

  /// La carte en attente de cible, pour les tests.
  @visibleForTesting
  ChanceCard? get pendingChoiceCard => _pendingChoice?.card;

  /// Applique la carte en attente au pion désigné.
  @visibleForTesting
  void resolvePendingChoice(Pawn? chosen) {
    if (_pendingChoice == null) return;
    setState(() {
      _pendingChoice = null;
      _controller.resolvePendingImmediate(chosen: chosen);
      _flushUpgradeNotices();
    });
  }

  /// La carte de la main qu'on vient de RETOURNER pour la lire, avec son
  /// propriétaire. `null` = aucune carte ouverte à la main.
  ({ChanceCard card, PlayerColor by, int slot})? _handCard;

  /// La carte ouverte à la main, pour les tests.
  @visibleForTesting
  ChanceCard? get openedHandCard => _handCard?.card;

  /// Les deux dés à montrer, ou `null` pour un dé unique.
  ///
  /// La carte « Deux dés » vaut deux tours, et pendant ces deux tours le
  /// joueur lance VRAIMENT deux dés : le centre doit les montrer tous les
  /// deux. Avant son premier lancer sous ce mode, on affiche deux faces
  /// neutres plutôt que rien.
  ({int a, int b})? get _twoDiceShown {
    final mode = _controller.upgrades.activeDiceMode(_activeColor);
    // DEUX cartes mettent deux dés au centre : « Deux dés », dont on joue
    // la somme, et « Double-dé », qui compte deux fois la même face. Le
    // DEMI-dé, lui, reste un dé unique : il ne change que les valeurs.
    if (mode != CardDiceMode.twoDice && mode != CardDiceMode.double) {
      return null;
    }
    return _controller.upgrades.lastTwoDice ?? (a: 1, b: 1);
  }

  /// La couleur dont les cartes de base sont cliquables : celle qui a la
  /// main, et seulement si un HUMAIN la tient. Une carte qu'on n'a pas le
  /// droit de jouer reste close.
  PlayerColor? get _cardTapSeat {
    if (!_controller.upgrades.chanceEnabled) return null;
    final seat = _deferredSeat;
    if (_isAiColor(seat)) return null;
    return seat;
  }

  /// Le siège dont les cartes sont cliquables, pour les tests.
  @visibleForTesting
  PlayerColor? get cardTapSeatForTest => _cardTapSeat;

  /// Le joueur a touché la carte n° [slot] de sa base : elle se retourne.
  @visibleForTesting
  void openHandCard(int slot) => _openHandCard(slot);

  void _openHandCard(int slot) {
    if (_paused) return;
    final seat = _cardTapSeat;
    if (seat == null) return;
    final hand = _controller.upgrades.handOf(seat);
    if (slot < 0 || slot >= hand.length) return;
    setState(() => _handCard = (card: hand[slot], by: seat, slot: slot));
  }

  /// Ouvre la carte du rang [slot], comme un clic sur son dos.
  @visibleForTesting
  void openHandCardForTest(int slot) => _openHandCard(slot);

  /// Referme la carte retournée sans la jouer.
  @visibleForTesting
  void closeHandCard() {
    if (_handCard != null) setState(() => _handCard = null);
  }

  /// Joue la carte actuellement ouverte, avec la cible choisie.
  void _playOpenedHandCard({Pawn? targetPawn, PlayerColor? targetPlayer}) {
    final open = _handCard;
    if (open == null) return;
    setState(() => _handCard = null);
    playDeferredCard(open.card,
        targetPawn: targetPawn, targetPlayer: targetPlayer);
  }

  /// Applique une carte Chance CHOISIE À LA MAIN, comme le fait la carte
  /// « Jeu manuel » pour le dé.
  ///
  /// Une carte IMMÉDIATE s'exécute séance tenante sur le pion [pawnId] de
  /// [player] ; une carte DIFFÉRÉE se range dans sa main, où il pourra la
  /// retourner et la jouer. Cet outil n'attend pas qu'une case Chance
  /// tombe : c'est ce qui permet d'essayer les 24 cartes une par une.
  @visibleForTesting
  void applyManualCard(ChanceCard card, PlayerColor player, int pawnId) {
    if (_paused) return;
    final pawn = _controller.state.pawnsByColor[player]![pawnId.clamp(0, 3)];
    setState(() {
      if (card.kind == CardKind.immediate) {
        _controller.upgrades.addNotice(
            'Carte chance pour ${_frenchColor(player)} : « ${card.nameFr} »');
        // Le moteur applique au nom de [player] : les cartes de dé et le
        // saut de tour visent CELUI QUI JOUE.
        _controller.runAsSeat(
            player, () => _controller.applyImmediateCard(card, pawn));
      } else if (!_controller.upgrades.addToHand(player, card)) {
        _controller.upgrades.addNotice(
            'Main de ${_frenchColor(player)} pleine : la carte est perdue.');
      } else {
        _controller.upgrades.addNotice(
            'Carte différée pour ${_frenchColor(player)} : '
            '« ${card.nameFr} » — à jouer à son tour.');
      }
      final notices = _controller.upgrades.takeNotices();
      for (final n in notices) {
        debugPrint('[amélioration] $n');
      }
      if (notices.isNotEmpty) _autoNotice = notices.join('\n');
    });
  }

  /// L'ordinateur pose une carte différée s'il en tient une de bonne.
  ///
  /// Rend `true` quand une carte a été jouée : le tour reprend alors son
  /// cours par la voie normale — une carte-dé remplace le lancer, les
  /// autres laissent le dé à lancer, et [_scheduleAiTurn] repasse.
  bool _playAiDeferredIfAny() {
    final me = _controller.currentColor;
    if (!_controller.upgrades.chanceEnabled) return false;
    final choice = _controller.pickAiDeferred(me);
    if (choice == null) return false;
    final forced = _controller.playDeferredCard(me, choice.card,
        targetPawn: choice.targetPawn, targetPlayer: choice.targetPlayer);
    setState(() {
      final notices = _controller.upgrades.takeNotices();
      for (final n in notices) {
        debugPrint('[amélioration] $n');
      }
      if (notices.isNotEmpty) _autoNotice = notices.join('\n');
    });
    debugPrint('[ai] ${me.name} joue « ${choice.card.nameFr} »');
    if (forced != null) {
      _roll(forced);
      if (_animating) return true;
      if (_controller.phase == TurnPhase.moving) {
        _aiTimer = _after(_pace(_aiMoveDelay, ai: true), _playAiMove);
      } else {
        _scheduleAiTurn();
      }
    } else {
      // Carte sans dé : il reste à lancer, on repasse tout de suite.
      _scheduleAiTurn();
    }
    return true;
  }

  /// Suite d'un tirage sur une case Chance.
  ///
  /// Une carte IMMÉDIATE s'ouvre : elle agit tout de suite, le joueur doit
  /// voir ce qui vient de lui arriver. Une carte DIFFÉRÉE, elle, ne montre
  /// RIEN : elle rejoint la base face cachée et y attend qu'on la retourne.
  ///
  /// Et si l'immédiate réclame une cible, on la présente avec son choix de
  /// pion au lieu de l'appliquer d'office.
  void _openDrawnCardIfAny() {
    final drawn = _controller.upgrades.takeLastDrawn();
    final pending = _controller.upgrades.pendingChoice;
    if (pending != null) {
      final owner = pending.onPawn.color;
      if (_isAiColor(owner)) {
        // L'ordinateur désigne son pion lui-même, sans rien afficher.
        final target = _controller.pickAiImmediateTarget();
        setState(() {
          _controller.resolvePendingImmediate(chosen: target);
          _flushUpgradeNotices();
        });
        debugPrint('[ai] ${owner.name} désigne le pion '
            '${(target?.id ?? pending.onPawn.id) + 1} pour '
            '« ${pending.card.nameFr} »');
        return;
      }
      setState(() => _pendingChoice = pending);
      return;
    }
    if (drawn == null) return;
    // Toute carte tirée se MONTRE. Une différée part se ranger dans la
    // base de son propriétaire ; sans ce temps d'arrêt, elle y arrivait
    // sans que personne ne l'ait vue — ni son propriétaire, ni la table.
    _openCard(drawn);
  }

  /// Vide les annonces du moteur vers le panneau et la console.
  void _flushUpgradeNotices() {
    final notices = _controller.upgrades.takeNotices();
    for (final n in notices) {
      debugPrint('[amélioration] $n');
    }
    if (notices.isNotEmpty) _autoNotice = notices.join('\n');
  }

  /// Un demi-tour pour les joueurs du HAUT du plateau. Rouge et vert sont
  /// assis en haut : une carte dessinée dans le sens de l'écran leur
  /// arriverait à l'envers. Bleu et jaune, en bas, la lisent telle quelle.
  Widget _facing(PlayerColor c, Widget card) =>
      (c == PlayerColor.red || c == PlayerColor.green)
          ? RotatedBox(quarterTurns: 2, child: card)
          : card;

  /// La carte qui vient d'être tirée sur une case Chance et qui doit
  /// S'OUVRIR : le joueur voit son dos, puis elle se retourne sur sa vraie
  /// face et son instruction. `null` = aucune carte à montrer.
  ({ChanceCard card, PlayerColor by})? _revealed;

  /// Minuterie qui referme la carte toute seule.
  Timer? _revealTimer;

  /// Combien de temps une carte IMMÉDIATE reste ouverte. Assez pour lire
  /// l'instruction sans avoir à cliquer — son effet part dans la foulée.
  static const Duration _revealHold = Duration(milliseconds: 3200);


  /// Ouvre [drawn] au centre du plateau. Un clic la referme plus tôt.
  ///
  /// SAUF pour une carte DIFFÉRÉE : celle-là file directement dans la
  /// base de son propriétaire, sans se montrer. Rien ne se joue au
  /// moment du tirage — la présentation ne faisait qu'interrompre la
  /// partie pour une carte qu'on jouera plus tard, et qu'on peut de
  /// toute façon consulter en la maintenant dans sa base.
  void _openCard(({ChanceCard card, PlayerColor by}) drawn) {
    _revealTimer?.cancel();
    if (drawn.card.kind == CardKind.deferred) {
      if (_revealed != null) setState(() => _revealed = null);
      return;
    }
    setState(() => _revealed = drawn);
    _revealTimer = _after(
        _pace(_revealHold, ai: _isAiColor(drawn.by)), () => closeCard());
  }

  // ── DÉSIGNER SA CIBLE SUR LE PLATEAU ─────────────────────────────────
  //
  // « Empêchez un pion adverse de sortir » : la cible se choisissait dans
  // une liste déroulante — « pion 3 de rouge » — alors qu'elle est là, sur
  // le plateau, sous les yeux du joueur. Il la DÉSIGNE maintenant en la
  // touchant, quelle que soit sa couleur.
  //
  // La liste déroulante reste : elle sert au clavier, aux tests, et à
  // l'ordinateur. La désignation s'ajoute, elle ne remplace rien.
  ({
    ChanceCard card,
    PlayerColor by,
    List<Pawn> targets,
    void Function(Pawn) pick,
  })? _targeting;

  /// Les pions désignables en ce moment, pour le plateau et les tests.
  @visibleForTesting
  List<Pawn> get targetPawns => _targeting?.targets ?? const [];

  void _startTargeting({
    required ChanceCard card,
    required PlayerColor by,
    required List<Pawn> targets,
    required void Function(Pawn) pick,
  }) {
    if (targets.isEmpty) return;
    setState(() {
      _handCard = null;   // la carte s'efface : elle cachait le plateau
      _targeting = (card: card, by: by, targets: targets, pick: pick);
    });
  }

  @visibleForTesting
  void cancelTargeting() {
    if (_targeting != null) setState(() => _targeting = null);
  }

  void _pickTarget(Pawn p) {
    final t = _targeting;
    if (t == null || !t.targets.contains(p)) return;
    setState(() => _targeting = null);
    t.pick(p);
  }

  // ── LA CARTE MAINTENUE ────────────────────────────────────────────────
  //
  // Un doigt posé sur une carte de sa base la montre, en grand, tant qu'il
  // y reste. C'est le geste qu'on fait avec une vraie carte quand on la
  // lève pour que la table la voie : elle se montre, puis on la repose.
  //
  // Au relâchement, la carte s'ouvre pour de bon — avec son bouton
  // « Jouer la carte ». Le maintien ne remplace donc rien, il s'ajoute.
  ({ChanceCard card, PlayerColor by})? _heldCard;

  ChanceCard? get heldCardForTest => _heldCard?.card;

  /// Quand le doigt s'est posé. Sert à distinguer les deux gestes.
  DateTime? _heldSince;

  /// En dessous de ce délai, ce n'était pas un maintien : c'était une
  /// TOUCHE. Au-delà, le joueur regardait sa carte.
  static const Duration _holdThreshold = Duration(milliseconds: 250);

  void _holdHandCard(int slot) {
    if (_paused) return;
    final seat = _cardTapSeat;
    if (seat == null) return;
    final hand = _controller.upgrades.handOf(seat);
    if (slot < 0 || slot >= hand.length) return;
    _heldSince = DateTime.now();
    setState(() => _heldCard = (card: hand[slot], by: seat));
  }

  /// Le doigt se lève. DEUX gestes, un seul contact :
  ///
  ///   * il a MAINTENU — il regardait sa carte, et la montrait à la
  ///     table. On la repose, rien de plus.
  ///   * il a TOUCHÉ — la carte part. Directement, sans boîte de
  ///     dialogue : c'est ce que veut dire toucher sa carte.
  ///
  /// Si la carte réclame une cible, on n'invente pas : le plateau passe
  /// en désignation et le joueur touche le pion qu'il vise.
  void _releaseHandCard(int slot) {
    final held = _heldCard;
    final since = _heldSince;
    _heldSince = null;
    if (held == null) return;
    setState(() => _heldCard = null);

    final long = since != null &&
        DateTime.now().difference(since) >= _holdThreshold;
    if (long) return; // il regardait : la carte reste en main

    final seat = held.by;
    final card = held.card;

    // La carte ne peut pas partir maintenant — mauvais moment, carte-dé
    // sans coup possible : on ouvre la carte, qui dit POURQUOI.
    if (!_controller.canPlayDeferred(seat, card)) {
      _openHandCard(slot);
      return;
    }

    if (card.needsTarget && card.entity == CardEntity.pawn) {
      final targets = _controller.deferredPawnTargets(seat, card);
      if (targets.isEmpty) {
        _openHandCard(slot);
        return;
      }
      _startTargeting(
        card: card,
        by: seat,
        targets: targets,
        pick: (p) => playDeferredCard(card, targetPawn: p),
      );
      return;
    }

    // Une carte qui vise un JOUEUR se choisit dans une liste : on ne
    // désigne pas un joueur sur le plateau, il n'y est pas.
    if (card.needsTarget && card.entity == CardEntity.player) {
      _openHandCard(slot);
      return;
    }

    playDeferredCard(card);
  }

  /// Referme la carte ouverte, s'il y en a une.
  @visibleForTesting
  void closeCard() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (_revealed != null) setState(() => _revealed = null);
  }

  /// La carte actuellement ouverte, pour les tests.
  @visibleForTesting
  ChanceCard? get revealedCard => _revealed?.card;

  /// Le siège dont on montre — et joue — la main de cartes différées.
  ///
  /// En mode ordinaire c'est le joueur du tour. En mode Rapide,
  /// `currentColor` ne désigne plus que « la dernière couleur à avoir
  /// agi » : le panneau montrerait alors la main d'un ordinateur, et les
  /// cartes de l'humain deviendraient injouables. On vise donc SON siège.
  PlayerColor get _deferredSeat =>
      _ruleFastMode ? (_humanSeat ?? _controller.currentColor)
                    : _controller.currentColor;

  /// [c] tient-il une carte différée jouable à cet instant précis ?
  /// Faux dès que les cases Chance sont éteintes : sa main est vide.
  bool _hasPlayableDeferred(PlayerColor c) => _controller.upgrades
      .handOf(c)
      .any((card) => _controller.canPlayDeferred(c, card));

  /// Laisse le dé affiché [_dicePause] avant de jouer le coup forcé. Le
  /// verrou est levé pendant l'attente : on voit le chiffre et le pion
  /// surligné, et aucune autre commande ne peut s'intercaler.
  void _scheduleAutoMove(Pawn p) {
    _autoMoveTimer?.cancel();
    // Améliorations : un joueur HUMAIN qui tient une carte différée jouable
    // À CET INSTANT doit pouvoir la jouer avant que le coup ne parte tout
    // seul — c'est le « et parfois après le lancer » de la spec. Sans ça,
    // une carte « Après » est injouable dès qu'un seul pion peut bouger :
    // le coup automatique la devance de 550 ms.
    //
    // On lui rend simplement la main : le pion reste surligné et cliquable.
    // L'ORDINATEUR n'est jamais retenu ici — il ne joue pas de cartes
    // différées, et le retenir figerait sa boucle.
    final actor = _controller.currentColor;
    if (_controller.upgrades.chanceEnabled &&
        !_isAiColor(actor) &&
        _hasPlayableDeferred(actor)) {
      setState(() {
        _autoNotice = 'Un seul coup possible : le pion ${p.id + 1} de '
            '${_frenchColor(p.color)}. Joue une carte chance si tu veux, '
            'puis clique le pion.';
      });
      return;
    }
    setState(() {
      _animating = true;
      // Le joueur doit SAVOIR pourquoi ça part sans lui : un seul coup
      // était possible, il n'y avait rien à choisir. Sans ce mot, un coup
      // automatique ressemble à un coup volé.
      _autoNotice = 'Un seul coup possible : le pion ${p.id + 1} de '
          '${_frenchColor(p.color)} part tout seul.';
    });
    _autoMoveTimer = _after(_pace(_dicePause), () {
      if (!mounted) return;
      _animating = false; // pour que _movePawn accepte le coup
      _movePawn(p);
    });
  }

  /// Où se trouve [p], dit en clair : base, flèche d'entrée, case du ring,
  /// couloir final ou maison. La flèche d'entrée est une case d'anneau
  /// comme les autres — elle n'a droit à son nom que pour la lisibilité de
  /// la trace, jamais dans la logique de jeu.
  String _whereIs(Pawn p) {
    switch (p.location) {
      case PawnLocation.base:
        return 'base(${p.position})';
      case PawnLocation.ring:
        final start = GameController.startIdx(p.color);
        return p.position == start
            ? 'FLÈCHE D\'ENTRÉE(${p.position})'
            : 'ring(${p.position})';
      case PawnLocation.homeColumn:
        return 'couloir(${p.position})';
      case PawnLocation.home:
        return 'maison';
    }
  }

  /// Journalise les options offertes par un 6 à la couleur [color].
  void _logSixOptions(PlayerColor color) {
    if (_controller.phase != TurnPhase.moving) {
      debugPrint('[six] ${color.name} fait 6 → aucun choix : le tour est '
          'déjà passé (troisième 6 de suite, ou aucun coup possible)');
      return;
    }
    final playable = _controller.movablePawns().toSet();
    final lines = _game.pawnsByColor[color]!
        .map((p) => '${playable.contains(p) ? '✔' : '✘'} '
            '${p.color.name}#${p.id} ${_whereIs(p)}')
        .join('  |  ');
    debugPrint('[six] ${color.name} fait 6 → '
        '${playable.length} pion(s) jouable(s) : $lines');
  }

  /// Message expliquant un coup joué automatiquement. `null` = rien à dire.
  String? _autoNotice;

  @visibleForTesting
  String? get autoNotice => _autoNotice;

  static String _frenchColor(PlayerColor c) => switch (c) {
        PlayerColor.blue => 'bleu',
        PlayerColor.red => 'rouge',
        PlayerColor.green => 'vert',
        PlayerColor.yellow => 'jaune',
      };

  /// Recale le sélecteur de couleur du Jeu manuel sur le joueur dont c'est
  /// réellement le tour. À appeler après TOUT changement de tour.
  void _syncManualPlayer() {
    final c = _controller.currentColor;
    if (_activeColors.contains(c)) _manualPlayer = c;
  }

  /// Cryptographically-strong RNG — backed by the OS entropy pool
  /// (`/dev/urandom` on Linux, `BCryptGenRandom` on Windows, Web Crypto
  /// on the browser). Unlike `Random()` (a deterministic XorShift seeded
  /// from the clock) this has no recoverable seed.
  ///
  /// ATTENTION : le tirage n'est PLUS uniforme sur 1..6. Il passe par
  /// [GameController.pickDiceValue], qui écarte les valeurs viseraient une
  /// case déjà tenue par un pion de la couleur. C'est un biais assumé et
  /// demandé ; l'entropie, elle, reste celle de l'OS.
  final math.Random _secureRng = math.Random.secure();

  void _rollDiceRandom() {
    if (_paused) return; // plateau gelé : aucune commande n'aboutit
    if (_ruleFastMode) {
      // Mode Rapide : on lance pour SON siège, quand on veut, sans attendre
      // que qui que ce soit ait fini. C'est tout l'objet du mode.
      final me = _humanSeat;
      if (me == null) return; // aucune couleur humaine en jeu
      if (_lockedFor(me)) return;
      if (_controller.seatOf(me).phase != TurnPhase.rolling) return;
      setState(() {
        _controller.runAsSeat(me,
            () => _controller.roll(_controller.pickDiceValueFor(me, _secureRng)));
      });
      return;
    }
    if (_animating) return; // verrou : une commande à la fois
    if (_isAiTurn) return;  // c'est à l'ordinateur de lancer, pas à nous
    if (_controller.phase != TurnPhase.rolling) return;
    _roll(_controller.pickDiceValueFor(_controller.currentColor, _secureRng));
    _scheduleAiTurn();
  }

  /// Le dé est-il cliquable maintenant ?
  ///
  /// Mode ordinaire : seulement quand c'est notre tour et que rien ne bouge.
  /// Mode Rapide : dès que NOTRE siège attend un lancer — on ne demande la
  /// permission à personne, c'est tout l'objet du mode.
  bool get _canRollNow {
    if (_paused) return false;
    if (_ruleFastMode) {
      final me = _humanSeat;
      if (me == null) return false;
      return _controller.seatOf(me).phase == TurnPhase.rolling &&
          !_lockedFor(me);
    }
    return _controller.phase == TurnPhase.rolling &&
        !_animating &&
        !_isAiTurn;
  }

  /// Les pions que l'HUMAIN peut jouer là, tout de suite. Ce sont eux qui
  /// portent le sélecteur et acceptent le clic ; ceux d'un ordinateur n'en
  /// ont jamais, il n'attend rien de nous.
  Set<Pawn> get _humanMovablePawns {
    if (_paused) return const {};
    if (_ruleFastMode) {
      final me = _humanSeat;
      if (me == null || _lockedFor(me)) return const {};
      if (_controller.seatOf(me).phase != TurnPhase.moving) return const {};
      late final Set<Pawn> movable;
      _controller.runAsSeat(
          me, () => movable = _controller.movablePawns().toSet());
      return movable;
    }
    if (_isAiTurn) return const {};
    return _controller.movablePawns().toSet();
  }

  /// La couleur que pilote l'humain en mode Rapide : la première de l'ordre
  /// des tours qui n'est pas confiée à un ordinateur. `null` quand les
  /// quatre sièges sont des ordinateurs — la partie se joue alors seule.
  PlayerColor? get _humanSeat {
    for (final c in _controller.turnOrder) {
      if (!_isAiColor(c) && !_controller.hasFinished(c)) return c;
    }
    return null;
  }

  // --- Mode contre ordinateur ------------------------------------------------

  /// Couleurs pilotées par l'IA : tout le monde sauf le premier joueur de
  /// l'ordre des tours (l'humain), et seulement quand la règle est ON.
  bool _isAiColor(PlayerColor c) => _aiSeats.contains(c);

  /// Vrai quand la main est à un ordinateur. Le plateau passe alors en
  /// LECTURE SEULE : ni sélecteur sur ses pions, ni dé cliquable. Sans ça
  /// le tour d'une IA est visuellement identique à un tour humain, et on
  /// croit que la partie attend un clic alors qu'elle joue toute seule.
  bool get _isAiTurn => _isAiColor(_controller.currentColor);

  /// Si le joueur courant est une IA, programme son lancer. Rappelée après
  /// chaque changement d'état susceptible de donner la main à une IA.
  /// Le délai laisse voir le dé et l'animation du coup précédent.
  void _scheduleAiTurn({Duration? delay}) {
    _aiTimer?.cancel();
    // En pause on n'arme rien : la reprise s'en chargera. Sans ça, une
    // minuterie naîtrait gelée et brouillerait le compte du temps restant.
    if (_paused) return;
    if (_aiSeats.isEmpty) return;
    if (_controller.phase == TurnPhase.gameOver) return;
    if (!_isAiColor(_controller.currentColor)) return;
    _aiTimer = _after(_pace(delay ?? _aiRollDelay), _playAiTurn);
  }

  // --- Mode Rapide : une boucle INDÉPENDANTE par couleur -------------------
  //
  // En mode ordinaire une seule boucle suit le joueur courant. Ici chaque
  // couleur d'ordinateur a la sienne : elle lance son dé, joue son pion et
  // se replanifie sans jamais consulter les autres. C'est ce qui fait qu'on
  // n'attend plus son tour.
  //
  // Dart n'ayant qu'un fil d'exécution, ces boucles s'ENTRELACENT au fil des
  // minuteries plutôt que de tourner vraiment en parallèle : chaque coup
  // reste atomique, et deux couleurs ne peuvent pas se marcher dessus au
  // milieu d'un déplacement.

  /// (Re)démarre les boucles de toutes les couleurs d'ordinateur.
  void _startFastLoops() {
    for (final c in _aiSeats) {
      _scheduleFastSeat(c);
    }
  }

  /// Programme le prochain geste de la couleur [c].
  void _scheduleFastSeat(PlayerColor c, {Duration? delay}) {
    _fastTimers.remove(c)?.cancel();
    if (_paused) return;
    if (!_ruleFastMode) return;
    if (!mounted) return;
    if (!_isAiColor(c)) return;
    if (_controller.phase == TurnPhase.gameOver) return;
    if (_controller.hasFinished(c)) return; // cette couleur a fini sa partie
    _fastTimers[c] = _after(
      _pace(delay ?? _aiRollDelay, ai: true),
      () => _playFastSeat(c),
    );
  }

  /// Un geste de la couleur [c] : lancer, puis coup s'il y en a un.
  void _playFastSeat(PlayerColor c) => _aiGuard('le tour rapide de ${c.name}',
      () {
        if (!mounted) return;
        if (!_ruleFastMode || !_isAiColor(c)) return;
        if (_controller.phase == TurnPhase.gameOver) return;
        if (_controller.hasFinished(c)) return;
        // Cette couleur anime encore son coup précédent : on repasse.
        if (_busySeats.contains(c)) {
          _scheduleFastSeat(c);
          return;
        }

        final seat = _controller.seatOf(c);
        if (seat.phase == TurnPhase.rolling) {
          setState(() {
            _controller.runAsSeat(c,
                () => _controller.roll(_controller.pickDiceValueFor(c, _secureRng)));
          });
          final rolled = _controller.seatOf(c).diceValue;
          debugPrint('[rapide] ${c.name} lance : $rolled');
          // Même trace qu'en mode ordinaire : le mode Rapide court-circuite
          // `_roll`, il faut donc la poser ici aussi.
          if (rolled == 6) {
            _controller.runAsSeat(c, () => _logSixOptions(c));
          }
        }

        // Le lancer a pu ne rien donner de jouable : le siège est revenu en
        // attente tout seul, on relance simplement sa boucle.
        if (_controller.seatOf(c).phase != TurnPhase.moving) {
          _scheduleFastSeat(c);
          return;
        }

        Pawn? choice;
        _controller.runAsSeat(c, () => choice = _controller.pickAiPawn());
        if (choice == null) {
          _scheduleFastSeat(c);
          return;
        }
        debugPrint('[rapide] ${c.name} joue ${choice!.color.name}#${choice!.id}');
        // _movePawn replanifie cette couleur à la fin de son trajet.
        _movePawn(choice!, seat: c);
      });

  /// Filet de sécurité, et il faut dire pourquoi il existe.
  ///
  /// Depuis que le plateau est en LECTURE SEULE pendant un tour
  /// d'ordinateur, un chemin qui oublierait de rappeler [_scheduleAiTurn]
  /// ne ralentit pas la partie : il la TUE. L'IA n'est pas relancée, et
  /// l'humain n'a plus ni dé ni pion cliquable pour la débloquer. C'est
  /// exactement ce qui arrivait après un Retour.
  ///
  /// Ce contrôle périodique rattrape ce cas au lieu de le laisser figer la
  /// partie. Il ne remplace PAS les appels explicites : s'il se déclenche,
  /// c'est qu'il en manque un quelque part — d'où la trace.
  void _startAiWatchdog() {
    _aiWatchdog?.cancel();
    int stuckTicks = 0;
    _aiWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      // Un plateau en pause n'est pas un plateau bloqué : ne rien secourir.
      if (_paused) return;
      // Un verrou levé sans AUCUN timer pour le rabaisser = animation
      // orpheline (exception en plein coup, timer perdu). L'ancien
      // watchdog était AVEUGLE à ce cas : il se contentait de repasser
      // tant que _animating était vrai, donc un verrou coincé figeait la
      // partie pour toujours. Trois contrôles de suite (~6 s, plus long
      // que n'importe quel trajet + pause) → on force le déverrouillage.
      if (_animating) {
        final somethingRuns = _travelTimers.values.any((t) => t.isActive) ||
            _travelEndTimers.values.any((t) => t.isActive) ||
            (_autoMoveTimer?.isActive ?? false);
        stuckTicks = somethingRuns ? 0 : stuckTicks + 1;
        if (stuckTicks >= 3) {
          debugPrint('[ai] verrou orphelin : _animating levé sans aucun '
              'timer actif depuis ~6 s — déverrouillage forcé');
          stuckTicks = 0;
          setState(_cancelAnimations);
          _scheduleAiTurn();
        }
        return;
      }
      stuckTicks = 0;
      if (!_aiMayAct) return;
      if ((_aiTimer?.isActive ?? false) ||
          (_autoMoveTimer?.isActive ?? false)) {
        return;
      }
      debugPrint('[ai] relance de secours : il manque un appel à '
          '_scheduleAiTurn sur le chemin qui vient de passer la main');
      _scheduleAiTurn();
    });
  }

  /// Dernier rempart du tour d'IA : si une exception éclate en plein coup,
  /// on nettoie tout et on PASSE LE TOUR plutôt que de figer la partie.
  /// Le joueur perd un coup d'ordinateur ; c'est infiniment mieux qu'un
  /// plateau mort.
  void _aiGuard(String stage, void Function() body) {
    try {
      body();
    } catch (e, st) {
      debugPrint('[ai] EXCEPTION pendant $stage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _cancelAnimations();
        if (_controller.phase == TurnPhase.moving) _controller.skipTurn();
      });
      _scheduleAiTurn();
    }
  }

  /// Vrai tant que l'IA courante peut continuer à agir. Les trois causes
  /// d'arrêt : le widget est parti, la règle a été coupée, ou la main n'est
  /// plus à une IA.
  bool get _aiMayAct =>
      mounted &&
      _controller.phase != TurnPhase.gameOver &&
      _isAiColor(_controller.currentColor);

  /// Premier temps du tour d'une IA : le lancer, et RIEN d'autre.
  ///
  /// Le coup est volontairement repoussé à [_playAiMove] : jouer dans la
  /// foulée du lancer ne laissait pas le temps de lire le dé — on voyait le
  /// pion partir avant le chiffre. Le seul cas où l'on ne programme rien
  /// est celui où [_roll] a déjà posé un coup automatique (un unique pion
  /// jouable) : il a sa propre pause et rendra la main tout seul.
  void _playAiTurn() => _aiGuard('le lancer', () {
        if (!mounted) return;
        if (_animating) {
          _scheduleAiTurn(); // le plateau bouge encore, on repasse plus tard
          return;
        }
        if (!_aiMayAct) return;
        if (_controller.phase != TurnPhase.rolling) {
          _playAiMove();
          return;
        }
        final who = _controller.currentColor.name;
        // Un ordinateur joue ses cartes comme un joueur : s'il en tient une
        // de bonne, il la pose AVANT de lancer. Sans cela sa main saturait
        // et tout tirage différé suivant était perdu.
        if (_playAiDeferredIfAny()) return;
        final v =
            _controller.pickDiceValueFor(_controller.currentColor, _secureRng);
        _roll(v);
        debugPrint('[ai] $who lance : $v'
            '${_controller.phase == TurnPhase.moving ? '' : ' — aucun coup, la main passe'}');
        if (_animating) return; // coup automatique déjà programmé par _roll
        if (_controller.phase == TurnPhase.moving) {
          _aiTimer = _after(_pace(_aiMoveDelay), _playAiMove);
        } else {
          // Le lancer n'a rien donné et a passé la main : au suivant.
          _scheduleAiTurn();
        }
      });

  /// Second temps : l'IA choisit son pion et le joue. Le coup passe par
  /// [_movePawn] — donc par le moteur, jamais par l'animation.
  void _playAiMove() => _aiGuard('le coup', () {
        if (!mounted) return;
        if (_animating) {
          _scheduleAiTurn();
          return;
        }
        if (!_aiMayAct) return;
        if (_controller.phase == TurnPhase.moving) {
          final choice = _controller.pickAiPawn();
          if (choice != null) {
            debugPrint('[ai] ${_controller.currentColor.name} joue '
                '${choice.color.name}#${choice.id} '
                '(${choice.location.name}:${choice.position}, '
                'dé ${_controller.diceValue})');
            _movePawn(choice);
            return; // _movePawn replanifie le tour suivant
          }
        }
        _scheduleAiTurn();
      });

  void _rollDiceManual(PlayerColor player, int value) {
    _roll(value, forPlayer: player);
    // Ce lancer peut passer la main à un ordinateur : sans cet appel il ne
    // repartirait jamais, et le plateau étant en lecture seule pendant son
    // tour, la partie serait définitivement figée.
    _scheduleAiTurn();
  }

  /// Joue le pion [p]. En mode Rapide, [seat] dit AU NOM DE QUI — chaque
  /// couleur ayant son propre tour, on ne peut plus le déduire d'un
  /// « joueur courant » qui n'ordonne plus rien.
  void _movePawn(Pawn p, {PlayerColor? seat}) {
    if (_paused) return; // plateau gelé
    final actor = _ruleFastMode ? (seat ?? p.color) : _controller.currentColor;
    // Verrou anti-bug : double clic sur un pion, clic pendant l'animation,
    // deux commandes simultanées → une seule est acceptée. Par couleur en
    // mode Rapide, global sinon.
    if (_lockedFor(actor)) return;
    if (_ruleFastMode && _controller.seatOf(actor).phase != TurnPhase.moving) {
      return;
    }
    if (!_ruleFastMode && _controller.phase != TurnPhase.moving) return;
    final distance = _ruleFastMode
        ? _controller.seatOf(actor).diceValue
        : _controller.diceValue;
    final oldLoc = p.location;
    // Snapshot capture state to spawn explosions for any pawn that got
    // sent back to base by this move. Sauvegarde aussi la position exacte.
    final beforeLoc = {
      for (final pp in _game.allPawns)
        pp: PawnStep(pp.location, pp.position),
    };
    // Trajet case par case, calculé AVANT que le moteur n'applique le coup.
    // Une sortie de base est un saut unique, pas un parcours.
    late final List<PawnStep> path;
    _controller.runAsSeat(actor, () {
      path = _controller.pathFor(p, distance);
    });
    // Ce coup appartient-il à un ordinateur ? Lu AVANT que le moteur ne
    // passe la main : sinon le mode Accélérateur s'appliquerait selon le
    // joueur SUIVANT, et accélérerait le coup d'un humain.
    final aiMove = _isAiColor(actor);
    final stepDur = _pace(
        (oldLoc == PawnLocation.base) ? _baseExitDuration : _stepDuration,
        ai: aiMove);
    // Instant où l'attaquant est VISUELLEMENT sur sa case d'arrivée. Le
    // `Timer.periodic` ci-dessous retire `_travelStep` à son tick
    // `path.length - 1` ; un trajet d'une seule étape (sortie de base)
    // s'affiche tout de suite mais glisse encore pendant `stepDur`.
    final arrivalDur = stepDur * math.max(path.length - 1, 1);
    // Pions capturés par ce coup, détectés en comparant l'avant / l'après.
    final capturedNow = <Pawn>[];

    _travelTimers.remove(p)?.cancel();
    setState(() {
      // Ce pion REPART : s'il rembobinait encore un retour de capture, on
      // le coupe ici. Sinon il resterait dessiné à sa case de rembobinage
      // et semblerait reculer au lieu de sortir — un pion qui sort sur un 6
      // ne doit JAMAIS partir en arrière.
      _stopReturnTravel(p);
      _moveDuration[p] = stepDur; // lu par l'AnimatedPositioned du pion
      // L'état LOGIQUE est mis à jour AVANT l'animation : le moteur a déjà
      // décidé capture / tour supplémentaire / classement quand le pion
      // commence à glisser.
      _controller.runAsSeat(actor, () => _controller.movePawn(p));
      // Améliorations : le moteur a pu tirer une carte chance ou déclencher
      // un vortex pendant ce coup. On affiche l'annonce dans le panneau et
      // on la trace en console pour vérification en conditions réelles.
      final upgradeNotices = _controller.upgrades.takeNotices();
      for (final n in upgradeNotices) {
        debugPrint('[amélioration] $n');
      }
      if (upgradeNotices.isNotEmpty) {
        _autoNotice = upgradeNotices.join('\n');
      }
      // Pions capturés : on garde leur ancienne position visible pendant le trajet.
      capturedNow.addAll(_game.allPawns.where((pp) =>
          pp != p &&
          beforeLoc[pp]!.location != PawnLocation.base &&
          pp.location == PawnLocation.base));
      // Trace de diagnostic demandée : elle dit ce que la détection a
      // RÉELLEMENT vu, pour qu'on puisse confirmer en conditions réelles
      // qu'aucune animation ne part sans victime.
      if (capturedNow.isEmpty) {
        // Trois raisons possibles de ne rien manger, et la trace doit
        // dire LAQUELLE : la case était vide ou sûre, ou bien elle était
        // tenue par un BLOC — deux pions d'une même couleur, qu'un pion
        // seul ne déloge pas.
        final bloc = p.location == PawnLocation.ring
            ? _game.allPawns.where((o) =>
                o.color != p.color &&
                o.location == PawnLocation.ring &&
                o.position == p.position)
            : const <Pawn>[];
        final tenue = bloc.isNotEmpty;
        debugPrint('[capture] pas de capture : '
            '${p.color.name}#${p.id} arrive sur '
            '${p.location.name}:${p.position}, '
            '${tenue ? 'bloc adverse : ${bloc.map((o) => '${o.color.name}#${o.id}').join(' + ')}' : 'case vide ou sûre'}');
      } else {
        debugPrint('[capture] capture détectée : '
            '${capturedNow.map((c) => '${c.color.name}#${c.id} depuis '
                '${beforeLoc[c]!.location.name}:${beforeLoc[c]!.position}').join(' + ')} '
            'par ${p.color.name}#${p.id} sur '
            '${p.location.name}:${p.position}');
      }
      for (final cap in capturedNow) {
        _captureOverride[cap] = beforeLoc[cap]!;
        // Le pion capturé doit DISPARAÎTRE net à la fin de la pause, pas
        // glisser jusqu'à sa base : sans ça, l'AnimatedPositioned garde une
        // durée périmée d'un coup précédent et le pion traverse le plateau
        // en glissant — c'était le « il bouge » constaté à l'écran.
        _moveDuration[cap] = Duration.zero;
      }
      // Le déplacement peut passer la main : le sélecteur manuel suit.
      _syncManualPlayer();
      if (_ruleFastMode) {
        _busySeats.add(actor);
      } else {
        _animating = true;
      }
      // Le dé garde la couleur du pion — et son Yard continue de
      // clignoter — tant qu'il n'a pas fini de compter ses cases.
      _activeColorHold = p.color;
      // On force l'affichage sur la 1re case du trajet ; le pion glissera
      // ensuite de case en case jusqu'à sa position réelle.
      if (path.length > 1) _travelStep[p] = path.first;
      _hopSeq[p] = (_hopSeq[p] ?? 0) + 1;
      if (oldLoc == PawnLocation.base) {
        _baseExit.add(p);
      } else {
        _baseExit.remove(p);
      }
    });
    // LA SORTIE DE BASE a son propre son — la chaîne — et il REMPLACE le
    // pas : ce n'est pas un pas, c'est une entrée en scène, et le pion y
    // glisse au lieu de sauter. Les deux ensemble ne feraient qu'une
    // bouillie sur un même demi-seconde.
    if (oldLoc == PawnLocation.base) {
      _baseExitBeat();
    } else {
      _stepBeat();
    }
    // La sortie finie, le pion redevient un pion ordinaire.
    if (oldLoc == PawnLocation.base) {
      _after(stepDur, () {
        if (mounted && _baseExit.remove(p)) setState(() {});
      });
    }

    // Une étape par tick : le pion s'arrête visiblement sur chaque case.
    if (path.length > 1) {
      int idx = 0;
      _travelTimers[p] = _every(stepDur, () {
        if (!mounted) {
          _travelTimers.remove(p)?.cancel();
          return;
        }
        idx++;
        _stepBeat();
        setState(() {
          _hopSeq[p] = (_hopSeq[p] ?? 0) + 1;
          if (idx >= path.length - 1) {
            // Dernière case = position réelle du pion : on retire l'override.
            _travelStep.remove(p);
            _travelTimers.remove(p)?.cancel();
          } else {
            _travelStep[p] = path[idx];
          }
          // NOTE : on ne retire JAMAIS une capture ici. Le pion capturé
          // reste rigoureusement sur sa case pendant tout le trajet ; il ne
          // disparaît qu'après la pause de co-localisation, plus bas.
        });
      });
    }

    // Pause de co-localisation : elle ne démarre qu'une fois l'attaquant
    // VISUELLEMENT sur la case. Pendant `_captureHold`, les deux pions sont
    // affichés ensemble sur cette case — le capturé n'a toujours pas bougé.
    // Sans capture, il n'y a rien à montrer : la pause est nulle.
    final holdDur =
        capturedNow.isEmpty ? Duration.zero : _pace(_captureHold, ai: aiMove);
    final totalDur = arrivalDur + holdDur;

    // Libère le verrou une fois le trajet parcouru ET la pause écoulée,
    // puis rend la main à l'IA si c'est à son tour.
    _travelEndTimers.remove(p)?.cancel();
    _travelEndTimers[p] = _after(totalDur, () {
      if (!mounted) return;
      setState(() {
        if (_ruleFastMode) {
          _busySeats.remove(actor);
        } else {
          _animating = false;
        }
        // Le pion a-t-il été DÉPLACÉ après son arrivée — par un vortex ou
        // par une carte ? Si oui on le laisse un instant sur la case où le
        // dé l'avait posé, pour qu'on VOIE qu'il y est arrivé avant d'être
        // emporté. Sans cette pause, il semblait n'y être jamais passé.
        final displaced = path.isNotEmpty &&
            (p.location != path.last.location ||
                p.position != path.last.position);
        if (!displaced) {
          _travelStep.remove(p);
          _travelEndTimers.remove(p);
        }
      });
      // Le pion est arrivé — mais le dé RESTE sur sa couleur et son chiffre
      // encore [_diceReadHold]. C'est seulement après que la main passe
      // visuellement au joueur suivant, dé et Yard clignotant compris.
      _diceReadTimer?.cancel();
      _diceReadTimer = _after(_pace(_diceReadHold, ai: aiMove), () {
        if (!mounted) return;
        // Un autre trajet a pu commencer entre-temps : on ne lui vole pas
        // sa couleur.
        if (_activeColorHold != actor) return;
        setState(() => _activeColorHold = null);
      });
      // La pause de la case spéciale, puis le pion rejoint sa vraie place.
      if (path.isNotEmpty &&
          (p.location != path.last.location ||
              p.position != path.last.position)) {
        _travelEndTimers[p] =
            _after(_pace(_specialCellHold, ai: aiMove), () {
          if (!mounted) return;
          setState(() {
            _travelStep.remove(p);
            _travelEndTimers.remove(p);
          });
        });
      }
      // Le pion est arrivé sur sa case : si c'était une case Chance, la
      // carte s'OUVRE maintenant. L'ouvrir plus tôt cacherait le trajet.
      _openDrawnCardIfAny();
      // L'attaquant est arrivé et la pause est écoulée : les pions capturés
      // quittent MAINTENANT la case, en rembobinant leur parcours à
      // contre-sens jusqu'à leur flèche d'entrée puis dans leur base.
      for (final cap in capturedNow) {
        _startReturnTravel(cap);
      }
      // Mode Rapide : seule CETTE couleur reprend la main, les autres
      // mènent leur tour de leur côté.
      if (_ruleFastMode) {
        _scheduleFastSeat(actor);
      } else {
        _scheduleAiTurn();
      }
    });
    // Explosion de capture : au moment EXACT où le pion capturé s'efface.
    final captures = capturedNow;
    if (captures.isNotEmpty) {
      _explosionTimer?.cancel();
      _explosionTimer = _after(totalDur, () {
        if (!mounted) return;
        // LE CRI TOMBE ICI, avec l'explosion.
        //
        // Il partait jusque-là à la DÉTECTION de la capture, c'est-à-dire
        // au moment où le moteur la résout — soit une seconde avant qu'on
        // la voie. L'attaquant n'avait même pas commencé son trajet. On
        // entendait donc crier un pion encore bien vivant à l'écran.
        //
        // Un cri par victime, DÉCALÉS de 130 ms : un même coup peut en
        // renvoyer deux (c'est la règle depuis le bloc), et deux fois le
        // même fichier au même instant ne fait pas deux cris — cela
        // double l'amplitude d'un son qui frôle déjà le maximum, donc
        // cela sature.
        for (var i = 0; i < captures.length; i++) {
          if (i == 0) {
            _captureBeat();
          } else {
            _after(Duration(milliseconds: 130 * i), _captureBeat);
          }
        }
        setState(() {
          for (final cap in captures) {
            final fx = ExplosionFx(
              colorRgb: _colorOfPawn(cap.color),
              targetPawn: p,
              vsync: this,
            )..start();
            _explosions.add(fx);
            fx.controller.addStatusListener((s) {
              if (s == AnimationStatus.completed && mounted) {
                setState(() {
                  _explosions.remove(fx);
                  fx.controller.dispose();
                });
              }
            });
          }
        });
      });
    }
  }

  /// Retour du pion [cap] qui vient d'être capturé : il rembobine son
  /// parcours à CONTRE-SENS depuis la case où il s'est fait manger jusqu'à
  /// sa flèche d'entrée, puis rentre dans sa base.
  ///
  /// Le moteur a déjà remis le pion en base ; c'est `_captureOverride` qui
  /// tient sa position VISUELLE, case après case, jusqu'à ce qu'on la
  /// retire — le pion se retrouve alors dessiné à sa vraie place, la base,
  /// exactement là où le rembobinage l'a mené. La transition est invisible.
  ///
  /// Purement décoratif : le verrou est déjà levé et la main déjà passée,
  /// donc ce retour n'empêche personne de jouer pendant qu'il se déroule.
  void _startReturnTravel(Pawn cap) {
    final from = _captureOverride[cap];
    // Le rembobinage n'existe QUE pour un pion capturé, donc renvoyé en
    // base par un adversaire. Toute autre situation (et notamment un pion
    // qui SORT de sa base sur un 6) n'en déclenche jamais.
    if (from == null || cap.location != PawnLocation.base) return;
    final path = _controller.returnPathFor(cap.color, from, cap.position);
    if (path.length < 2) {
      setState(() => _captureOverride.remove(cap));
      return;
    }
    // Le rembobinage ne doit JAMAIS survivre à la capture qui l'a causé :
    // un pion mangé loin de sa flèche remontait jusqu'à 51 cases, soit
    // près de 3 s, pendant lesquelles il glissait seul à l'écran bien
    // après le coup — on croyait voir une capture sans adversaire.
    // On borne donc la durée TOTALE et on resserre le pas si besoin.
    final steps = math.max(path.length, 1);
    final stepDur = Duration(
      microseconds: math.min(
        _returnStep.inMicroseconds,
        _returnBudget.inMicroseconds ~/ steps,
      ),
    );
    setState(() {
      // Le pion glisse d'une case à l'autre au rythme du rembobinage.
      _moveDuration[cap] = stepDur;
      _captureOverride[cap] = path.first;
    });
    int i = 0;
    _returnTimers[cap] = _every(stepDur, () {
      // Le pion est ressorti de sa base entre-temps : son trajet normal
      // reprend la main, on s'efface immédiatement.
      if (!mounted || cap.location != PawnLocation.base) {
        _returnTimers.remove(cap)?.cancel();
        if (mounted) setState(() => _captureOverride.remove(cap));
        return;
      }
      i++;
      setState(() {
        if (i >= path.length - 1) {
          // Dernière étape = la base, sa position réelle : on retire
          // l'override plutôt que de l'y poser, c'est le même point.
          _captureOverride.remove(cap);
          _returnTimers.remove(cap)?.cancel();
        } else {
          _captureOverride[cap] = path[i];
        }
      });
    });
  }

  /// Coupe net le rembobinage de [p] s'il en avait un en vol, et efface sa
  /// position visuelle de secours. Appelé dès que le pion REPART : sans ça
  /// il serait encore dessiné à sa case de rembobinage et donnerait
  /// l'impression de reculer au lieu de sortir de sa base.
  void _stopReturnTravel(Pawn p) {
    _returnTimers.remove(p)?.cancel();
    _captureOverride.remove(p);
  }

  Color _colorOfPawn(PlayerColor c) {
    switch (c) {
      case PlayerColor.yellow: return const Color(0xFFE6B800);
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
    }
  }

  /// Manual setup helper: force EXACTLY [targetCount] of [_manualPlayer]'s
  /// pawns into the **home** (center). Bi-directional:
  ///   - If current_in_home < target: pull pawns IN, taking the MOST
  ///     advanced ones first (homeColumn near home → ring near home →
  ///     base last).
  ///   - If current_in_home > target: push pawns OUT back to their base
  ///     slot (lowest pawn-id first).
  void _fillManualHome(int targetCount) {
    _controller.pushHistory(
        '${_manualPlayer.name} · $targetCount pion(s) maison');
    setState(() {
      final pawns = _game.pawnsByColor[_manualPlayer]!;
      final inHome = pawns
          .where((p) => p.location == PawnLocation.home)
          .toList();
      final outside = pawns
          .where((p) => p.location != PawnLocation.home)
          .toList();
      final delta = targetCount - inHome.length;
      if (delta > 0) {
        // ADD: pull `delta` pawns INTO home (most-advanced first).
        outside.sort((a, b) =>
            _progressOf(b).compareTo(_progressOf(a)));
        for (int i = 0; i < delta && i < outside.length; i++) {
          outside[i].location = PawnLocation.home;
          outside[i].position = 0;
        }
      } else if (delta < 0) {
        // REMOVE: send `-delta` pawns from home back to their base slot.
        inHome.sort((a, b) => a.id.compareTo(b.id));
        final toRemove = -delta;
        for (int i = 0; i < toRemove && i < inHome.length; i++) {
          inHome[i].location = PawnLocation.base;
          inHome[i].position = inHome[i].id;
        }
      }
      // L'éditeur manuel a déplacé des pions sans passer par movePawn :
      // on recalcule le classement complet (rangs, gagnant, fin de partie).
      _controller.recomputeStandings();
    });
  }

  /// Progress score (lower = closer to base, higher = closer to home).
  int _progressOf(Pawn p) {
    switch (p.location) {
      case PawnLocation.base:
        return 0;
      case PawnLocation.ring:
        final start = GameController.startIdx(p.color);
        return (p.position - start + GameController.ringSize) %
            GameController.ringSize;
      case PawnLocation.homeColumn:
        return GameController.ringSize + p.position;
      case PawnLocation.home:
        return GameController.totalStepsToHome;
    }
  }

  /// Pawn descriptor shown in the "Détails" cursor tooltip.
  /// Same string we used to print in the right-panel subtitle.
  String _pawnInfo(Pawn p) {
    final animIdx = _pawnAnimIdx[p];
    String pos;
    switch (p.location) {
      case PawnLocation.base:        pos = 'base #${p.position}';        break;
      case PawnLocation.ring:        pos = 'ring #${p.position}';        break;
      case PawnLocation.homeColumn:  pos = 'home column #${p.position}'; break;
      case PawnLocation.home:        pos = 'home';                       break;
    }
    return 'Pion ${p.color.name} #${p.id} · idle anim #$animIdx · $pos';
  }

  /// Bouton « Retour » : annule la dernière action (lancer + déplacement
  /// joué avec, ou édition manuelle) et remet le plateau tel qu'il était
  /// avant. Chaque pression remonte d'un coup de plus.
  ///
  /// Si le rembobinage retombe sur le tour d'une couleur IA, celle-ci est
  /// replanifiée avec [_aiResumeDelay] — un délai long exprès, pour qu'on
  /// puisse enchaîner plusieurs Retour sans qu'elle ne reparte entre deux
  /// clics (chaque appui annule le timer avant de le reposer).
  ///
  /// Elle l'était AUTREFOIS pas du tout, au motif qu'elle rejouerait
  /// aussitôt le coup annulé. Mais depuis que le plateau est en lecture
  /// seule pendant un tour d'ordinateur, ne pas la replanifier fige la
  /// partie pour de bon : plus d'IA, et plus de dé cliquable pour la
  /// relancer. Et l'IA ne « rejoue » rien : elle relance le dé, donc tire
  /// une nouvelle valeur.
  void _stepBack() {
    if (_paused) return;
    if (_anyBusy) return;
    if (_controller.undoDepth == 0) return;
    _cancelAnimations();
    setState(() {
      _controller.stepBack();
      // Les pions doivent réapparaître à leur ancienne place SANS glisser :
      // un retour arrière n'est pas un coup.
      _moveDuration.clear();
      _syncManualPlayer();
      _manualValue =
          _controller.diceValue > 0 ? _controller.diceValue : _manualValue;
    });
    _scheduleAiTurn(delay: _aiResumeDelay);
  }

  /// Coupe tout ce qui est en vol : trajet d'un pion, coup automatique en
  /// attente, tour d'IA programmé. Indispensable avant de rembobiner la
  /// partie — sinon un timer d'une position abandonnée retomberait dessus.
  void _cancelAnimations() {
    _aiTimer?.cancel();
    for (final t in _travelTimers.values) {
      t.cancel();
    }
    _travelTimers.clear();
    _autoMoveTimer?.cancel();
    for (final t in _travelEndTimers.values) {
      t.cancel();
    }
    _travelEndTimers.clear();
    for (final t in _fastTimers.values) {
      t.cancel();
    }
    _fastTimers.clear();
    _busySeats.clear();
    _explosionTimer?.cancel();
    _diceReadTimer?.cancel();
    _diceThrowTimer?.cancel();
    _diceRolling = false;
    for (final t in _returnTimers.values) {
      t.cancel();
    }
    _returnTimers.clear();
    _travelStep.clear();
    _baseExit.clear();
    _activeColorHold = null;
    _captureOverride.clear();
    _animating = false;
  }

  /// Bouton « Rejouer » : rétablit l'action qu'on vient d'annuler. Chaque
  /// pression redescend d'un coup. Jouer un nouveau coup vide la pile de
  /// rétablissement — on ne rejoue pas une branche abandonnée.
  void _stepForward() {
    if (_paused) return;
    if (_anyBusy) return;
    if (_controller.redoDepth == 0) return;
    _cancelAnimations();
    setState(() {
      _controller.stepForward();
      _moveDuration.clear();
      _syncManualPlayer();
      _manualValue =
          _controller.diceValue > 0 ? _controller.diceValue : _manualValue;
    });
    _scheduleAiTurn(delay: _aiResumeDelay);
  }

  void _endTurn() {
    // Changement de joueur pendant une animation : interdit.
    if (_paused) return;
    if (_anyBusy) return;
    setState(() {
      _controller.skipTurn();
    });
    _scheduleAiTurn();
  }

  void _confirmRestart(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redémarrer le jeu ?'),
        content: const Text('Tous les pions retourneront dans leur base.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Redémarrer'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        _cancelAnimations();
        setState(() {
          _animating = false;
          _controller.reset();
          _initialDiceFace = math.Random().nextInt(6) + 1;
          if (_ruleStartWith1TokenOut) _applyRuleStartWith1TokenOut();
        });
        _scheduleAiTurn();
      }
    });
  }

  /// Hover callbacks — only active when [_showDetails] is on.
  void _onPawnHover(Pawn? p) {
    if (!_showDetails) return;
    if (p == null) {
      setState(() => _hoverInfo = null);
      return;
    }
    final animIdx = _pawnAnimIdx[p];
    String pos;
    switch (p.location) {
      case PawnLocation.base:        pos = 'base #${p.position}';        break;
      case PawnLocation.ring:        pos = 'ring #${p.position}';        break;
      case PawnLocation.homeColumn:  pos = 'home column #${p.position}'; break;
      case PawnLocation.home:        pos = 'home';                       break;
    }
    setState(() {
      _hoverInfo =
          'Pion ${p.color.name} #${p.id} · idle anim #$animIdx · $pos';
    });
  }

  void _onDiceHover(bool hovering) {
    if (!_showDetails) return;
    if (!hovering) {
      setState(() => _hoverInfo = null);
      return;
    }
    final color = _activeColor;
    setState(() {
      _hoverInfo = 'Dé ${color.name} · valeur $_shownDice';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      // Le décor et le logo, pas un fond vide en anglais.
      return LoadingScreen(
        status: _loadingStatus,
        background: widget.setup.background,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1A2541),
      // Le décor derrière le plateau : image du Studio si elle existe,
      // dégradé sinon. Le plateau est posé PAR-DESSUS — c'est ce qui lui
      // donne l'air de flotter sur le fond plutôt que d'y être collé.
      body: AppBackground.board.wrap(
        config: widget.setup.background,
        SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight.isFinite ? c.maxHeight : 800.0;
            final w = c.maxWidth.isFinite ? c.maxWidth : 1200.0;
            // Narrow = phone-ish (folded foldable, portrait, ...).
            // Below this threshold, stack board on top + panel below.
            // Above, side-by-side (current desktop layout).
            final isNarrow = w < 700;
            // Command center: ~39 % of the page width (was 30 %, +30 %).
            // On very narrow screens (folded phones), shrink the floor
            // proportionally so we don't end up with min > max in clamp().
            final panelMax = w * 0.55;
            final panelMin = math.min(280.0, panelMax);
            final showPanel = widget.showPanel;
            // Le retour au menu est posé PAR-DESSUS, en haut à droite de
            // la zone du plateau : il ne prend donc aucune hauteur, et se
            // trouve au même endroit en portrait comme en paysage.
            const barH = 0.0;
            final panelWidth = (!showPanel || _panelCollapsed)
                ? 0.0
                : (w * 0.39).clamp(panelMin, panelMax);
            // La poignée à chevron mange sa propre largeur — mais seulement
            // si elle existe : sans panneau, tout l'espace revient au
            // plateau.
            final handleWidth = showPanel ? _PanelHandle.width : 0.0;
            final boardArea = isNarrow
                ? w
                : (w - panelWidth - handleWidth).clamp(120.0, w);
            // 15 px top + 15 px bottom breathing room around the board.
            // Une marge tout autour du plateau : sans elle il touche les
            // bords et le décor ne se voit plus derrière lui.
            //
            // Sur téléphone la marge se paie cher : le plateau est carré et
            // borné par la LARGEUR, donc chaque pixel de marge horizontale
            // est un pixel retiré aux quinze cases. On la réduit de moitié
            // là où elle coûte, on la garde entière sur grand écran où elle
            // ne coûte rien.
            final boardMarginV = isNarrow ? 8.0 : 14.0;
            final boardMarginH = isNarrow ? 7.0 : 14.0;
            final maxBoardSquare = isNarrow
                // Sans panneau — le mode « Jouer » du téléphone — le plateau
                // prend toute la hauteur qu'il peut. Avec panneau, il lui en
                // laisse les deux tiers.
                ? math.min(
                    w - 2 * boardMarginH,
                    showPanel ? h * 0.6 : h - 2 * boardMarginV - barH)
                : (h - 2 * boardMarginV - barH)
                    .clamp(0.0, boardArea - 2 * boardMarginH);
            final boardSide =
                _boardWidthOverride?.clamp(120.0, maxBoardSquare) ??
                    maxBoardSquare;

            final boardWidget = SizedBox(
              width: boardArea,
              height: isNarrow ? boardSide + 2 * boardMarginV : h - barH,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: boardMarginV),
                child: Center(
                  child: SizedBox(
                    width: boardSide,
                    height: boardSide,
                    child: Stack(
                      // Même raison : ce qui déborde du plateau par le haut
                      // doit rester visible.
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: BoardView(
                      players: _activePlayers,
                      game: _game,
                      showVortexCells: _controller.upgrades.vortexEnabled,
                      showChanceCells: _controller.upgrades.chanceEnabled,
                      deferredHands: {
                        for (final p in _activePlayers)
                          p.color: _controller.upgrades.handOf(p.color),
                      },
                      invulnerablePawns: {
                        for (final p in _game.allPawns)
                          if (_controller.upgrades.isInvulnerable(p)) p,
                      },
                      twoDice: _twoDiceShown,
                      tappableCardSeat: _cardTapSeat,
                      onDeferredCardTap: _releaseHandCard,
                      onDeferredCardHold: _holdHandCard,
                      onDeferredCardRelease: () {
                        // Geste annulé : on oublie AUSSI l'instant du
                        // contact, sinon la levée suivante croirait à une
                        // touche et jouerait la carte.
                        _heldSince = null;
                        if (_heldCard != null) {
                          setState(() => _heldCard = null);
                        }
                      },
                      showRing: _showRing,
                      showGrid: _showGrid,
                      showCanvas: _showCanvas,
                      playerCount: _playerCount,
                      diceValue: _shownDice,
                      diceRolling: _diceRolling,
                      throwSeq: _throwSeq,
                      activeColor: _activeColor,
                      currentPlayerColor: _controller.currentColor,
                      paused: _paused,
                      canRollDice: _canRollNow,
                      // Aucun sélecteur, aucun pion cliquable tant que
                      // c'est un ordinateur qui joue : il n'attend rien.
                      movablePawns: _humanMovablePawns,
                      onRollDice: _rollDiceRandom,
                      onPawnTap: (p) => _movePawn(p),
                      targetPawns: _targeting?.targets ?? const [],
                      targetTint: _targeting == null
                          ? const Color(0xFFFFD54F)
                          : cardIdentity(_targeting!.card).color,
                      onTargetPick: _pickTarget,
                      pawnAsset: _pawnAsset,
                      pawnInfo: _pawnInfo,
                      onPawnHover: _onPawnHover,
                      onDiceHover: _onDiceHover,
                      showDetails: _showDetails,
                      moveDuration: _moveDuration,
                      travelStep: _travelStep,
                      hopSeq: _hopSeq,
                      baseExit: _baseExit,
                      captureOverride: _captureOverride,
                      explosions: _explosions,
                        )),
                        // La carte tirée s'OUVRE par-dessus le plateau :
                        // elle part de son dos et se retourne sur sa vraie
                        // face. Un clic la referme plus tôt.
                        // Une carte immédiate qui réclame une cible : le
                        // joueur désigne SON pion avant qu'elle n'agisse.
                        if (_pendingChoice != null)
                          Positioned.fill(
                            child: _facing(
                              _pendingChoice!.onPawn.color,
                              _HandCardOverlay(
                              key: ValueKey(
                                  'choice-${_pendingChoice!.card.id}'),
                              card: _pendingChoice!.card,
                              ownerLabel:
                                  _frenchColor(_pendingChoice!.onPawn.color),
                              size: boardSide,
                              playable: true,
                              pawnTargets: _controller.immediateTargets(
                                  _pendingChoice!.card,
                                  _pendingChoice!.onPawn),
                              playerTargets: const [],
                              phase: _controller.phase,
                              // Refermer sans choisir applique la carte au
                              // pion qui l'a déclenchée : l'effet a
                              // toujours lieu, on ne peut pas l'esquiver.
                              onClose: () => resolvePendingChoice(null),
                              onPlay: ({targetPawn, targetPlayer}) =>
                                  resolvePendingChoice(targetPawn),
                              defaultPawn: _pendingChoice!.onPawn,
                              onPickOnBoard: () {
                                final pending = _pendingChoice!;
                                setState(() => _pendingChoice = null);
                                _startTargeting(
                                  card: pending.card,
                                  by: pending.onPawn.color,
                                  targets: _controller.immediateTargets(
                                      pending.card, pending.onPawn),
                                  pick: (p) => setState(() {
                                    _controller.resolvePendingImmediate(
                                        chosen: p);
                                    _flushUpgradeNotices();
                                  }),
                                );
                              },
                            ),
                            ),
                          ),
                        // La carte que le joueur vient de RETOURNER dans
                        // sa base : il lit l'instruction et l'applique.
                        if (_handCard != null)
                          Positioned.fill(
                            child: _facing(
                              _handCard!.by,
                              _HandCardOverlay(
                              key: ValueKey('hand-${_handCard!.card.id}'),
                              card: _handCard!.card,
                              // « Bleu · carte 2 » : on retrouve le
                              // numéro peint sur le dos qu'on vient de
                              // toucher.
                              ownerLabel: '${_frenchColor(_handCard!.by)}'
                                  ' · carte ${_handCard!.slot + 1}',
                              size: boardSide,
                              playable: _controller.canPlayDeferred(
                                  _handCard!.by, _handCard!.card),
                              pawnTargets: _controller.deferredPawnTargets(
                                  _handCard!.by, _handCard!.card),
                              playerTargets: _controller.deferredPlayerTargets(
                                  _handCard!.by, _handCard!.card),
                              phase: _controller.phase,
                              onClose: closeHandCard,
                              onPlay: _playOpenedHandCard,
                              onPickOnBoard: () {
                                final open = _handCard!;
                                _startTargeting(
                                  card: open.card,
                                  by: open.by,
                                  targets: _controller.deferredPawnTargets(
                                      open.by, open.card),
                                  // La carte ouverte s'efface pour laisser
                                  // voir le plateau : on retient donc ICI
                                  // laquelle on joue, plutôt que de la
                                  // relire dans `_handCard`, qui est nul.
                                  pick: (p) => playDeferredCard(open.card,
                                      targetPawn: p),
                                );
                              },
                            ),
                            ),
                          ),
                        // La bannière de DÉSIGNATION : elle dit ce qu'on
                        // attend et permet d'y renoncer. Sans elle, le
                        // plateau se met à refuser les coups normaux sans
                        // que rien n'explique pourquoi.
                        if (_targeting != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: _TargetBanner(
                              card: _targeting!.card,
                              count: _targeting!.targets.length,
                              onCancel: cancelTargeting,
                            ),
                          ),
                        // La carte MAINTENUE : elle se montre à la table
                        // dans le sens de l'écran — c'est justement pour
                        // les autres qu'on la lève, pas pour soi.
                        if (_heldCard != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _HeldCard(
                                card: _heldCard!.card,
                                ownerLabel: _frenchColor(_heldCard!.by),
                                size: boardSide,
                              ),
                            ),
                          ),
                        if (_revealed != null)
                          Positioned.fill(
                            child: _facing(
                              _revealed!.by,
                              _CardReveal(
                              key: ValueKey(
                                  '${_revealed!.card.id}-${_revealed!.by.name}'),
                              card: _revealed!.card,
                              ownerLabel: _frenchColor(_revealed!.by),
                              onDismiss: closeCard,
                              size: boardSide,
                            ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );

            final panel = _ControlPanel(
                    showRing: _showRing,
                    onToggleRing: (v) => setState(() => _showRing = v),
                    showGrid: _showGrid,
                    onToggleGrid: (v) => setState(() => _showGrid = v),
                    showCanvas: _showCanvas,
                    onToggleCanvas: (v) =>
                        setState(() => _showCanvas = v),
                    showDetails: _showDetails,
                    onToggleDetails: (v) {
                      setState(() {
                        _showDetails = v;
                        if (!v) _hoverInfo = null;
                      });
                    },
                    hoverInfo: _hoverInfo,
                    boardWidthOverride: _boardWidthOverride,
                    onDeviceSize: (w) =>
                        setState(() => _boardWidthOverride = w),
                    manualPlayer: _manualPlayer,
                    onChangeManualPlayer: (c) {
                      setState(() {
                        _manualPlayer = c;
                        // Immediately switch the controller's current player
                        // so the blinking Yard moves to the new color.
                        final idx = _controller.turnOrder.indexOf(c);
                        if (idx >= 0) {
                          _controller.currentPlayerIdx = idx;
                          if (_controller.phase != TurnPhase.gameOver) {
                            _controller.phase = TurnPhase.rolling;
                            _controller.diceValue = 0;
                            _controller.consecutiveSixes = 0;
                          }
                        }
                      });
                    },
                    manualValue: _manualValue,
                    onChangeManualValue: (v) =>
                        setState(() => _manualValue = v),
                    onManualRoll: () =>
                        _rollDiceManual(_manualPlayer, _manualValue),
                    onFillManualHome: _fillManualHome,
                    onStepBack: _stepBack,
                    canStepBack:
                        _controller.undoDepth > 0 && !_animating,
                    stepBackLabel: _controller.lastUndoLabel,
                    onStepForward: _stepForward,
                    canStepForward:
                        _controller.redoDepth > 0 && !_animating,
                    stepForwardLabel: _controller.nextRedoLabel,
                    panelTab: _panelTab,
                    // « Système » : le panneau occupe tout l'écran.
                    fullWidth: !widget.showBoard,
                    onChangePanelTab: (t) =>
                        setState(() => _panelTab = t),
                    ruleStartWith1TokenOut: _ruleStartWith1TokenOut,
                    onToggleRuleStartWith1TokenOut: (v) {
                      setState(() {
                        _ruleStartWith1TokenOut = v;
                        // Don't retroactively change the running game;
                        // the rule applies at the next reset (or now
                        // if no pawn has moved yet — simple heuristic:
                        // apply if every pawn is still in base).
                        final allInBase = _game.allPawns.every(
                            (p) => p.location == PawnLocation.base);
                        if (v && allInBase) {
                          _applyRuleStartWith1TokenOut();
                        }
                      });
                    },
                    ruleTeamMode: _ruleTeamMode,
                    onToggleRuleTeamMode: (v) {
                      setState(() {
                        _ruleTeamMode = v;
                        _controller.teamMode = v;
                      });
                    },
                    autoNotice: _autoNotice,
                    paused: _paused,
                    onSetPaused: setPaused,
                    fastMode: _ruleFastMode,
                    onToggleFastMode: setFastMode,
                    vortexEnabled: _controller.upgrades.vortexEnabled,
                    onToggleVortex: setVortexEnabled,
                    chanceEnabled: _controller.upgrades.chanceEnabled,
                    onToggleChance: setChanceEnabled,
                    deferredHand:
                        _controller.upgrades.handOf(_deferredSeat),
                    canPlayDeferred: (c) =>
                        _controller.canPlayDeferred(_deferredSeat, c),
                    deferredPawnTargets: (c) =>
                        _controller.deferredPawnTargets(_deferredSeat, c),
                    deferredPlayerTargets: (c) =>
                        _controller.deferredPlayerTargets(_deferredSeat, c),
                    onPlayDeferred: playDeferredCard,
                    aiTurbo: _aiTurbo,
                    onToggleAiTurbo: (v) {
                      setState(() => _aiTurbo = v);
                      // Prise d'effet IMMÉDIATE, même au milieu d'un tour
                      // d'ordinateur : le prochain délai armé utilisera
                      // déjà le nouveau rythme.
                      if (_isAiColor(_controller.currentColor) &&
                          !_animating) {
                        _scheduleAiTurn();
                      }
                    },
                    aiDifficulty: _controller.aiDifficulty,
                    onChangeAiDifficulty: (d) =>
                        setState(() => _controller.aiDifficulty = d),
                    aiSeats: _aiSeats,
                    onSetAiSeats: (seats) {
                      _aiTimer?.cancel();
                      setState(() => _aiSeats
                        ..clear()
                        ..addAll(seats));
                      _scheduleAiTurn();
                    },
                    onApplyManualCard: applyManualCard,
                    ranking: _controller.ranking,
                    busy: _animating,
                    playerCount: _playerCount,
                    onChangePlayerCount: _onChangePlayerCount,
                    activePlayers: _activePlayers,
                    currentPlayer: _activePlayers[
                        _controller.currentPlayerIdx
                            .clamp(0, _activePlayers.length - 1)],
                    phase: _controller.phase,
                    diceValue: _controller.diceValue,
                    consecutiveSixes: _controller.consecutiveSixes,
                    winner: _controller.winner,
                    onRollDice: _rollDiceRandom,
                    onEndTurn: _endTurn,
                    onRestart: () => _confirmRestart(context),
                  );

            // Le retour au menu est posé AU-DESSUS du plateau, pas dessus :
            // sur le plateau il masquait un coin de base.
            final board = boardWidget;

            /// Le retour au menu, en haut à droite de la zone du plateau.
            /// Sur téléphone cette zone occupe toute la largeur : il tombe
            /// donc en haut à droite de l'écran, portrait compris.
            /// Un bouton rond de la barre du plateau. Les deux se
            /// ressemblent trait pour trait : même fond, même taille,
            /// même hauteur — l'un à gauche, l'autre à droite.
            Widget barButton({
              required Key key,
              required IconData icon,
              required String tip,
              required VoidCallback onTap,
              Color? fond,
            }) =>
                Tooltip(
                  message: tip,
                  child: Material(
                    color: fond ?? Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      key: key,
                      customBorder: const CircleBorder(),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Icon(icon, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                );

            Widget withHome(Widget layout) => Stack(
                    children: [
                      layout,
                      // LA PAUSE, à gauche — en face de la maison.
                      //
                      // Elle existait déjà, mais seulement dans le centre
                      // de commandes : en mode « Jouer » le panneau
                      // n'existe pas, et il n'y avait aucun moyen
                      // d'arrêter la partie.
                      Positioned(
                        top: 6,
                        left: 0,
                        width: widget.showBoard ? boardArea : w,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: barButton(
                              key: const Key('board-pause'),
                              icon: _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              tip: _paused ? 'Reprendre' : 'Mettre en pause',
                              // En pause, le bouton s'allume : c'est le
                              // seul repère quand tout le reste est figé.
                              fond: _paused
                                  ? const Color(0xE6D4AF37)
                                  : null,
                              onTap: () => setPaused(!_paused),
                            ),
                          ),
                        ),
                      ),
                      if (widget.onExit != null)
                      Positioned(
                        top: 6,
                        left: 0,
                        // Sans plateau, le bouton se cale sur toute la
                        // largeur de l'écran.
                        width: widget.showBoard ? boardArea : w,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: barButton(
                              key: const Key('board-home'),
                              icon: Icons.home_outlined,
                              tip: 'Revenir au menu',
                              onTap: () =>
                                  widget.onExit?.call(_currentSetup),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

            // ── Responsive root: stack on narrow screens, side-by-side
            //    on wide ones. ───────────────────────────────────────
            // « Système » : le panneau seul, plein écran. Aucun plateau,
            // donc rien à disposer à côté.
            if (!widget.showBoard) {
              return withHome(SizedBox(width: w, height: h, child: panel));
            }
            if (isNarrow) {
              // ── LES BANDES VIDES DU TÉLÉPHONE ──────────────────────
              //
              // Le plateau est CARRÉ et borné par la largeur : sur un
              // écran de téléphone il occupe 96 % de la largeur mais à
              // peine 44 % de la hauteur. Plus de la moitié de l'écran
              // reste vide au-dessus et au-dessous, et aucun réglage de
              // marge n'y changera rien — un carré ne s'étire pas.
              //
              // Ludo King remplit ces deux bandes avec les joueurs : ceux
              // d'en haut au-dessus, ceux d'en bas au-dessous, chacun avec
              // son dé. On fait pareil, et l'écran cesse d'être un plateau
              // posé dans du vide.
              final top = <Player>[
                for (final p in _activePlayers)
                  if (p.color == PlayerColor.red ||
                      p.color == PlayerColor.green)
                    p,
              ];
              final bottom = <Player>[
                for (final p in _activePlayers)
                  if (p.color == PlayerColor.blue ||
                      p.color == PlayerColor.yellow)
                    p,
              ];
              Widget strip(List<Player> seats, {required bool flip}) =>
                  _SeatStrip(
                    seats: seats,
                    current: _activeColor,
                    diceValue: _controller.diceValue,
                    flip: flip,
                    homeCount: {
                      for (final p in seats)
                        p.color: _controller.state.pawnsByColor[p.color]!
                            .where((x) => x.location == PawnLocation.home)
                            .length,
                    },
                  );

              if (!showPanel) {
                return withHome(Column(
                  children: [
                    // Les joueurs d'EN HAUT sont assis de l'autre côté :
                    // leur bandeau se lit retourné, comme leurs cartes.
                    Expanded(child: Center(child: strip(top, flip: true))),
                    board,
                    Expanded(child: Center(child: strip(bottom, flip: false))),
                  ],
                ));
              }
              return withHome(Column(
                children: [
                  board,
                  Expanded(child: panel),
                ],
              ));
            }
            return withHome(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                board,
                if (showPanel) ...[
                  _PanelHandle(
                    collapsed: _panelCollapsed,
                    height: h,
                    onTap: () =>
                        setState(() => _panelCollapsed = !_panelCollapsed),
                  ),
                  if (!_panelCollapsed)
                    SizedBox(
                      width: panelWidth,
                      height: h,
                      child: panel,
                    ),
                ],
              ],
            ));
          },
        ),
      ),
      ),
    );
  }
}

/// La poignée posée entre le plateau et le centre de commandes : un liseré
/// vertical portant un chevron. Un clic replie le panneau sur le côté, un
/// autre le rouvre. Le chevron pointe TOUJOURS vers l'endroit où le clic
/// va emmener le panneau.
class _PanelHandle extends StatelessWidget {
  const _PanelHandle({
    required this.collapsed,
    required this.height,
    required this.onTap,
  });

  final bool collapsed;
  final double height;
  final VoidCallback onTap;

  /// Assez large pour être visée à la souris, assez fine pour ne pas voler
  /// de place au plateau.
  static const double width = 18;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: const Key('panel-handle'),
          // opaque : le liseré tout entier est cliquable, pas seulement les
          // quelques pixels peints par le chevron.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Tooltip(
            message: collapsed
                ? 'Rouvrir le centre de commandes'
                : 'Replier le centre de commandes sur le côté',
            child: ColoredBox(
              color: cs.surfaceContainerHighest,
              child: Center(
                child: Icon(
                  collapsed ? Icons.chevron_left : Icons.chevron_right,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Right-side panel: command center. Two cards (Normal / Manual) on top of an
/// overlay-toggles card. The number of players (1-6) and board-width preset
/// (smartphone / foldable / tablet / web FHD) live on the header row.
class _ControlPanel extends StatelessWidget {
  // Overlays
  final bool showRing;
  final ValueChanged<bool> onToggleRing;
  final bool showGrid;
  final ValueChanged<bool> onToggleGrid;
  final bool showCanvas;
  final ValueChanged<bool> onToggleCanvas;
  final bool showDetails;
  final ValueChanged<bool> onToggleDetails;
  final String? hoverInfo;

  // Layout
  final int playerCount;
  final ValueChanged<int> onChangePlayerCount;
  final List<Player> activePlayers;
  final double? boardWidthOverride;
  final ValueChanged<double?> onDeviceSize;

  // Turn state (normal mode)
  final Player currentPlayer;
  final TurnPhase phase;
  final int diceValue;
  final int consecutiveSixes;
  final PlayerColor? winner;
  final VoidCallback onRollDice;
  final VoidCallback onEndTurn;

  // Restart
  final VoidCallback onRestart;

  // Manual mode
  final PlayerColor manualPlayer;
  final ValueChanged<PlayerColor> onChangeManualPlayer;
  final int manualValue;
  final ValueChanged<int> onChangeManualValue;
  /// Force N pawns of [manualPlayer] back into the base (1..4). Removes
  /// home pawns first, then the least-advanced.
  final ValueChanged<int> onFillManualHome;

  /// Bouton « Lancer » du Jeu manuel : joue [manualValue] pour
  /// [manualPlayer]. Choisir une valeur ne fait plus que la SÉLECTIONNER —
  /// c'est ce bouton, et lui seul, qui déclenche le lancer.
  final VoidCallback onManualRoll;

  /// Boutons « Retour » / « Rejouer » du bas de la carte Jeu manuel :
  /// annulent et rétablissent le dernier coup. Les libellés décrivent
  /// l'action concernée.
  final VoidCallback onStepBack;
  final bool canStepBack;
  final String? stepBackLabel;
  final VoidCallback onStepForward;
  final bool canStepForward;
  final String? stepForwardLabel;

  // Tab + persistent rules
  final String panelTab;

  /// Le panneau occupe-t-il TOUT l'écran ? En mode « Système » il n'a plus
  /// de plateau à côté : ses cartes s'étirent alors sur toute la largeur et
  /// deviennent illisibles. On les recentre dans une colonne de lecture.
  final bool fullWidth;
  final ValueChanged<String> onChangePanelTab;
  final bool ruleStartWith1TokenOut;
  final ValueChanged<bool> onToggleRuleStartWith1TokenOut;
  final bool ruleTeamMode;
  final ValueChanged<bool> onToggleRuleTeamMode;
  /// Sièges actuellement pilotés par l'IA (peut être vide, ou tous).
  final Set<PlayerColor> aiSeats;

  /// Remplace d'un bloc l'ensemble des sièges IA — utilisé aussi bien par
  /// les boutons de combinaison (4 H, 1 H + 3 IA…) que par les
  /// interrupteurs individuels H/IA de chaque siège.
  final ValueChanged<Set<PlayerColor>> onSetAiSeats;

  /// Pause générale du plateau.
  final bool paused;
  final ValueChanged<bool> onSetPaused;

  /// Message expliquant un coup joué automatiquement, ou `null`.
  final String? autoNotice;

  /// Mode Rapide — sans attente de tour.
  final bool fastMode;
  final ValueChanged<bool> onToggleFastMode;

  /// Améliorations LudoPoly : cases Vortex et cases Chance.
  final bool vortexEnabled;
  final ValueChanged<bool> onToggleVortex;
  final bool chanceEnabled;
  final ValueChanged<bool> onToggleChance;

  /// Les cartes différées que le joueur courant tient en main, et de quoi
  /// en jouer une.
  final List<ChanceCard> deferredHand;
  final bool Function(ChanceCard) canPlayDeferred;
  final List<Pawn> Function(ChanceCard) deferredPawnTargets;
  final List<PlayerColor> Function(ChanceCard) deferredPlayerTargets;
  final void Function(ChanceCard, {Pawn? targetPawn, PlayerColor? targetPlayer})
      onPlayDeferred;

  /// Mode Accélérateur : l'ordinateur joue deux fois plus vite.
  final bool aiTurbo;
  final ValueChanged<bool> onToggleAiTurbo;

  /// Niveau de jeu de l'ordinateur, un seul actif à la fois.
  final AiDifficulty aiDifficulty;
  final ValueChanged<AiDifficulty> onChangeAiDifficulty;

  /// Applique une carte Chance à la main : la carte, le joueur visé, et
  /// le pion visé pour les cartes immédiates.
  final void Function(ChanceCard card, PlayerColor player, int pawnId)
      onApplyManualCard;

  /// Ordre d'arrivée courant : 1er, 2e, 3e, 4e.
  final List<PlayerColor> ranking;

  /// Vrai pendant qu'un pion glisse : toutes les commandes sont gelées.
  final bool busy;

  const _ControlPanel({
    required this.showRing,
    required this.onToggleRing,
    required this.showGrid,
    required this.onToggleGrid,
    required this.showCanvas,
    required this.onToggleCanvas,
    required this.showDetails,
    required this.onToggleDetails,
    required this.hoverInfo,
    required this.playerCount,
    required this.onChangePlayerCount,
    required this.activePlayers,
    required this.boardWidthOverride,
    required this.onDeviceSize,
    required this.currentPlayer,
    required this.phase,
    required this.diceValue,
    required this.consecutiveSixes,
    required this.winner,
    required this.onRollDice,
    required this.onEndTurn,
    required this.onRestart,
    required this.manualPlayer,
    required this.onChangeManualPlayer,
    required this.manualValue,
    required this.onChangeManualValue,
    required this.onFillManualHome,
    required this.onManualRoll,
    required this.onStepBack,
    required this.canStepBack,
    required this.stepBackLabel,
    required this.onStepForward,
    required this.canStepForward,
    required this.stepForwardLabel,
    required this.panelTab,
    this.fullWidth = false,
    required this.onChangePanelTab,
    required this.ruleStartWith1TokenOut,
    required this.onToggleRuleStartWith1TokenOut,
    required this.ruleTeamMode,
    required this.onToggleRuleTeamMode,
    required this.aiSeats,
    required this.onSetAiSeats,
    this.autoNotice,
    required this.paused,
    required this.onSetPaused,
    required this.fastMode,
    required this.onToggleFastMode,
    required this.vortexEnabled,
    required this.onToggleVortex,
    required this.chanceEnabled,
    required this.onToggleChance,
    required this.deferredHand,
    required this.canPlayDeferred,
    required this.deferredPawnTargets,
    required this.deferredPlayerTargets,
    required this.onPlayDeferred,
    required this.aiTurbo,
    required this.onToggleAiTurbo,
    required this.aiDifficulty,
    required this.onChangeAiDifficulty,
    required this.onApplyManualCard,
    required this.ranking,
    required this.busy,
  });

  Color _playerColor(PlayerColor c) {
    switch (c) {
      case PlayerColor.yellow: return const Color(0xFFE6B800);
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
    }
  }

  String _phaseText() {
    switch (phase) {
      case TurnPhase.rolling:
        return 'En attente du lancer';
      case TurnPhase.moving:
        return 'Dé $diceValue — choisis un pion';
      case TurnPhase.gameOver:
        return 'Partie terminée';
    }
  }

  /// Device-size presets for the board width override.
  static const Map<String, ({IconData icon, double? width})> _devicePresets = {
    'Smartphone':   (icon: Icons.smartphone,    width: 360),
    'Foldable':     (icon: Icons.devices_fold,  width: 720),
    'Tablette':     (icon: Icons.tablet_mac,    width: 1024),
    'Web FHD':      (icon: Icons.desktop_windows, width: 1920),
  };

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        return Material(
          color: cs.surface,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // Plein écran, une carte étirée sur 1400 px est illisible :
              // on borne la colonne, comme le fait la page Options.
              constraints: BoxConstraints(
                  maxWidth: fullWidth ? 760 : double.infinity),
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Les trois pages du panneau ----
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'commandes',
                        label: Text('Commandes'),
                        icon: Icon(Icons.tune, size: 18),
                      ),
                      ButtonSegment(
                        value: 'rules',
                        label: Text('Règles'),
                        icon: Icon(Icons.rule, size: 18),
                      ),
                      ButtonSegment(
                        value: 'settings',
                        label: Text('Paramètres'),
                        icon: Icon(Icons.settings, size: 18),
                      ),
                    ],
                    selected: {panelTab},
                    onSelectionChanged: (s) => onChangePanelTab(s.first),
                    showSelectedIcon: false,
                  ),
                ),
                if (panelTab == 'rules') ...[
                  _SectionCard(
                    title: 'Règles persistantes',
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text(
                              'Démarrer avec 1 token sorti'),
                          subtitle: const Text(
                              'Au début de chaque partie, 1 pion de '
                              'chaque couleur est déjà sur sa case '
                              'départ.'),
                          value: ruleStartWith1TokenOut,
                          onChanged: onToggleRuleStartWith1TokenOut,
                        ),
                        SwitchListTile(
                          title: const Text('Jeu en équipe (2v2)'),
                          subtitle: const Text(
                              'Bleu + Vert vs Jaune + Rouge. '
                              "Pas de capture entre coéquipiers · "
                              "un joueur dont les 4 pions sont à la maison "
                              "joue avec ceux de son partenaire · victoire "
                              "= 8 pions au centre."),
                          value: ruleTeamMode,
                          onChanged: onToggleRuleTeamMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: 'Joueurs — Humain ou IA',
                    child: _PlayerSeatsCard(
                      activePlayers: activePlayers,
                      aiSeats: aiSeats,
                      onSetAiSeats: onSetAiSeats,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: "Niveau de l'ordinateur",
                    child: _AiDifficultyCard(
                      selected: aiDifficulty,
                      onChanged: onChangeAiDifficulty,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: 'Mode de partie',
                    child: _GameModeCard(
                      fastMode: fastMode,
                      onToggleFastMode: onToggleFastMode,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: 'Améliorations LudoPoly',
                    child: _UpgradesCard(
                      vortexEnabled: vortexEnabled,
                      onToggleVortex: onToggleVortex,
                      chanceEnabled: chanceEnabled,
                      onToggleChance: onToggleChance,
                    ),
                  ),
                ] else if (panelTab == 'settings') ...[
                  // ---- Onglet Settings : même mécanique que les Règles,
                  //      contenu à venir — les paramètres s'ajouteront ici,
                  //      chacun dans sa _SectionCard.
                  _SectionCard(
                    title: 'Paramètres',
                    child: Text(
                      'Aucun paramètre pour l\'instant.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ] else ...[
                  // ---- Améliorations : la main de cartes différées du
                  //      joueur courant. N'apparaît que si les cases
                  //      Chance sont allumées ET qu'il tient des cartes.
                  if (chanceEnabled && deferredHand.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Vos cartes chance',
                      child: _DeferredHandCard(
                        hand: deferredHand,
                        owner: currentPlayer.color,
                        canPlay: canPlayDeferred,
                        pawnTargets: deferredPawnTargets,
                        playerTargets: deferredPlayerTargets,
                        onPlay: onPlayDeferred,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                // ---- Setup card (left, half width) + nomenclature
                //      thumbnail (right, half width, hover-zoom) ----
                rowOuColonne(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _SectionCard(
                          title: 'Setup',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Nb joueurs',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(color: cs.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              SegmentedButton<int>(
                                segments: const [
                                  ButtonSegment(value: 1, label: Text('1')),
                                  ButtonSegment(value: 2, label: Text('2')),
                                  ButtonSegment(value: 3, label: Text('3')),
                                  ButtonSegment(value: 4, label: Text('4')),
                                  ButtonSegment(value: 5, label: Text('5')),
                                  ButtonSegment(value: 6, label: Text('6')),
                                ],
                                selected: {playerCount},
                                onSelectionChanged: (s) =>
                                    onChangePlayerCount(s.first),
                                showSelectedIcon: false,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text('Taille board',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: cs.onSurfaceVariant)),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: onRestart,
                                    icon: const Icon(Icons.restart_alt,
                                        size: 16),
                                    label: const Text('Redémarrer jeu'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: cs.error,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final entry
                                      in _devicePresets.entries)
                                    Tooltip(
                                      message:
                                          '${entry.key} (${entry.value.width!.toInt()}px)',
                                      child: IconButton.filledTonal(
                                        isSelected: boardWidthOverride ==
                                            entry.value.width,
                                        onPressed: () => onDeviceSize(
                                            entry.value.width),
                                        icon: Icon(entry.value.icon),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          children: [
                            // Fixed-aspect thumbnails (instead of Expanded
                            // inside a column) so the layout has a known
                            // intrinsic height — otherwise IntrinsicHeight
                            // or any size-query upstream crashes with
                            // 'hasSize is not true' on tighter constraints
                            // (esp. on Android).
                            AspectRatio(
                              aspectRatio: 1.6,
                              child: _HoverZoomImage(
                                asset:
                                    'Documentation/Board4_Nomenclature.png',
                              ),
                            ),
                            SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: 1.6,
                              child: _HoverZoomImage(
                                asset:
                                    'Documentation/Token_Nomenclature.png',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                // ---- Two side-by-side cards: Jeu normal / Jeu manuel ----
                // Trois cartes côte à côte tant qu'il y a la place ; en
                // dessous elles s'empilent. À l'étroit, « Jeu normal »
                // débordait — un septième de la largeur ne suffit pas à
                // « Tour : » et sa pastille de couleur.
                LayoutBuilder(builder: (context, c) {
                  final cards = <Widget>[
                    _normalCard(theme, cs),
                    _manualCard(theme, cs),
                    _SectionCard(
                      title: 'Cartes chance',
                      child: _ManualCardsCard(
                        player: manualPlayer,
                        onApply: onApplyManualCard,
                      ),
                    ),
                  ];
                  if (c.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final w in cards)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: w,
                          ),
                      ],
                    );
                  }
                  // Sans IntrinsicHeight : forcer les trois cartes à la
                  // même hauteur faisait déborder la plus chargée de
                  // quelques pixels dès que sa colonne rétrécissait.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: cards[0]),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: cards[1]),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: cards[2]),
                    ],
                  );
                }),

                const SizedBox(height: 12),

                // ---- Pause du plateau ----
                _SectionCard(
                  title: 'Plateau',
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: Icon(
                      paused ? Icons.play_arrow : Icons.pause,
                      color: paused ? cs.primary : cs.onSurfaceVariant,
                    ),
                    title: Text(paused ? 'Reprendre' : 'Pause'),
                    subtitle: Text(paused
                        ? 'Le plateau est gelé. La reprise repart exactement '
                            "où tout s'est arrêté."
                        : 'Fige tout : pions, dé, ordinateurs et minuteries.'),
                    trailing: paused
                        ? FilledButton.icon(
                            onPressed: () => onSetPaused(false),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Reprendre'),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => onSetPaused(true),
                            icon: const Icon(Icons.pause, size: 18),
                            label: const Text('Pause'),
                          ),
                  ),
                ),

                const SizedBox(height: 12),

                // ---- Mode Accélérateur IA ----
                _SectionCard(
                  title: 'Rythme de l\'ordinateur',
                  padding: EdgeInsets.zero,
                  child: SwitchListTile(
                    secondary: Icon(
                      Icons.bolt,
                      color: aiTurbo ? cs.primary : cs.outline,
                    ),
                    title: Row(
                      children: [
                        const Text('Mode Accélérateur IA'),
                        if (aiTurbo) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '⚡ ACTIF',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: const Text(
                        'Divise par deux les temps d\'attente des tours de '
                        'l\'ordinateur — lancer, choix du pion, déplacement. '
                        'Les tours humains gardent leur rythme.'),
                    value: aiTurbo,
                    onChanged: onToggleAiTurbo,
                  ),
                ),

                const SizedBox(height: 12),

                // ---- Overlays card (2 toggles per row) ----
                _SectionCard(
                  title: 'Overlays',
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      rowOuColonne(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Show ring'),
                              subtitle: const Text(
                                  'Indices des cases du ring'),
                              value: showRing,
                              onChanged: onToggleRing,
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Show grid 15×15'),
                              subtitle: const Text(
                                  'Indices 0..224 sur chaque case'),
                              value: showGrid,
                              onChanged: onToggleGrid,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                      rowOuColonne(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Show canvas'),
                              subtitle: const Text(
                                  'Bbox rouge autour du GIF de chaque pion'),
                              value: showCanvas,
                              onChanged: onToggleCanvas,
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Détails'),
                              subtitle: Text(
                                hoverInfo ?? 'Survole un pion ou le dé',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: showDetails,
                              onChanged: onToggleDetails,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ], // end of panelTab == 'commandes' branch
              ],
            ),
          ),
          ),
        ),
        );
      }),
    );
  }

  Widget _normalCard(ThemeData theme, ColorScheme cs) {
    return _SectionCard(
      title: 'Jeu normal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Tour :', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 6),
              Flexible(
                child: Chip(
                  label: Text(currentPlayer.name,
                      overflow: TextOverflow.ellipsis),
                  backgroundColor: _playerColor(currentPlayer.color),
                  labelStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _phaseText(),
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (consecutiveSixes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Série de 6 : $consecutiveSixes',
                  style: TextStyle(color: cs.tertiary, fontSize: 12)),
            ),
          // Coup joué sans le joueur : on lui dit pourquoi.
          if (autoNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(autoNotice!,
                        style: TextStyle(color: cs.primary, fontSize: 12)),
                  ),
                ],
              ),
            ),
          if (ranking.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < ranking.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(
                            i == 0
                                ? Icons.emoji_events
                                : Icons.workspace_premium,
                            size: 16,
                            color: i == 0 ? cs.tertiary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          // Expanded + ellipsis : sans ça la ligne du
                          // classement déborde du panneau dès que le nom de
                          // la couleur est long, et Flutter peint les rayures
                          // jaunes et noires par-dessus le panneau.
                          Expanded(
                            child: Text(
                              '${i + 1}${i == 0 ? 'er' : 'e'} · '
                              '${ranking[i].name}'
                              '${i == 0 ? ' gagne' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color:
                                    i == 0 ? cs.tertiary : cs.onSurfaceVariant,
                                fontWeight: i == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (phase != TurnPhase.gameOver)
                    Text(
                      'La partie continue pour les places suivantes.',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                          fontSize: 11),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // « Jeu normal » ne reçoit qu'un septième de la largeur du panneau
          // (flex 1 contre 3 et 3). Un bouton libre y empilait ses lettres à
          // la verticale : libellé court, une seule ligne, et coupure nette
          // plutôt qu'un retour à la ligne.
          SizedBox(
            height: 32,
            child: FilledButton(
              // Deux boutons s'appellent « Lancer » (ici et dans Jeu manuel) :
              // la cle les distingue sans ambiguite pour les tests.
              key: const Key('roll-normal'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed:
                  (phase == TurnPhase.rolling && !busy) ? onRollDice : null,
              child: const Text(
                'Lancer',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualCard(ThemeData theme, ColorScheme cs) {
    return _SectionCard(
      title: 'Jeu manuel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Haut : Couleur à gauche (verticale), Pions dans la Maison
          //     en haut à DROITE, à l'horizontale — empilés sur un
          //     téléphone, où deux colonnes ne tiennent pas. ───
          rowOuColonne(
            children: [
              // La colonne des couleurs ne prend que la largeur qu'il lui
              // faut : tout le reste va aux pions, qui en ont besoin pour
              // tenir sur une seule ligne.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Couleur',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final p in activePlayers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _ColorDot(
                        color: _playerColor(p.color),
                        selected: p.color == manualPlayer,
                        onTap: () => onChangeManualPlayer(p.color),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pions dans la Maison',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    // Wrap et non Row : horizontal par nature, mais il passe
                    // à la ligne au lieu de déborder si la carte rétrécit.
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (int n = 1; n <= 4; n++)
                          _MiniDiceButton(
                            value: n,
                            onTap: () => onFillManualHome(n),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ─── Milieu : Valeur dé, à l'horizontale et centrée ───
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Valeur dé',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (int v = 1; v <= 6; v++)
                    _MiniDiceButton(
                      value: v,
                      selected: v == manualValue,
                      onTap: () => onChangeManualValue(v),
                    ),
                ],
              ),
            ],
          ),
          // ─── Lancer : joue la couleur et la valeur choisies ───
          // Hauteur bridée et libellé sur UNE ligne : dans une colonne
          // étroite un bouton libre empile ses lettres à la verticale.
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              key: const Key('roll-manual'),
              icon: const Icon(Icons.casino, size: 16),
              label: const Text(
                'Lancer',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 13),
              ),
              onPressed:
                  (busy || phase == TurnPhase.gameOver) ? null : onManualRoll,
            ),
          ),
          // ─── Retour / Rejouer (undo / redo) — bas de carte ───
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: canStepBack
                      ? 'Annule : ${stepBackLabel ?? "le dernier coup"}'
                      : 'Rien à annuler',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Retour'),
                    onPressed: canStepBack ? onStepBack : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: canStepForward
                      ? 'Rejoue : ${stepForwardLabel ?? "le coup annulé"}'
                      : 'Rien à rejouer',
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.redo, size: 18),
                    label: const Text('Rejouer'),
                    onPressed: canStepForward ? onStepForward : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small color dot for the manual-mode color selector.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 3)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

/// Reusable section card with a small title above the body. Uses the ambient
/// Material 3 theme for surface/elevation/typography.
/// Configuration des sièges : chaque place de la partie est tenue par un
/// Humain ou par l'IA locale. Les boutons du haut posent d'un clic les
/// combinaisons classiques (4 H, 3 H + 1 IA, … 4 IA) ; les interrupteurs
/// du dessous règlent chaque siège individuellement. Les deux vues
/// commandent le même ensemble [aiSeats].
class _PlayerSeatsCard extends StatelessWidget {
  final List<Player> activePlayers;
  final Set<PlayerColor> aiSeats;
  final ValueChanged<Set<PlayerColor>> onSetAiSeats;

  const _PlayerSeatsCard({
    required this.activePlayers,
    required this.aiSeats,
    required this.onSetAiSeats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = activePlayers.length;
    final aiCount =
        activePlayers.where((p) => aiSeats.contains(p.color)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'IA locale : capture > maison > couloir > sortie > case sûre. '
          'Une partie 100 % IA se joue toute seule jusqu\'au classement.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // ── Les combinaisons, un bouton chacune ──
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (int ia = 0; ia <= n; ia++)
              ChoiceChip(
                label: Text(ia == 0
                    ? '$n H'
                    : (ia == n ? '$ia IA' : '${n - ia} H + $ia IA')),
                selected: aiCount == ia,
                onSelected: (_) {
                  // Les IA occupent les DERNIERS sièges : le 1er joueur
                  // reste humain tant qu'il reste au moins un humain.
                  onSetAiSeats({
                    for (final p in activePlayers.skip(n - ia)) p.color,
                  });
                },
              ),
          ],
        ),
        const Divider(height: 20),
        // ── Le détail, siège par siège ──
        for (final p in activePlayers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: _seatColor(p.color)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('H'),
                        icon: Icon(Icons.person, size: 14)),
                    ButtonSegment(
                        value: true,
                        label: Text('IA'),
                        icon: Icon(Icons.smart_toy, size: 14)),
                  ],
                  selected: {aiSeats.contains(p.color)},
                  onSelectionChanged: (sel) {
                    final next = Set<PlayerColor>.from(aiSeats);
                    sel.first ? next.add(p.color) : next.remove(p.color);
                    onSetAiSeats(next);
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static Color _seatColor(PlayerColor c) {
    switch (c) {
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
      case PlayerColor.yellow: return const Color(0xFFE6B800);
    }
  }
}

/// Modes de partie. Seul le mode ordinaire local existe aujourd'hui ; le
/// mode rapide (tous les joueurs jouent sans attendre leur tour) et le
/// multijoueur multi-appareils sont affichés mais VERROUILLÉS — leurs
/// boutons annoncent la suite sans prétendre qu'elle est jouable.
/// Les cinq niveaux de l'ordinateur, en boutons EXCLUSIFS : un seul actif.
///
/// L'ordre de la liste est celui de l'enum, du plus tendre au plus dur —
/// c'est [AiDifficulty] qui porte les libellés et les résumés, pour que le
/// texte affiché et le comportement réel ne puissent pas diverger.
class _AiDifficultyCard extends StatelessWidget {
  final AiDifficulty selected;
  final ValueChanged<AiDifficulty> onChanged;

  const _AiDifficultyCard({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final level in AiDifficulty.values)
              ChoiceChip(
                label: Text(level.label),
                selected: level == selected,
                onSelected: (_) => onChanged(level),
                showCheckmark: false,
                avatar: level == selected
                    ? Icon(Icons.check, size: 16, color: cs.onSecondaryContainer)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(selected.summary, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          'Le dé reste tiré dans la même urne pour tout le monde : un niveau '
          'élevé ne gagne pas avec de meilleurs dés, il gagne en ne se '
          'trompant pas.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

class _GameModeCard extends StatelessWidget {
  /// Mode Rapide — sans attente de tour.
  final bool fastMode;
  final ValueChanged<bool> onToggleFastMode;

  const _GameModeCard({
    required this.fastMode,
    required this.onToggleFastMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget lockedRow(IconData icon, String title, String sub) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium),
                    Text(sub,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: null,
                child: const Text('À venir'),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.play_circle, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ordinaire — tour par tour (local)',
                      style: theme.textTheme.bodyMedium),
                  Text(
                      'Les joueurs jouent chacun à leur tour, dans un '
                      'ordre fixe, sur cet appareil.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            fastMode
                ? OutlinedButton(
                    onPressed: () => onToggleFastMode(false),
                    child: const Text('Reprendre'),
                  )
                : FilledButton.tonal(
                    onPressed: null,
                    child: const Text('Actif'),
                  ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.bolt,
                  size: 16, color: fastMode ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rapide — sans attente de tour',
                        style: theme.textTheme.bodyMedium),
                    Text(
                        "Les couleurs ordinateur jouent en continu, chacune "
                        "de son côté, pendant que vous réfléchissez : vous "
                        "lancez votre dé quand vous voulez, sans jamais "
                        "patienter. Le classement reste complet — la partie "
                        "continue après le premier arrivé.",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: fastMode, onChanged: onToggleFastMode),
            ],
          ),
        ),
        lockedRow(
            Icons.wifi,
            'Multijoueur — plusieurs appareils',
            'Mêmes combinaisons H / IA, réparties sur plusieurs '
                'appareils.'),
      ],
    );
  }
}

/// La carte tirée sur une case Chance, qui S'OUVRE au centre du plateau.
///
/// Elle part de son DOS — le même que celui des cartes posées dans les
/// bases — puis pivote sur elle-même pour montrer sa vraie face et son
/// instruction. Un clic n'importe où la referme avant la fin.
/// La carte qu'on MAINTIENT : montrée en grand, au centre, tant que le
/// doigt reste posé dessus.
///
/// Pas de bouton, pas de minuterie, rien à fermer : elle vit exactement le
/// temps du geste. Et elle se présente dans le sens de l'ÉCRAN, jamais
/// retournée vers son propriétaire — c'est pour que les autres la voient
/// qu'on la lève.
class _HeldCard extends StatelessWidget {
  const _HeldCard({
    required this.card,
    required this.ownerLabel,
    required this.size,
  });

  final ChanceCard card;
  final String ownerLabel;

  /// Côté du plateau : la carte s'y dimensionne.
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = (size * 0.34).clamp(150.0, 260.0);
    return ColoredBox(
      color: const Color(0x99000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Carte de $ownerLabel',
              style: const TextStyle(
                color: Color(0xFFF3E3A3),
                fontSize: 13,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: w,
              height: w * 1.55,
              child: CardFace(card: card),
            ),
            const SizedBox(height: 10),
            const Text(
              'Relâchez pour la reposer',
              style: TextStyle(color: Color(0x99F3E3A3), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardReveal extends StatefulWidget {
  final ChanceCard card;
  final String ownerLabel;
  final VoidCallback onDismiss;

  /// Côté du plateau : la carte s'y dimensionne.
  final double size;

  const _CardReveal({
    super.key,
    required this.card,
    required this.ownerLabel,
    required this.onDismiss,
    required this.size,
  });

  @override
  State<_CardReveal> createState() => _CardRevealState();
}

class _CardRevealState extends State<_CardReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = (widget.size * 0.34).clamp(150.0, 260.0);
    final h = w * 1.55;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDismiss,
      child: ColoredBox(
        color: const Color(0xAA000000),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Carte chance — ${widget.ownerLabel}',
                style: const TextStyle(
                  color: Color(0xFFF3E3A3),
                  fontSize: 13,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedBuilder(
                animation: _flip,
                builder: (context, _) {
                  // Un demi-tour : de face cachée à face visible. Au-delà
                  // du quart de tour on bascule sur la face, et on la
                  // contre-pivote pour qu'elle ne s'affiche pas en miroir.
                  final t = Curves.easeInOutCubic.transform(_flip.value);
                  final angle = t * math.pi;
                  final showFace = t > 0.5;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(angle),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..rotateY(showFace ? math.pi : 0),
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: showFace
                            ? CardFace(card: widget.card)
                            : const CardBack(radius: 12),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Touchez pour fermer',
                style: TextStyle(color: Color(0x99F3E3A3), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le bandeau des joueurs, posé au-dessus et au-dessous du plateau sur
/// téléphone.
///
/// Il n'existe que là, et pour une raison précise : le plateau est carré
/// et borné par la largeur de l'écran, si bien qu'en portrait il ne
/// remplit qu'un peu plus de deux cinquièmes de la hauteur. Ces bandeaux
/// occupent le reste — et y mettent ce qu'on cherche du regard pendant une
/// partie : à qui est le tour, et où en est chacun.
///
/// Le siège de celui qui joue s'allume, sa valeur de dé apparaît. Les
/// autres restent en retrait.
/// UN `Row` SUR UN ÉCRAN LARGE, UNE COLONNE SUR UN TÉLÉPHONE.
///
/// Le centre de commandes a été dessiné pour un écran large : chaque
/// carte y prend la moitié de la largeur. Sur un téléphone de 360 points
/// cette moitié tombe à 170, et un interrupteur avec son titre et sa
/// ligne d'explication n'y tient plus — tout se retrouve coincé, écrasé,
/// coupé.
///
/// Cette fonction prend EXACTEMENT les mêmes enfants qu'un `Row`. Quand
/// la place manque, elle les empile : les `Expanded` rendent leur enfant
/// tel quel (une colonne les étire déjà sur toute la largeur), et les
/// espaceurs horizontaux deviennent des espaceurs verticaux.
///
/// Le seuil est celui déjà retenu ailleurs dans ce panneau : en dessous,
/// deux colonnes ne tiennent pas.
Widget rowOuColonne({
  required List<Widget> children,
  double seuil = 560,
}) {
  return LayoutBuilder(builder: (context, c) {
    if (c.maxWidth >= seuil) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in children)
          if (w is Expanded)
            w.child
          else if (w is SizedBox && (w.width ?? 0) > 0)
            SizedBox(height: w.width)
          else
            w,
      ],
    );
  });
}

class _SeatStrip extends StatelessWidget {
  const _SeatStrip({
    required this.seats,
    required this.current,
    required this.diceValue,
    required this.homeCount,
    required this.flip,
  });

  final List<Player> seats;

  /// La couleur qui a la main.
  final PlayerColor current;

  /// La valeur du dé, montrée sur le seul siège actif. 0 = pas encore lancé.
  final int diceValue;

  /// Pions rentrés, par couleur : le seul chiffre qui dit qui gagne.
  final Map<PlayerColor, int> homeCount;

  /// Les joueurs d'en haut lisent le plateau à l'envers : leur bandeau se
  /// retourne, comme leurs cartes et comme le dé.
  ///
  /// Le retournement porte sur CHAQUE PAVÉ, pas sur la rangée. Retourner
  /// la rangée entière la lisait de droite à gauche : le pavé rouge
  /// atterrissait au-dessus de la base VERTE et le vert au-dessus de la
  /// ROUGE. C'est ce que signalait « Player 2 est rouge alors qu'il
  /// devrait être vert » — les deux étaient simplement inversés.
  final bool flip;

  static const Map<PlayerColor, Color> _tint = {
    PlayerColor.red: Color(0xFFED1C24),
    PlayerColor.green: Color(0xFF00A651),
    PlayerColor.blue: Color(0xFF29ABE2),
    PlayerColor.yellow: Color(0xFFFFCB05),
  };

  @override
  Widget build(BuildContext context) {
    if (seats.isEmpty) return const SizedBox.shrink();
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final p in seats)
            Flexible(
              child: RotatedBox(
                quarterTurns: flip ? 2 : 0,
                child: _SeatTile(
                  player: p,
                  tint: _tint[p.color] ?? Colors.white,
                  active: p.color == current,
                  diceValue: diceValue,
                  home: homeCount[p.color] ?? 0,
                ),
              ),
            ),
        ],
      ),
    );
    return row;
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.player,
    required this.tint,
    required this.active,
    required this.diceValue,
    required this.home,
  });

  final Player player;
  final Color tint;
  final bool active;
  final int diceValue;
  final int home;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.lerp(const Color(0xCC0B1220), tint, active ? 0.30 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? tint : tint.withValues(alpha: 0.35),
          width: active ? 2.0 : 1.0,
        ),
        boxShadow: active
            ? [BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 14)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xCCE8EEF7),
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                Text(
                  '$home/4 rentrés',
                  style: const TextStyle(
                      color: Color(0x99E8EEF7), fontSize: 10, height: 1.1),
                ),
              ],
            ),
          ),
          // Le dé n'apparaît que sur le siège qui joue, et seulement une
          // fois lancé : un dé affiché partout ne dit plus rien.
          if (active && diceValue > 0) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: MiniDieFace(value: diceValue, color: tint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// LE SAUT du pion, d'une case à la suivante.
///
/// Le pion GLISSAIT : `AnimatedPositioned` interpole sa position, et rien
/// de plus. On voyait un jeton traîné sur le plateau, pas un pion qui
/// avance. Ici il décolle, passe au-dessus de la ligne, et retombe — un
/// arc par case, comme une main qui déplace le pion.
///
/// L'arc est un demi-sinus : nul aux deux bouts, maximal au milieu. Le
/// pion part donc du sol et y revient exactement, sans saut d'image entre
/// deux cases.
///
/// Il s'y ajoute un écrasement à l'atterrissage — le pion se tasse d'un
/// dixième puis reprend sa taille. C'est peu, et c'est ce peu qui fait
/// qu'on SENT le contact au lieu de le déduire.
class _PawnHop extends StatefulWidget {
  const _PawnHop({
    required this.seq,
    required this.duration,
    required this.height,
    required this.child,
    this.glide = false,
  });

  /// Change à chaque case franchie. C'est le seul signal : le saut repart
  /// de zéro dès qu'il bouge.
  final int seq;

  /// Le temps d'une case. Le saut dure exactement ça, sinon le pion
  /// arriverait avant ou après s'être posé.
  final Duration duration;

  /// Hauteur du bond, en pixels.
  final double height;

  /// Un GLISSÉ, et surtout PAS un bond : la sortie de base.
  ///
  /// Le pion ne saute JAMAIS de sa boîte vers sa case de départ. Il ne
  /// quitte pas le sol du tout — il file, et il freine. Le saut est ce
  /// qu'on fait de case en case ; sortir de sa boîte n'est pas un pas,
  /// c'est une entrée en jeu.
  final bool glide;

  final Widget child;

  @override
  State<_PawnHop> createState() => _PawnHopState();
}

class _PawnHopState extends State<_PawnHop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration == Duration.zero
        ? const Duration(milliseconds: 220)
        : widget.duration,
  );

  @override
  void didUpdateWidget(covariant _PawnHop old) {
    super.didUpdateWidget(old);
    if (widget.seq != old.seq) {
      _c.duration = widget.duration == Duration.zero
          ? const Duration(milliseconds: 220)
          : widget.duration;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      // L'enfant est construit UNE fois : le pion porte une animation
      // WebP, la reconstruire à chaque frame la ferait repartir.
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        // AUCUNE élévation pour un glissé : le pion reste au sol de bout
        // en bout. C'est le freinage de la position, posé plus haut par
        // `AnimatedPositioned`, qui fait tout le travail.
        final lift =
            widget.glide ? 0.0 : math.sin(t * math.pi) * widget.height;
        // L'écrasement ne vit que sur le dernier sixième, au contact —
        // et seulement pour un saut : rien à amortir quand rien n'est
        // monté.
        final squash = widget.glide || t < 0.84
            ? 0.0
            : math.sin((t - 0.84) / 0.16 * math.pi);
        return Transform.translate(
          offset: Offset(0, -lift),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(
                1 + squash * 0.07, 1 - squash * 0.10, 1),
            child: child,
          ),
        );
      },
    );
  }
}

/// Retourne [child] pour les joueurs assis EN HAUT du plateau.
///
/// Rouge et vert regardent le plateau depuis l'autre bord : ce qui est
/// dessiné dans le sens de l'écran leur arrive à l'envers. Une carte, un
/// dé — tout ce qui doit se lire « face à soi » passe par ici. Bleu et
/// jaune, en bas, lisent tel quel.
/// Le `RotatedBox` est TOUJOURS là, à zéro ou à deux quarts de tour.
///
/// L'envelopper seulement pour rouge et vert changeait la FORME de
/// l'arbre à chaque passage de main : Flutter jetait alors l'État du
/// widget en dessous. Pour le dé, cet État est ce qui garde la dernière
/// image à l'écran — le perdre, c'est un dé vide le temps d'un décodage,
/// et le halo du plateau qui apparaît à sa place.
Widget _facingColor(PlayerColor c, Widget child) => RotatedBox(
      quarterTurns:
          (c == PlayerColor.red || c == PlayerColor.green) ? 2 : 0,
      child: child,
    );

/// La bannière affichée pendant qu'on désigne une cible sur le plateau.
///
/// Elle dit trois choses : quelle carte attend, ce qu'on attend, et
/// comment y renoncer. Sans elle, le plateau se met à refuser les coups
/// normaux et rien n'explique pourquoi.
class _TargetBanner extends StatelessWidget {
  const _TargetBanner({
    required this.card,
    required this.count,
    required this.onCancel,
  });

  final ChanceCard card;

  /// Combien de pions sont désignables. « aucun » n'arrive pas ici — on
  /// n'entre pas en désignation sans cible — mais le pluriel, si.
  final int count;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ident = cardIdentity(card);
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xE6101418),
          border: Border.all(color: ident.color, width: 1.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            CardGlyph(card: card, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Touchez le pion à désigner',
                    style: TextStyle(
                      color: ident.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    '${card.nameFr} — $count pion${count > 1 ? 's' : ''} '
                    'possible${count > 1 ? 's' : ''}',
                    style: const TextStyle(
                        color: Color(0xCCF3E3A3), fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onCancel,
              child: const Text('Annuler',
                  style: TextStyle(color: Color(0xFFF3E3A3))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le repère d'un pion DÉSIGNABLE : un anneau franc, doublé de blanc.
///
/// Il doit se voir sur les quatre couleurs de base comme sur le blanc des
/// cases — d'où le double trait : la couleur de la carte pour dire d'où
/// vient la demande, cerclée de blanc pour tenir sur n'importe quel fond.
/// Les quatre encoches en croix disent « ici, on touche ».
class _TargetMark extends CustomPainter {
  const _TargetMark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = u * 0.44;

    canvas.drawCircle(
        c, r, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.4, u * 0.085)
          ..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, u * 0.050)
          ..color = color);

    // Quatre encoches, aux quatre points cardinaux.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.6, u * 0.058)
      ..color = Colors.white;
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.96), c + d * (r * 1.26), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetMark old) => old.color != color;
}

/// Le repère d'un pion INVULNÉRABLE : un anneau clair autour de sa case,
/// et un petit écusson.
///
/// Volontairement discret — « une petite différence », pas un décor : le
/// pion doit rester le sujet de sa case.
/// LA SPHÈRE du pion invulnérable : une bulle de verre qui l'enferme.
///
/// Le repère était auparavant un anneau posé sur la case, sous le pion,
/// avec un petit écusson dans un coin. On le prenait pour une décoration
/// de case — rien ne disait qu'il appartenait au PION, et rien ne le
/// suivait quand il se déplaçait.
///
/// Une bulle, elle, ne se discute pas : ce qui est dedans est protégé.
/// Elle enveloppe le pion, monte et redescend avec lui, et respire —
/// lentement, pour qu'on la remarque sans qu'elle agite le plateau.
///
/// Elle reste TRANSPARENTE au centre : le pion doit continuer de se lire à
/// travers. Tout ce qui la rend visible est sur son bord — le renflement
/// du verre, un reflet en haut à gauche, un ressac de lumière en bas.
class _ShieldBubble extends StatefulWidget {
  const _ShieldBubble({required this.color});

  final Color color;

  @override
  State<_ShieldBubble> createState() => _ShieldBubbleState();
}

class _ShieldBubbleState extends State<_ShieldBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _ShieldBubblePainter(
            color: widget.color,
            breath: Curves.easeInOut.transform(_c.value),
          ),
        ),
      );
}

class _ShieldBubblePainter extends CustomPainter {
  const _ShieldBubblePainter({required this.color, required this.breath});

  final Color color;

  /// La respiration, de 0 à 1 : la bulle enfle d'un centième et son verre
  /// s'éclaircit un peu.
  final double breath;

  @override
  void paint(Canvas canvas, Size size) {
    // Le pion visible occupe le haut de sa boîte ; la bulle se centre
    // dessus, pas sur la boîte.
    final c = Offset(size.width / 2, size.height * 0.455);
    final r = size.height * 0.455 * (1 + 0.025 * breath);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Le VERRE : transparent au centre, dense au bord. C'est ce dégradé
    // qui donne le volume — un disque uniforme ferait un voile.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.02),
              color.withValues(alpha: 0.10 + 0.04 * breath),
              color.withValues(alpha: 0.34 + 0.10 * breath),
            ],
            stops: const [0.0, 0.72, 1.0],
          ).createShader(rect));

    // Le bord, doublé de blanc : sur une case de sa propre couleur, un
    // cerne de la même teinte disparaîtrait.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, r * 0.075)
          ..color = color.withValues(alpha: 0.85));
    canvas.drawCircle(
        c,
        r * 0.955,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, r * 0.028)
          ..color = Colors.white.withValues(alpha: 0.60 + 0.15 * breath));

    // Le REFLET, en haut à gauche : un arc clair et un point. Deux traits,
    // et le disque devient une sphère.
    final gloss = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, r * 0.09)
      ..color = Colors.white.withValues(alpha: 0.72);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.74),
        math.pi * 1.08, math.pi * 0.36, false, gloss);
    canvas.drawCircle(
        c + Offset(-r * 0.34, -r * 0.52),
        r * 0.085,
        Paint()..color = Colors.white.withValues(alpha: 0.80));

    // Le ressac : la lumière qui remonte du bas du verre.
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 0.84),
        math.pi * 0.18,
        math.pi * 0.44,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.8, r * 0.05)
          ..color = Colors.white.withValues(alpha: 0.28));
  }

  @override
  bool shouldRepaint(covariant _ShieldBubblePainter old) =>
      old.color != color || old.breath != breath;
}

/// Les 24 cartes Chance, à essayer à la main.
///
/// Le pendant de « Jeu manuel » pour les cartes : on choisit une famille,
/// une carte, un pion, on lit son JSON — celui de l'Annexe A — et on
/// l'applique au joueur sélectionné dans « Jeu manuel ». Une immédiate
/// s'exécute sur-le-champ, une différée entre dans la main du joueur.
class _ManualCardsCard extends StatefulWidget {
  final PlayerColor player;
  final void Function(ChanceCard card, PlayerColor player, int pawnId) onApply;

  const _ManualCardsCard({required this.player, required this.onApply});

  @override
  State<_ManualCardsCard> createState() => _ManualCardsCardState();
}

class _ManualCardsCardState extends State<_ManualCardsCard> {
  CardKind _kind = CardKind.immediate;
  ChanceCard? _card;
  int _pawnId = 0;
  bool _showJson = false;

  List<ChanceCard> get _deck =>
      _kind == CardKind.immediate ? kImmediateCards : kDeferredCards;

  ChanceCard get _selected => _card ?? _deck.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final card = _selected;
    final immediate = card.kind == CardKind.immediate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<CardKind>(
          segments: const [
            ButtonSegment(
                value: CardKind.immediate, label: Text('Immédiates')),
            ButtonSegment(
                value: CardKind.deferred, label: Text('Différées')),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _kind = v.first;
            _card = null;
          }),
        ),
        const SizedBox(height: 8),
        DropdownButton<ChanceCard>(
          isExpanded: true,
          value: card,
          items: [
            for (final c in _deck)
              DropdownMenuItem(
                value: c,
                child: Text('${c.timingLabelFr} · ${c.nameFr}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ),
          ],
          onChanged: (c) => setState(() => _card = c),
        ),
        Text(card.descriptionFr,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        // Une carte immédiate s'applique à UN pion : lequel ?
        if (immediate) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Pion',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('1')),
                    ButtonSegment(value: 1, label: Text('2')),
                    ButtonSegment(value: 2, label: Text('3')),
                    ButtonSegment(value: 3, label: Text('4')),
                  ],
                  selected: {_pawnId},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _pawnId = v.first),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: () =>
                    widget.onApply(card, widget.player, _pawnId),
                child: Text(immediate ? 'Appliquer' : 'Donner'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _showJson = !_showJson),
              child: Text(_showJson ? 'Masquer JSON' : 'Voir JSON'),
            ),
          ],
        ),
        if (_showJson)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              card.toJsonString(),
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 10, height: 1.35),
            ),
          ),
      ],
    );
  }
}

/// La carte que le joueur vient de RETOURNER dans sa base.
///
/// Tant qu'il n'y a pas touché, il ne voit que le dos ; ici il lit
/// l'instruction, désigne sa cible s'il en faut une, et l'applique. Le
/// moteur refuse la carte au mauvais moment : on le dit alors en clair
/// plutôt que de griser un bouton sans explication.
class _HandCardOverlay extends StatefulWidget {
  final ChanceCard card;
  final String ownerLabel;
  final double size;
  final bool playable;
  final List<Pawn> pawnTargets;
  final List<PlayerColor> playerTargets;
  final TurnPhase phase;
  final VoidCallback onClose;
  final void Function({Pawn? targetPawn, PlayerColor? targetPlayer}) onPlay;

  /// Pion proposé d'office — celui qui a déclenché la carte. Le joueur
  /// peut en désigner un autre, mais il n'a jamais un bouton mort devant
  /// lui.
  final Pawn? defaultPawn;

  /// Referme la carte et passe le plateau en mode désignation : le joueur
  /// touche alors directement le pion qu'il vise. `null` quand la carte
  /// ne vise pas un pion.
  final VoidCallback? onPickOnBoard;

  const _HandCardOverlay({
    super.key,
    required this.card,
    required this.ownerLabel,
    required this.size,
    required this.playable,
    required this.pawnTargets,
    required this.playerTargets,
    required this.phase,
    required this.onClose,
    required this.onPlay,
    this.defaultPawn,
    this.onPickOnBoard,
  });

  @override
  State<_HandCardOverlay> createState() => _HandCardOverlayState();
}

class _HandCardOverlayState extends State<_HandCardOverlay> {
  Pawn? _pawn;
  PlayerColor? _player;

  @override
  void initState() {
    super.initState();
    _pawn = widget.defaultPawn;
  }

  static String _fr(PlayerColor c) => switch (c) {
        PlayerColor.blue => 'bleu',
        PlayerColor.red => 'rouge',
        PlayerColor.green => 'vert',
        PlayerColor.yellow => 'jaune',
      };

  /// Pourquoi la carte ne part pas, dit en clair.
  String get _why {
    final card = widget.card;
    if (!widget.playable) {
      if (card.timing == ChanceTiming.beforeRoll &&
          widget.phase == TurnPhase.moving) {
        return 'Carte AVANT : elle se joue avant le lancer du dé.';
      }
      if (card.timing == ChanceTiming.afterRoll &&
          widget.phase == TurnPhase.rolling) {
        return 'Carte APRÈS : lance d\'abord ton dé.';
      }
      if (widget.card.action == CardAction.setDice) {
        return 'Aucun coup possible avec un ${widget.card.value} : la '
            'carte serait perdue pour rien.';
      }
      return 'Une seule carte différée par tour — celle-ci attendra.';
    }
    if (widget.card.needsTarget &&
        widget.card.entity == CardEntity.pawn &&
        widget.pawnTargets.isEmpty) {
      return 'Aucun pion à désigner pour l\'instant.';
    }
    if (widget.card.needsTarget &&
        widget.card.entity == CardEntity.player &&
        widget.playerTargets.isEmpty) {
      return 'Aucun joueur à désigner pour l\'instant.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final needsPawn = widget.card.needsTarget &&
        widget.card.entity == CardEntity.pawn;
    final needsPlayer = widget.card.needsTarget &&
        widget.card.entity == CardEntity.player;
    final ready = widget.playable &&
        (!needsPawn || _pawn != null) &&
        (!needsPlayer || _player != null);
    final w = (widget.size * 0.36).clamp(160.0, 270.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onClose,
      child: ColoredBox(
        color: const Color(0xCC000000),
        child: Center(
          // Le clic sur la carte elle-même ne doit pas la refermer.
          child: GestureDetector(
            onTap: () {},
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Votre carte — ${widget.ownerLabel}',
                    style: const TextStyle(
                      color: Color(0xFFF3E3A3),
                      fontSize: 13,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: w,
                    height: w * 1.55,
                    child: CardFace(card: widget.card),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: w,
                    child: Column(
                      children: [
                        // DÉSIGNER SUR LE PLATEAU : le geste naturel.
                        // Le pion visé est là, sous les yeux ; le choisir
                        // dans une liste — « pion 3 de rouge » — oblige à
                        // le retrouver ensuite du regard.
                        if (needsPawn && widget.onPickOnBoard != null)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: widget.pawnTargets.isEmpty
                                  ? null
                                  : widget.onPickOnBoard,
                              icon: const Icon(Icons.ads_click, size: 18),
                              label: const Text('Désigner sur le plateau'),
                            ),
                          ),
                        if (needsPawn)
                          DropdownButton<Pawn>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A1A1A),
                            value: widget.pawnTargets.contains(_pawn)
                                ? _pawn
                                : null,
                            hint: const Text('Choisir un pion',
                                style: TextStyle(color: Color(0xFFF3E3A3))),
                            items: [
                              for (final p in widget.pawnTargets)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                      'pion ${p.id + 1} de ${_fr(p.color)}',
                                      style: const TextStyle(
                                          color: Color(0xFFF3E3A3))),
                                ),
                            ],
                            onChanged: (p) => setState(() => _pawn = p),
                          ),
                        if (needsPlayer)
                          DropdownButton<PlayerColor>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A1A1A),
                            value: widget.playerTargets.contains(_player)
                                ? _player
                                : null,
                            hint: const Text('Choisir un joueur',
                                style: TextStyle(color: Color(0xFFF3E3A3))),
                            items: [
                              for (final c in widget.playerTargets)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(_fr(c),
                                      style: const TextStyle(
                                          color: Color(0xFFF3E3A3))),
                                ),
                            ],
                            onChanged: (c) => setState(() => _player = c),
                          ),
                        if (_why.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _why,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xCCF3E3A3), fontSize: 11),
                            ),
                          ),
                        const SizedBox(height: 8),
                        // Les deux boutons partagent la largeur de la
                        // carte : sans `Expanded` ils la débordaient.
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: widget.onClose,
                                child: Text(
                                    widget.defaultPawn == null
                                        ? 'Reposer'
                                        : 'Garder ce pion',
                                    style: const TextStyle(
                                        color: Color(0xFFF3E3A3))),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: ready
                                    ? () => widget.onPlay(
                                        targetPawn: _pawn,
                                        targetPlayer: _player)
                                    : null,
                                child: const Text('Jouer la carte'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La main de cartes différées du joueur courant : au plus 4 cartes, une
/// seule jouable par tour. Une carte « CHOSEN » demande d'abord de
/// désigner sa cible ; les autres partent d'un clic.
class _DeferredHandCard extends StatefulWidget {
  final List<ChanceCard> hand;
  final PlayerColor owner;
  final bool Function(ChanceCard) canPlay;
  final List<Pawn> Function(ChanceCard) pawnTargets;
  final List<PlayerColor> Function(ChanceCard) playerTargets;
  final void Function(ChanceCard, {Pawn? targetPawn, PlayerColor? targetPlayer})
      onPlay;

  const _DeferredHandCard({
    required this.hand,
    required this.owner,
    required this.canPlay,
    required this.pawnTargets,
    required this.playerTargets,
    required this.onPlay,
  });

  @override
  State<_DeferredHandCard> createState() => _DeferredHandCardState();
}

class _DeferredHandCardState extends State<_DeferredHandCard> {
  /// Cible choisie pour chaque carte qui en réclame une.
  final Map<String, Pawn> _pawnChoice = {};
  final Map<String, PlayerColor> _playerChoice = {};

  static String _fr(PlayerColor c) => switch (c) {
        PlayerColor.blue => 'bleu',
        PlayerColor.red => 'rouge',
        PlayerColor.green => 'vert',
        PlayerColor.yellow => 'jaune',
      };

  static String _pawnLabel(Pawn p) =>
      'pion ${p.id + 1} de ${_fr(p.color)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Indexée, pas seulement parcourue : le numéro affiché ici doit
        // être EXACTEMENT celui peint sur le dos de la carte, dans la base.
        for (var slot = 0; slot < widget.hand.length; slot++) () {
          final card = widget.hand[slot];
          final playable = widget.canPlay(card);
          final pawns = widget.pawnTargets(card);
          final players = widget.playerTargets(card);
          // Le besoin d'une cible vient de la CARTE, jamais de la longueur
          // de la liste : sans cette distinction, une carte à cible sans
          // aucune cible légale passait pour une carte sans cible, le
          // bouton restait actif et le clic ne faisait rien, en silence.
          final needsPawn =
              card.needsTarget && card.entity == CardEntity.pawn;
          final needsPlayer =
              card.needsTarget && card.entity == CardEntity.player;
          final noTarget = (needsPawn && pawns.isEmpty) ||
              (needsPlayer && players.isEmpty);
          final pawn = _pawnChoice[card.id];
          final player = _playerChoice[card.id];
          // Une carte à cible ne part qu'une fois la cible désignée.
          final ready = playable &&
              !noTarget &&
              (!needsPawn || pawn != null) &&
              (!needsPlayer || player != null);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // Le pictogramme de l'effet, pas une icône de carte
                    // générique : la ligne se lit sans être parcourue.
                    Opacity(
                      opacity: playable ? 1.0 : 0.45,
                      child: CardGlyph(card: card, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: card.descriptionFr,
                        child: Row(
                          children: [
                            // Le moment d'utilisation, dit comme la spec
                            // l'écrit : AVANT, APRÈS ou AVANT/APRÈS.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(card.timingLabelFr,
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(
                                          color: cs.onSecondaryContainer)),
                            ),
                            const SizedBox(width: 6),
                            // Le CODE de la carte — 1, 2, 3… pour une
                            // différée — le même que sur sa face.
                            Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD4AF37),
                                shape: BoxShape.circle,
                              ),
                              child: Text(cardCode(card),
                                  style: const TextStyle(
                                    color: Color(0xFF0A0A0A),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  )),
                            ),
                            const SizedBox(width: 6),
                            // L'effet en trois mots, dans la couleur de
                            // sa famille : c'est LUI qu'on lit d'abord.
                            Text(cardIdentity(card).label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cardIdentity(card).color,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.3,
                                )),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(card.nameFr,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: ready
                          ? () => widget.onPlay(card,
                              targetPawn: pawn, targetPlayer: player)
                          : null,
                      child: const Text('Jouer'),
                    ),
                  ],
                ),
                if (noTarget)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: Text(
                      'Aucune cible possible pour l\'instant.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.outline),
                    ),
                  ),
                if (needsPawn && pawns.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: DropdownButton<Pawn>(
                      isExpanded: true,
                      value: pawns.contains(pawn) ? pawn : null,
                      hint: const Text('Choisir un pion'),
                      items: [
                        for (final p in pawns)
                          DropdownMenuItem(
                              value: p, child: Text(_pawnLabel(p))),
                      ],
                      onChanged: (p) => setState(() {
                        if (p != null) _pawnChoice[card.id] = p;
                      }),
                    ),
                  ),
                if (needsPlayer && players.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: DropdownButton<PlayerColor>(
                      isExpanded: true,
                      value: players.contains(player) ? player : null,
                      hint: const Text('Choisir un joueur'),
                      items: [
                        for (final c in players)
                          DropdownMenuItem(value: c, child: Text(_fr(c))),
                      ],
                      onChanged: (c) => setState(() {
                        if (c != null) _playerChoice[card.id] = c;
                      }),
                    ),
                  ),
              ],
            ),
          );
        }(),
        Text(
          'Main de ${_fr(widget.owner)} — ${widget.hand.length}/'
          '${LudoUpgrades.handLimit} cartes. Une seule carte à la fois. '
          'AVANT = avant le lancer, APRÈS = après, AVANT/APRÈS = les deux. '
          'Survolez une carte pour lire son effet.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

/// Les Améliorations LudoPoly, dans l'onglet Règles du jeu : deux
/// interrupteurs indépendants, basculables en pleine partie.
class _UpgradesCard extends StatelessWidget {
  final bool vortexEnabled;
  final ValueChanged<bool> onToggleVortex;
  final bool chanceEnabled;
  final ValueChanged<bool> onToggleChance;

  const _UpgradesCard({
    required this.vortexEnabled,
    required this.onToggleVortex,
    required this.chanceEnabled,
    required this.onToggleChance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget row({
      required IconData icon,
      required String title,
      required String sub,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) =>
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(icon,
                  size: 16, color: value ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium),
                    Text(sub,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          icon: Icons.cyclone,
          title: 'Cases Vortex / Trou noir',
          sub: 'Deux cases par couleur, à votre couleur — vous seule les '
              'utilisez. La bonne, juste devant votre départ, vous envoie '
              'sur la première case de l\'adversaire en diagonale. La '
              'mauvaise, première case de votre dernière ligne droite, vous '
              'renvoie sur la sienne : 26 pas perdus.',
          value: vortexEnabled,
          onChanged: onToggleVortex,
        ),
        row(
          icon: Icons.help_center,
          title: 'Cases Chance',
          sub: '4 cases violettes, 2 cases avant chaque étoile. S\'y poser '
              'tire une carte du talon (mélangé au départ, retourné à '
              'l\'épuisement) : bonus ou mauvais tour, appliqué sur-le-champ '
              'au pion tombé dessus.',
          value: chanceEnabled,
          onChanged: onToggleChance,
        ),
        const SizedBox(height: 6),
        Text(
          'Un tirage sur deux donne une carte DIFFÉRÉE : elle se range dans '
          'votre main (4 places au maximum, dans le bloc « Vos cartes '
          'chance ») et se joue à votre tour, une seule à la fois.',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _SectionCard({
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Renders the board image, the pawn name labels, and every pawn at its
/// current location (base / ring / home column / home).
class BoardView extends StatelessWidget {
  final List<Player> players;
  final GameState game;
  final bool showRing;
  final bool showGrid;
  /// Debug overlay: draw a red rectangle around each pawn's bbox.
  final bool showCanvas;
  final int playerCount;
  /// Valeur du dé central. Un seul dé sur le plateau : il conserve la
  /// dernière valeur sortie jusqu'au lancer suivant.
  final int diceValue;

  /// Le dé est en train de rouler : le plateau montre alors l'animation de
  /// lancer du Studio plutôt que la face fixe.
  final bool diceRolling;

  /// Numéro du lancer en cours. Change à chaque lancer et force l'image
  /// animée à repartir de sa première frame.
  final int throwSeq;

  /// Couleur du siège ACTIF — celle du dé central ET du Yard qui
  /// clignote. Ce n'est PAS toujours [currentPlayerColor] : pendant qu'un
  /// pion compte ses cases, les deux indicateurs restent sur la couleur de
  /// ce pion et ne passent au joueur suivant qu'à son ARRIVÉE.
  final PlayerColor activeColor;
  final PlayerColor currentPlayerColor;
  /// Plateau gelé : voile « Pause » par-dessus, et les pions cessent même
  /// leur animation d'attente — sinon le plateau respire encore et la pause
  /// n'a pas l'air d'en être une.
  final bool paused;

  final bool canRollDice;
  final Set<Pawn> movablePawns;

  // ── LA DÉSIGNATION SUR LE PLATEAU ────────────────────────────────────
  //
  // Une carte qui vise « un pion adverse » demandait sa cible dans une
  // liste déroulante — « pion 3 de rouge » — alors que le pion est là,
  // sous les yeux. On le DÉSIGNE désormais en le touchant.
  //
  // Tant que [targetPawns] n'est pas vide, le plateau est en mode
  // désignation : seuls ces pions-là répondent au doigt, et ils
  // répondent à [onTargetPick] et non à [onPawnTap]. Les coups normaux
  // sont suspendus — on ne peut pas déplacer un pion pendant qu'on en
  // désigne un.
  final List<Pawn> targetPawns;

  /// Couleur du repère posé sur les cibles — celle de la famille de la
  /// carte, pour qu'on relie le repère à la carte qui l'a demandé.
  final Color targetTint;

  final void Function(Pawn)? onTargetPick;
  final VoidCallback onRollDice;
  final ValueChanged<Pawn> onPawnTap;
  /// Resolver for a pawn's currently-assigned idle GIF asset path.
  final String Function(Pawn) pawnAsset;
  /// Resolver for a pawn's detail string (shown in the cursor tooltip
  /// when `showDetails` is true).
  final String Function(Pawn) pawnInfo;
  /// Hover callback for token details. Null pawn = mouse exited.
  final ValueChanged<Pawn?>? onPawnHover;
  /// Hover callback for the dice. Bool = entered (true) / exited (false).
  final ValueChanged<bool>? onDiceHover;
  /// When true, the cursor over pawns/dice becomes a help-pointer (`?`).
  final bool showDetails;
  /// Per-pawn slide duration applied to the AnimatedPositioned wrapping
  /// the pawn's image. Pawns that just moved get their distance-based
  /// duration; pawns that didn't move see no change in position so the
  /// animation is a no-op.
  final Map<Pawn, Duration> moveDuration;

  /// Position VISUELLE d'un pion en cours de trajet. Quand une entrée est
  /// présente, le pion est dessiné sur cette case et non sur sa position
  /// réelle — c'est ce qui permet de le voir passer case par case.
  final Map<Pawn, PawnStep> travelStep;

  /// Le compteur de sauts, par pion : il change à chaque case franchie et
  /// c'est ce changement — rien d'autre — qui relance le saut.
  final Map<Pawn, int> hopSeq;

  /// Les pions qui SORTENT de leur base en ce moment. Leur trajet reçoit
  /// un arc plus ample et un freinage, au lieu du petit saut d'un pas.
  final Set<Pawn> baseExit;

  /// Pions en train de se faire capturer : affichés à leur ancienne position
  /// le temps du trajet du pion attaquant.
  final Map<Pawn, PawnStep> captureOverride;
  /// Active explosion FX painted on top of the board (capture markers).
  final List<ExplosionFx> explosions;

  /// Améliorations LudoPoly : dessiner les cases Vortex / Chance sur le
  /// plateau. Éteints par défaut — le plateau de base ne change pas.
  final bool showVortexCells;
  final bool showChanceCells;

  /// Les cartes différées que chaque couleur tient en main. Elles sont
  /// posées EN UN BLOC dans sa base, toutes FACE CACHÉE : on voit le dos,
  /// jamais l'instruction. Il faut TOUCHER une carte pour la retourner.
  final Map<PlayerColor, List<ChanceCard>> deferredHands;

  /// Les pions actuellement INVULNÉRABLES. Ils portent un petit repère —
  /// un anneau clair et un écusson — qui les distingue des autres sans
  /// masquer le pion lui-même.
  final Set<Pawn> invulnerablePawns;

  /// Les DEUX dés à montrer au centre, quand « Deux dés » ou « Double-dé »
  /// est actif pour le joueur au tour. `null` = un seul dé, comme
  /// d'habitude. Le demi-dé, lui, reste un dé unique : il ne change que
  /// les valeurs possibles.
  final ({int a, int b})? twoDice;

  /// La couleur dont les cartes sont cliquables — celle qui a la main, si
  /// c'est un humain. Les cartes des autres restent closes : tant qu'on
  /// n'y a pas droit, on ne voit pas ce qui est caché.
  final PlayerColor? tappableCardSeat;

  /// Le joueur a touché la carte n° [slot] de sa base.
  final void Function(int slot)? onDeferredCardTap;

  /// Le doigt se POSE sur une carte de sa base : elle se montre en grand
  /// tant qu'il y reste.
  final void Function(int slot)? onDeferredCardHold;

  /// Le doigt quitte la carte sans la relâcher dessus (geste annulé) :
  /// on la repose sans rien ouvrir.
  final VoidCallback? onDeferredCardRelease;
  const BoardView({
    super.key,
    required this.players,
    required this.game,
    required this.diceValue,
    this.diceRolling = false,
    this.throwSeq = 0,
    required this.activeColor,
    required this.currentPlayerColor,
    this.paused = false,
    required this.canRollDice,
    required this.movablePawns,
    this.targetPawns = const [],
    this.targetTint = const Color(0xFFFFD54F),
    this.onTargetPick,
    required this.onRollDice,
    required this.onPawnTap,
    required this.pawnAsset,
    required this.pawnInfo,
    this.onPawnHover,
    this.onDiceHover,
    this.showDetails = false,
    this.showRing = false,
    this.moveDuration = const {},
    this.travelStep = const {},
    this.hopSeq = const {},
    this.baseExit = const {},
    this.captureOverride = const {},
    this.explosions = const [],
    this.showGrid = false,
    this.showCanvas = false,
    this.playerCount = 4,
    this.showVortexCells = false,
    this.showChanceCells = false,
    this.deferredHands = const {},
    this.invulnerablePawns = const {},
    this.twoDice,
    this.tappableCardSeat,
    this.onDeferredCardTap,
    this.onDeferredCardHold,
    this.onDeferredCardRelease,
  });

  // Top-left grid cell of each colored base (the board is a 15x15 grid).
  // New layout: red TL, green TR, blue BL, yellow BR.
  static const Map<PlayerColor, Offset> _baseCorner = {
    PlayerColor.red:    Offset(0, 0),
    PlayerColor.green:  Offset(9, 0),
    PlayerColor.blue:   Offset(0, 9),
    PlayerColor.yellow: Offset(9, 9),
  };

  // Horizontal X positions (in cell units relative to base top-left) of the
  // 4 pawn slots inside a base. Y is computed dynamically so the pawn bbox
  // is stuck to the top of the (enlarged) white inner area with a 3px margin.
  static const List<double> _spotsX = kBaseSlotsX;

  /// Le BLOC de cartes d'une base : sa rangée est posée dans la bande
  /// libre entre les pions — rangés en haut vers 1,1 — et l'étiquette du
  /// joueur, en bas vers 5,5.
  static const double _cardRowY = 3.4;

  /// Abscisses des 4 cartes du bloc, en cases depuis le coin de la base.
  /// Elles se touchent presque : c'est un bloc, pas quatre emplacements
  /// épars.
  /// Écart entre deux cartes du bloc, en cases. Les cartes ont GRANDI —
  /// elles étaient trop petites pour qu'on distingue le pictogramme d'un
  /// coup d'œil — et l'écart a suivi, sinon elles se chevaucheraient.
  static const double cardSlotStep = 1.15;

  /// Largeur et hauteur d'une carte du bloc, en cases. Le bloc de quatre
  /// occupe donc 4 × 1,15 = 4,6 cases sur les 6 de la base : il reste une
  /// marge de 0,7 case de chaque côté.
  static const double cardW = 1.05;
  static const double cardH = 1.47;

  static const List<double> _cardSpotsX = [
    3.0 - 1.5 * cardSlotStep,
    3.0 - 0.5 * cardSlotStep,
    3.0 + 0.5 * cardSlotStep,
    3.0 + 1.5 * cardSlotStep,
  ];

  /// Centre de la carte [slot] (0..3) du bloc de [color], en unités de
  /// case. Fonction pure : les tests la vérifient sans widget.
  static Offset cardSlotCenter(PlayerColor color, int slot) {
    final corner = _baseCorner[color]!;
    return Offset(
      corner.dx + _cardSpotsX[slot.clamp(0, _cardSpotsX.length - 1)],
      corner.dy + _cardRowY,
    );
  }

  // ---- Pawn-image visible bounds inside its bbox -------------------------
  // The content-bbox-based scaling in `_PawnAnimatedGif` already aligns the
  // visible token's CENTER with the parent container's center, so we only
  // need to remember where the container is anchored on screen — which is
  // the cell center for every position (base / ring / home column).
  static const double _pawnVisibleCenterFrac = 0.5;

  // Center (in cell units) of each player's name label, placed in the
  // bottom row of its base. Targets: red 77/78, green 86/87, blue 212/213,
  // yellow 221/222 — center sits on the shared edge of those two cells.
  static const Map<PlayerColor, Offset> _labelCenter = {
    PlayerColor.red:    Offset(3.0,  5.5),
    PlayerColor.green:  Offset(12.0, 5.5),
    PlayerColor.blue:   Offset(3.0,  14.5),
    PlayerColor.yellow: Offset(12.0, 14.5),
  };

  /// Geometric center of the BASE slot cell the pawn rests in. Slots sit
  /// in row 0.5 of the base 6×6 (i.e. just inside the colored ribbon),
  /// raised by 1/2 cell vs the previous layout so 4 pions don't crowd
  /// against the player name banner.
  Offset _baseSlotCenter(PlayerColor color, int slot, double cell) {
    final corner = _baseCorner[color]!;
    final cx = (corner.dx + _spotsX[slot]) * cell;
    final cy = (corner.dy + kBaseSlotY) * cell;
    return Offset(cx, cy);
  }

  /// Geometric center of ring cell [index] in pixels.
  Offset _ringCellCenter(int index, double cell) => ring[index].pos * cell;
  Offset _pawnCenter(Pawn p, double cell, double pawnHeight) {
    // Pendant un trajet, la case affichée vient de `travelStep` : le modèle
    // est déjà à l'arrivée, mais on montre le pion là où il en est.
    // Si le pion est capturé, on le montre à son ancienne position jusqu'au
    // moment où l'attaquant arrive exactement sur sa case.
    final step = travelStep[p];
    final overrideLoc = captureOverride[p];
    final loc = step?.location ?? overrideLoc?.location ?? p.location;
    final pos = step?.position ?? overrideLoc?.position ?? p.position;
    final cellCenter = switch (loc) {
      PawnLocation.base       => _baseSlotCenter(p.color, pos, cell),
      PawnLocation.ring       => _ringCellCenter(pos, cell),
      PawnLocation.homeColumn => _homeColumnCenter(p.color, pos, cell),
      // Un pion arrivé se range à SA place sur l'hypoténuse. L'index est
      // son id (0..3), stable et unique dans sa couleur — `position` ne
      // veut plus rien dire une fois la maison atteinte.
      PawnLocation.home       => _homeCenter(p.color, p.id, cell),
    };
    return Offset(
      cellCenter.dx,
      cellCenter.dy + 0.1 * cell - 0.5 * pawnHeight,
    );
  }

  /// Place du pion [slot] d'une couleur ARRIVÉE, en unités de case.
  ///
  /// Chaque triangle de maison a son sommet au centre du plateau (7,5 ;
  /// 7,5) et sa base — l'hypoténuse — sur le bord extérieur du bloc
  /// central, du côté de sa couleur :
  ///
  ///   bleu   → sud     rouge → ouest
  ///   vert   → nord    jaune → est
  ///
  /// Les 4 pions se rangent sur 4 parts ÉGALES de cette hypoténuse : le
  /// pion [slot] occupe le MILIEU de la part n° [slot], soit les fractions
  /// 1/8, 3/8, 5/8 et 7/8 de la largeur. Ils sont donc symétriques deux à
  /// deux par rapport à l'axe du triangle, et aucun n'en recouvre un autre
  /// — avant, les quatre se superposaient sur un point unique.
  ///
  /// Les pions se posent SUR la ligne de l'hypoténuse elle-même, pas en
  /// retrait à l'intérieur du triangle : `reach` vaut donc la demi-largeur
  /// pleine du bloc central. La base y mesure 3 cases, d'où un pas de
  /// 0,75 case entre voisins — plus d'air qu'en retrait, et les pions ne
  /// se chevauchent plus.
  static Offset homeSlotCenter(PlayerColor color, int slot) {
    const center = 7.5;
    const reach = 1.5;            // demi-côté du bloc : on est SUR la base
    const step = (2 * reach) / 4; // 0,75 : largeur d'une part
    final along = (slot.clamp(0, 3) - 1.5) * step;
    switch (color) {
      case PlayerColor.blue:   return Offset(center + along, center + reach);
      case PlayerColor.green:  return Offset(center + along, center - reach);
      case PlayerColor.red:    return Offset(center - reach, center + along);
      case PlayerColor.yellow: return Offset(center + reach, center + along);
    }
  }

  Offset _homeCenter(PlayerColor color, int slot, double cell) =>
      homeSlotCenter(color, slot) * cell;

  /// Center of home-column cell [position] (0..4) for the given [color].
  /// Position 0 = entry from ring, position 4 = cell just before center.
  Offset _homeColumnCenter(PlayerColor color, int position, double cell) {
    final p = position.toDouble();
    late double col, row;
    switch (color) {
      case PlayerColor.blue:
        col = 7;      row = 13 - p; break;
      case PlayerColor.red:
        col = 1 + p;  row = 7;      break;
      case PlayerColor.green:
        col = 7;      row = 1 + p;  break;
      case PlayerColor.yellow:
        col = 13 - p; row = 7;      break;
    }
    return Offset((col + 0.5) * cell, (row + 0.5) * cell);
  }

  @override
  Widget build(BuildContext context) {
    // 5- and 6-player boards use a polygonal layout (no 15x15 grid, no
    // pawns/labels yet — first pass focuses on the board geometry). A single
    // shared dice sits in the central dark hexagon.
    // Polygonal layout only for 5 and 6. Counts 1-4 all use the 4-player
    // board (inactive colors are filtered out of the pawn/label rendering
    // by the parent that builds the `players` list).
    if (playerCount == 5) {
      // 5-player board: vector-painted from the BoardCraft geometry
      // (lib/game/board5p_geometry.dart + lib/game/board_painter_5p.dart).
      // The painter draws its own dice cell at the center, so no separate
      // _DiceFace overlay here (pawn/dice interaction layer is TBD).
      return const Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: BoardPainter5P())),
        ],
      );
    }
    if (playerCount >= 5) {
      return LayoutBuilder(
        builder: (context, c) {
          final side = c.biggest.shortestSide;
          final diceSize =
              side * _PolygonBoardPainter.diceSizeFraction(playerCount);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                    painter: _PolygonBoardPainter(n: playerCount)),
              ),
              if (showRing && playerCount == 5)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _PolygonRingDebugPainter(n: playerCount),
                    ),
                  ),
                ),
              Positioned(
                left: (c.biggest.width - diceSize) / 2,
                top: (c.biggest.height - diceSize) / 2,
                width: diceSize,
                height: diceSize,
                child: const _DiceFace(value: 1),
              ),
            ],
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final side = c.biggest.shortestSide;
        final cell = side / 15.0;

        // Hauteur visible du pion. Elle vaut exactement le côté du socle
        // peint sous lui dans la base : les deux tombent donc l'un sur
        // l'autre au pixel près. 1,2 était trop grand — le pion débordait
        // sur les cases voisines et masquait la flèche de sélection.
        // Le pion déborde volontairement de sa case : sur un plateau de
        // téléphone une case fait 24 px, un pion à sa taille exacte y est
        // un timbre. Il empiète donc sur ses voisines — sans jamais les
        // masquer, la silhouette étant étroite et le bas transparent.
        final pawnHeight = cell * kBaseSlotSize * 1.18;
        // Aspect ≈ 0.7 — close to a typical idle WebP (64/93 = 0.69).
        final pawnWidth = pawnHeight * 0.8;

        return Stack(
          // Le corps d'un pion monte AU-DESSUS de sa case. Sur la rangée du
          // haut — cases 23, 24, 25 — il sortait donc du plateau et se
          // faisait couper net. On laisse déborder.
          clipBehavior: Clip.none,
          children: [
            // Vector-drawn board: stays crisp at any size (no raster scaling).
            Positioned.fill(
              child: CustomPaint(
                  painter: BoardPainter(
                showVortex: showVortexCells,
                showChance: showChanceCells,
              )),
            ),

            // Le Yard du siège actif CLIGNOTE, en écho à la couleur du dé
            // central : les deux disent à qui de jouer — humain comme
            // ordinateur. Posé sous les étiquettes et les pions pour ne
            // voler aucun clic ni recouvrir personne.
            () {
              final corner = _baseCorner[activeColor]!;
              return Positioned(
                left: corner.dx * cell,
                top:  corner.dy * cell,
                width: 6 * cell,
                height: 6 * cell,
                child: YardBlink(
                  playerColor: activeColor,
                  color: _colorOf(activeColor),
                  paused: paused,
                  strokeWidth: (cell * 0.14).clamp(2.0, 6.0),
                ),
              );
            }(),

            // Player name labels — sitting in the bottom row of each base.
            for (final p in players)
              () {
                final lc = _labelCenter[p.color]!;
                final w = cell * 2.4;
                final h = cell * 0.8;
                return Positioned(
                  left: lc.dx * cell - w / 2,
                  top:  lc.dy * cell - h / 2,
                  width: w,
                  height: h,
                  child: Center(
                    child: _PlayerLabel(
                      name: p.name,
                      color: _colorOf(p.color),
                      // Scale the label font with the cell size — 14 at a
                      // ~50 px cell (~750 px board), down to ~7 on a 360 px
                      // smartphone preset.
                      fontSize: (cell * 0.30).clamp(8.0, 16.0),
                    ),
                  ),
                );
              }(),

            // Le BLOC de cartes de chaque couleur, posé dans sa base et
            // TOUJOURS face cachée : on voit le dos, jamais l'instruction.
            // Les emplacements libres restent en pointillé doré.
            if (showChanceCells)
              for (final p in players)
                for (int slot = 0; slot < LudoUpgrades.handLimit; slot++)
                  () {
                    final hand =
                        deferredHands[p.color] ?? const <ChanceCard>[];
                    final center = cardSlotCenter(p.color, slot);
                    final w = cell * BoardView.cardW;
                    final h = cell * BoardView.cardH;
                    return Positioned(
                      left: center.dx * cell - w / 2,
                      top: center.dy * cell - h / 2,
                      width: w,
                      height: h,
                      child: () {
                        if (slot >= hand.length) {
                          // Emplacement libre : un liseré, et rien à
                          // toucher.
                          return IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(cell * 0.10),
                                border: Border.all(
                                  color: const Color(0x55D4AF37),
                                  width: math.max(1.0, cell * 0.03),
                                ),
                              ),
                            ),
                          );
                        }
                        final mine = p.color == tappableCardSeat;
                        // MES cartes se reconnaissent sans être
                        // retournées : pictogramme de l'effet, code, et
                        // l'effet en trois mots. Celles des autres
                        // restent un dos muet, numéroté à partir de 1
                        // pour qu'on puisse désigner « sa deuxième ».
                        final art = mine
                            ? CardMini(
                                card: hand[slot],
                                number: slot + 1,
                                radius: cell * 0.10)
                            : CardBack(
                                radius: cell * 0.10,
                                number: slot + 1,
                              );
                        if (!mine || onDeferredCardTap == null) {
                          return IgnorePointer(child: art);
                        }
                        // C'est MA carte et c'est mon tour : je peux la
                        // retourner pour lire son instruction en entier.
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (_) =>
                                onDeferredCardHold?.call(slot),
                            onPointerUp: (_) => onDeferredCardTap!(slot),
                            onPointerCancel: (_) =>
                                onDeferredCardRelease?.call(),
                            // Le doigt sort de la carte sans se lever :
                            // geste annulé. On repose la carte sans la
                            // jouer — sinon glisser le doigt hors de la
                            // carte pour renoncer la jouerait quand même.
                            onPointerMove: (e) {
                              if (e.localPosition.dx < 0 ||
                                  e.localPosition.dy < 0 ||
                                  e.localPosition.dx > w ||
                                  e.localPosition.dy > h) {
                                onDeferredCardRelease?.call();
                              }
                            },
                            child: art,
                          ),
                        );
                      }(),
                    );
                  }(),

            // Single central dice in the active player's color. Clickable
            // during the rolling phase.
            () {
              final pair = twoDice;
              // Avec la carte « Deux dés », il y en a bien DEUX au centre,
              // un peu plus petits pour tenir côte à côte. Le total joué
              // est leur somme.
              // Le dé occupe plus de deux cases : posé à plat au centre
              // du plateau, il doit se lire d'un coup d'œil, sans qu'on se
              // penche ni qu'on le cherche. C'est l'objet autour duquel
              // tout le tour s'organise.
              final size = pair == null ? cell * 2.35 : cell * 1.50;
              final width = pair == null ? size : size * 2 + cell * 0.14;
              final clickable = canRollDice;
              return Positioned(
                left: 7.5 * cell - width / 2,
                top:  7.5 * cell - size / 2,
                width: width,
                height: size,
                child: MouseRegion(
                  cursor: showDetails
                      ? SystemMouseCursors.help
                      : (clickable
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic),
                  onEnter: (_) => onDiceHover?.call(true),
                  onExit: (_) => onDiceHover?.call(false),
                  // `Listener` et non `GestureDetector` : `onTap` attend
                  // le RELÂCHEMENT du doigt, et l'arbitrage des gestes
                  // peut encore le retarder ou l'annuler si le doigt
                  // glisse d'un cheveu. `onPointerDown` part à l'instant
                  // où le doigt se pose — c'est ce qu'on veut d'un dé.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: clickable ? (_) => onRollDice() : null,
                    // Le dé se présente FACE À CELUI QUI JOUE, comme les
                    // cartes. Rouge et vert sont assis en haut : un dé
                    // dessiné dans le sens de l'écran leur montre son
                    // ombre du mauvais côté, et sa lumière aussi. On le
                    // retourne, et chacun voit le même dé que l'autre
                    // depuis sa place.
                    child: _facingColor(activeColor, pair == null
                        ? _DiceFace(
                            value: diceValue,
                            playerColor: activeColor,
                            rolling: diceRolling,
                            throwSeq: throwSeq,
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                width: size,
                                height: size,
                                child: _DiceFace(
                                    value: pair.a, playerColor: activeColor),
                              ),
                              SizedBox(
                                width: size,
                                height: size,
                                child: _DiceFace(
                                    value: pair.b, playerColor: activeColor),
                              ),
                            ],
                          )),
                  ),
                ),
              );
            }(),

            // Every pawn, rendered at its current model position. Pawns the
            // current player can move with the rolled dice are highlighted
            // and tappable.
            //
            // Two passes:
            //   1) yield all `Selector_D_Arrow` GIFs for movable pawns first
            //      → guaranteed behind ALL pawns (selectors never occlude
            //      another pawn's MouseRegion).
            //   2) yield all pawn MouseRegions next → topmost in their bbox,
            //      hover/click hit-testing stays simple per pawn.
            // Le repère des pions INVULNÉRABLES ne se dessine plus ici :
            // c'est désormais une SPHÈRE qui enveloppe le pion, posée avec
            // lui plus bas — elle doit le suivre, saut compris.

            ...() sync* {
              final activeColors = players.map((p) => p.color).toSet();
              final rawList = game.allPawns
                  .where((p) => activeColors.contains(p.color))
                  .toList();

              // ── Stacking: pawns sharing the same cell get a lateral
              //    offset so all colors stay visible, and the CURRENT
              //    player's pawn is rendered LAST (so it sits on top of
              //    the pile). Same-color stacks (ring blocks, home
              //    column doubles) keep a deterministic id order.
              String stackKey(Pawn p) {
                // Même règle que _pawnCenter : un pion en trajet se groupe
                // avec la case qu'il TRAVERSE, pas avec sa case d'arrivée.
                // Un pion capturé se groupe aussi avec son ancienne position.
                final step = travelStep[p];
                final overrideLoc = captureOverride[p];
                final loc = step?.location ?? overrideLoc?.location ?? p.location;
                final pos = step?.position ?? overrideLoc?.position ?? p.position;
                switch (loc) {
                  case PawnLocation.base:
                    return 'base_${p.color.name}_$pos';
                  case PawnLocation.ring:
                    return 'ring_$pos';
                  case PawnLocation.homeColumn:
                    return 'hc_${p.color.name}_$pos';
                  case PawnLocation.home:
                    // Chaque pion arrivé a DÉJÀ sa place propre sur
                    // l'hypoténuse : le grouper avec ses coéquipiers lui
                    // ajouterait un décalage latéral par-dessus, et les
                    // quatre repartiraient de travers.
                    return 'home_${p.color.name}_${p.id}';
                }
              }
              final groups = <String, List<Pawn>>{};
              for (final p in rawList) {
                groups.putIfAbsent(stackKey(p), () => []).add(p);
              }
              // ── Décalage latéral : ordre STABLE (couleur, id).
              //    Il ne dépend PAS du joueur courant : sinon, à chaque
              //    changement de tour, les pions d'une même case
              //    échangeaient leur place latérale et on avait
              //    l'impression qu'ils permutaient.
              int stableCompare(Pawn a, Pawn b) {
                final c = a.color.index.compareTo(b.color.index);
                return c != 0 ? c : a.id.compareTo(b.id);
              }
              final stackOffsets = <Pawn, Offset>{};
              const stackDxFrac = 0.18; // 18 % de case entre voisins
              for (final g in groups.values) {
                g.sort(stableCompare);
                final n = g.length;
                // Un pion capturé (encore affiché à son ancienne position
                // via `captureOverride`) NE DOIT PAS BOUGER quand
                // l'attaquant le rejoint sur sa case : geler tout le
                // groupe à décalage zéro tant que la capture est en cours,
                // sinon le pion capturé glisse latéralement (perçu comme
                // "un pas en arrière") au moment où le groupe passe de 1 à
                // 2 pions.
                final hasCapture = g.any((pw) => captureOverride.containsKey(pw));
                for (int i = 0; i < n; i++) {
                  final dx = (n == 1 || hasCapture)
                      ? 0.0
                      : (i - (n - 1) / 2) * stackDxFrac * cell;
                  stackOffsets[g[i]] = Offset(dx, 0);
                }
              }

              // ── Ordre de PEINTURE (z) uniquement : le pion du joueur
              //    courant passe devant. C'est le seul critère qui dépend
              //    du tour, et il ne touche plus aux positions.
              final list = groups.values.expand((g) => g).toList()
                ..sort((a, b) {
                  final aCur = a.color == currentPlayerColor ? 1 : 0;
                  final bCur = b.color == currentPlayerColor ? 1 : 0;
                  if (aCur != bCur) return aCur - bCur; // courant en dernier
                  return stableCompare(a, b);
                });

              // Décalage de démarrage de l'anim idle, DÉTERMINISTE et propre
              // à chaque pion : indexé sur son identité, jamais sur sa place
              // dans la liste de rendu (qui change à chaque déplacement).
              int delayOf(Pawn p) => ((p.color.index * 4 + p.id) * 137) % 800;

              // ---- Passe 1 ter : LES HALOS, TOUS AVANT TOUS LES PIONS.
              //
              // Le halo vivait dans le pion, sous son propre sprite. Il
              // ne le traversait donc pas — mais il traversait LES
              // AUTRES : sur l'anneau les pions se chevauchent (un pion
              // fait 1,36 case de haut), et le halo d'un pion se
              // retrouvait par-dessus la tête de son voisin de derrière.
              //
              // Il faut donc les peindre TOUS d'abord. Ils gardent
              // EXACTEMENT la même position animée que leur pion —
              // `AnimatedPositioned`, même durée, même courbe, construit
              // dans la même passe de build : les deux tweens partent sur
              // la même frame et n'ont aucun moyen de diverger.
              for (final pawn in list) {
                if (pawn.location == PawnLocation.base &&
                    !movablePawns.contains(pawn)) {
                  continue;
                }
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                yield AnimatedPositioned(
                  key: ValueKey('halo_${pawn.color.name}_${pawn.id}'),
                  duration: moveDuration[pawn] ?? Duration.zero,
                  curve: baseExit.contains(pawn)
                      ? Curves.easeOutCubic
                      : Curves.easeInOut,
                  // Les pieds du pion, pas son cadre : le halo reste au
                  // sol pendant que le pion saute au-dessus de lui.
                  left: center.dx - cell * 0.36,
                  top: center.dy -
                      pawnHeight * _pawnVisibleCenterFrac +
                      pawnHeight * 0.90 -
                      cell * 0.19,
                  width: cell * 0.72,
                  height: cell * 0.38,
                  child: IgnorePointer(
                    child: _PawnHaloView(
                      color: _colorOf(pawn.color),
                      spinning: movablePawns.contains(pawn),
                    ),
                  ),
                );
              }

              // ---- Pass 2: pawn IMAGES (no hit-test, full bbox for visual).
              //  AnimatedPositioned interpolates left/top when the cell
              //  changes — Flutter handles the slide internally, no extra
              //  rebuild of the rest of the board. ----
              for (final pawn in list) {
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final bboxLeft = center.dx - pawnWidth / 2;
                final bboxTop  = center.dy - pawnHeight * _pawnVisibleCenterFrac;
                yield AnimatedPositioned(
                  // SANS cette clé, le Stack apparie ses enfants par index :
                  // dès qu'un pion change de case l'ordre de la liste bouge,
                  // et le tween de position d'un pion se retrouve appliqué à
                  // un autre — les pions semblaient s'échanger.
                  key: ValueKey('pawn_${pawn.color.name}_${pawn.id}'),
                  duration: moveDuration[pawn] ?? Duration.zero,
                  // La SORTIE DE BASE freine au lieu de s'arrêter : le pion
                  // part vite de sa boîte et se pose en douceur sur sa case
                  // de départ. C'est ce freinage, et lui seul, qui fait la
                  // différence entre un pion posé et un pion téléporté.
                  curve: baseExit.contains(pawn)
                      ? Curves.easeOutCubic
                      : Curves.easeInOut,
                  left: bboxLeft,
                  top:  bboxTop,
                  width: pawnWidth,
                  height: pawnHeight,
                  child: IgnorePointer(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: _PawnHop(
                      seq: hopSeq[pawn] ?? 0,
                      duration: moveDuration[pawn] ?? Duration.zero,
                      height: cell * 0.42,
                      // La sortie de base GLISSE : elle ne décolle pas.
                      glide: baseExit.contains(pawn),
                      child: _PawnAnimatedGif(
                      key: ValueKey('${pawn.color.name}_${pawn.id}'),
                      asset: pawnAsset(pawn),
                      sequentialStartDelayMs: delayOf(pawn),
                      showCanvas: showCanvas,
                      // Only the current player's pawns animate. The
                      // others stay on their rest frame so the board
                      // doesn't get visually overloaded.
                      paused: paused || pawn.color != currentPlayerColor,
                    ),
                    ),
                        ),
                        // LA SPHÈRE du pion invulnérable. Dans le saut,
                        // donc elle monte et redescend avec lui : c'est
                        // une bulle qui l'enferme, pas une marque au sol.
                        if (invulnerablePawns.contains(pawn))
                          Positioned.fill(
                            child: _ShieldBubble(color: _colorOf(pawn.color)),
                          ),
                      ],
                    ),
                  ),
                );
                // (Canvas debug overlay is drawn inside `_PawnAnimatedGif`
                // when `showCanvas` is true, using the GIF's native pixel
                // dimensions so the rectangle matches the actual rendered
                // image — not the layout bbox.)
              }

              // ---- Passe 2 bis : LA FLÈCHE des pions jouables. ----
              //
              // Elle était dessinée AVANT les pions, donc derrière eux.
              // Tant que le repère du Studio portait aussi un anneau de
              // pointillés sous les pieds, il en restait quelque chose de
              // visible ; en ne gardant que la flèche, elle disparaissait
              // entièrement derrière la tête du pion.
              //
              // Elle passe donc APRÈS les pions — au-dessus de tout — et
              // se pose FRANCHEMENT au-dessus de la tête, sans la
              // recouvrir. Elle ne prend aucun clic : c'est un panneau
              // indicateur, pas un bouton.
              //
              // L'asset est recadré au plus près de la flèche
              // (`Selector_Arrow_Tight`, 73 x 76) : sur la toile 400 x 400
              // d'origine, la flèche n'occupait qu'un sixième de la
              // hauteur, et la mettre à une taille lisible aurait demandé
              // un cadre de trois cases.
              for (final pawn in list) {
                if (targetPawns.isNotEmpty) break; // on désigne, on ne joue pas
                if (!movablePawns.contains(pawn)) continue;
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final aw = cell * 0.62;
                final ah = aw * 76 / 73;
                yield Positioned(
                  key: ValueKey('sel_${pawn.color.name}_${pawn.id}'),
                  left: center.dx - aw / 2,
                  // Le sommet du pion visible, moins la flèche et un jour.
                  top: center.dy -
                      pawnHeight * _pawnVisibleCenterFrac -
                      ah -
                      cell * 0.04,
                  width: aw,
                  height: ah,
                  child: IgnorePointer(
                    child: Image.asset(
                      'AnimStock/Selectors/WEBP/Selector_Arrow_Tight.webp',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                );
              }

              // ---- Passe 2 bis : le REPÈRE des pions désignables. ----
              // Un anneau franc autour de chaque cible, dans la couleur
              // de la carte. Il est dessiné APRÈS les pions pour qu'aucun
              // ne le recouvre : c'est le seul moment où le repère compte
              // plus que le pion.
              for (final pawn in targetPawns) {
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final d = cell * 1.15;
                yield Positioned(
                  key: ValueKey('tgt_${pawn.color.name}_${pawn.id}'),
                  left: center.dx - d / 2,
                  top: center.dy - d / 2,
                  width: d,
                  height: d,
                  child: IgnorePointer(
                    child: CustomPaint(painter: _TargetMark(targetTint)),
                  ),
                );
              }

              // ---- Pass 3: HIT zones (tight square around the visible
              //              token only — no more giant bbox swallowing
              //              the empty halo around the sprite). ----
              // Zone de touche : cell × 1.34, centrée sur le pion visible.
              // Le pion n'occupe que cell×0.776 en hauteur ; à la souris
              // un carré serré suffisait, mais un doigt est large de
              // 8 mm et se pose rarement au pixel près. On élargit donc
              // au-delà du sprite — les zones voisines ne se recouvrent
              // pas pour autant, les pions étant à une case d'écart.
              // La zone couvre le pion ENTIER, tête comprise.
              //
              // C'était un carré centré sur l'ancre du pion — donc sur son
              // milieu. Le doigt posé sur la TÊTE, la partie qu'on vise
              // spontanément parce que c'est elle qu'on voit, tombait au
              // bord de la zone ou dehors. D'où le pion qui « ne répond
              // pas ». La zone est maintenant plus haute que large et
              // remontée : elle englobe la tête, le corps et le socle.
              final hitW = cell * 1.30;
              final hitH = pawnHeight + cell * 0.55;
              // De combien remonter : l'ancre est au milieu du pion, la
              // tête au-dessus.
              final hitUp = pawnHeight * _pawnVisibleCenterFrac + cell * 0.30;
              // En mode désignation, c'est la liste des cibles qui commande
              // — pas les coups possibles. Un pion adverse n'est jamais
              // « jouable », et c'est pourtant lui qu'on vient désigner.
              final picking = targetPawns.isNotEmpty && onTargetPick != null;
              for (final pawn in list) {
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final isMovable = picking
                    ? targetPawns.contains(pawn)
                    : movablePawns.contains(pawn);
                yield Positioned(
                  key: ValueKey('hit_${pawn.color.name}_${pawn.id}'),
                  left: center.dx - hitW / 2,
                  top:  center.dy - hitUp,
                  width: hitW,
                  height: hitH,
                  child: MouseRegion(
                    cursor: showDetails
                        ? SystemMouseCursors.help
                        : (isMovable
                            ? SystemMouseCursors.click
                            : SystemMouseCursors.basic),
                    onEnter: (_) {
                      debugPrint('[hover] enter ${pawn.color.name}#${pawn.id}');
                      onPawnHover?.call(pawn);
                    },
                    onExit: (_) {
                      debugPrint('[hover] exit  ${pawn.color.name}#${pawn.id}');
                      onPawnHover?.call(null);
                    },
                    child: Tooltip(
                      message: showDetails ? pawnInfo(pawn) : '',
                      waitDuration: const Duration(milliseconds: 150),
                      preferBelow: true,
                      verticalOffset: 18,
                      child: Listener(
                        // Sans `opaque`, un SizedBox invisible n'absorbe
                        // pas les touches → elles traverseraient jusqu'au
                        // parent et `onPawnTap` ne partirait jamais.
                        //
                        // `onPointerDown` plutôt que `onTap` : le pion
                        // part dès que le doigt se pose, sans attendre
                        // qu'il se relève ni que l'arbitrage tranche.
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: !isMovable
                            ? null
                            : picking
                                ? (_) => onTargetPick!(pawn)
                                : (_) => onPawnTap(pawn),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                );
              }
            }(),

            // Debug overlay: numbered dots on every ring cell.
            if (showRing)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RingDebugPainter(cell: cell)),
                ),
              ),

            // Debug overlay: 15x15 grid with cell numbers (0..224, row-major).
            if (showGrid)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GridDebugPainter(cell: cell)),
                ),
              ),

            // Capture explosions painted on top of everything.
            for (final fx in explosions)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: fx.controller,
                    builder: (ctx, _) {
                      final c = _pawnCenter(fx.targetPawn, cell, pawnHeight);
                      // Explosion FX is anchored on the captured cell.
                      // Use the visible pawn center (above the pointe).
                      final visCenter = Offset(
                        c.dx,
                        c.dy + 0.5 * pawnHeight - 0.5 * cell * 0.5,
                      );
                      return CustomPaint(
                        painter: _ExplosionPainter(
                          progress: fx.controller.value,
                          color: fx.colorRgb,
                          center: visCenter,
                          scale: cell * 1.4,
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Voile de PAUSE, tout en haut de la pile : il grise le plateau
            // et absorbe les clics, pour qu'on voie ET qu'on sente que rien
            // ne répond plus.
            if (paused)
              Positioned.fill(
                child: AbsorbPointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.pause_circle_filled,
                                color: Colors.white, size: 26),
                            SizedBox(width: 10),
                            Text(
                              'PAUSE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static Color _colorOf(PlayerColor c) {
    switch (c) {
      case PlayerColor.yellow: return const Color(0xFFE6B800);
      case PlayerColor.blue:   return const Color(0xFF3DA4EC);
      case PlayerColor.red:    return const Color(0xFFD33232);
      case PlayerColor.green:  return const Color(0xFF2E8B47);
    }
  }
}

/// Paints small numbered markers on every ring cell + emphasizes safe cells.
class _RingDebugPainter extends CustomPainter {
  final double cell;
  _RingDebugPainter({required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final normal = Paint()..color = const Color(0xCCFF00FF);
    final start = Paint()..color = const Color(0xCCFFC107);
    final star = Paint()..color = const Color(0xCC00E5FF);
    for (final c in ring) {
      final cx = c.pos.dx * cell;
      final cy = c.pos.dy * cell;
      Paint p;
      switch (c.type) {
        case CellType.start:     p = start; break;
        case CellType.safeStar:  p = star; break;
        case CellType.normal:    p = normal; break;
      }
      canvas.drawCircle(Offset(cx, cy), cell * 0.18, p);

      final tp = TextPainter(
        text: TextSpan(
          text: '${c.index}',
          style: TextStyle(
            color: Colors.white,
            fontSize: cell * 0.28,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RingDebugPainter old) => old.cell != cell;
}

/// Debug overlay for the 5-player ring: numbered magenta dots on every ring
/// cell, mirroring the 4-player [_RingDebugPainter] but for the polygonal
/// layout produced by [_PolygonBoardPainter].
class _PolygonRingDebugPainter extends CustomPainter {
  final int n;
  _PolygonRingDebugPainter({required this.n});

  @override
  void paint(Canvas canvas, Size size) {
    if (n != 5) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final c = _PolygonBoardPainter.cellSize5(
        math.min(size.width, size.height));
    final positions = _PolygonBoardPainter.ringPositions5(cx, cy, c);

    final dotPaint = Paint()..color = const Color(0xCCFF00FF);
    final dotR = c * 0.22;
    final fontSize = c * 0.32;
    for (int i = 0; i < positions.length; i++) {
      final p = positions[i];
      canvas.drawCircle(p, dotR, dotPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonRingDebugPainter old) => old.n != n;
}

/// Paints a 15x15 grid above the board with each cell's index (row-major,
/// 0..224). Used as a coordinate ruler when designing the board geometry.
class _GridDebugPainter extends CustomPainter {
  final double cell;
  _GridDebugPainter({required this.cell});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xAAFF00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final side = cell * 15.0;
    for (int i = 0; i <= 15; i++) {
      final p = i * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, side), line);
      canvas.drawLine(Offset(0, p), Offset(side, p), line);
    }
    final fontSize = cell * 0.28;
    for (int r = 0; r < 15; r++) {
      for (int c = 0; c < 15; c++) {
        final idx = r * 15 + c;
        final tp = TextPainter(
          text: TextSpan(
            text: '$idx',
            style: TextStyle(
              color: Colors.black,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            c * cell + (cell - tp.width) / 2,
            r * cell + (cell - tp.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridDebugPainter old) => old.cell != cell;
}

/// Painter for 5- and 6-player Ludo boards (5p detailed, 6p still a rough
/// placeholder).
///
/// 5p geometry (matches the LudoKing 5p reference):
///   - 5 radial arms at 72° intervals starting from the bottom (player 1).
///   - Each arm is 3 cells wide × 6 cells long. The middle column holds the
///     5 colored home-stretch cells; the side columns hold ring cells.
///   - A triangular colored BASE sits at the outer end of each arm, with a
///     smaller white token triangle inside for the 4 tokens.
///   - A central PENTAGON home is split into 5 colored triangles converging
///     to a small DARK pentagon at the very center (where the dice sits).
class _PolygonBoardPainter extends CustomPainter {
  final int n;
  const _PolygonBoardPainter({required this.n});

  // Standard Ludo King wedge colors going CCW visual (= CCW math because +y
  // is down) from the bottom (player 1).
  static const Map<int, List<Color>> _wedgeColors = {
    5: [Color(0xFF3DA4EC), Color(0xFFFF8A2C), Color(0xFF4FAE5D),
        Color(0xFFE94B4B), Color(0xFFFFCE2E)],
    6: [Color(0xFF3DA4EC), Color(0xFFFF8A2C), Color(0xFF4FAE5D),
        Color(0xFFE94B4B), Color(0xFFFFCE2E), Color(0xFF9B59B6)],
  };

  /// Cell-grid parameters for the 5p board.
  static const int _innerCells5 = 3;  // central pentagon "radius" in cells
  static const int _armLen5     = 6;  // arm length in cells
  static const int _armWidth5   = 3;  // arm width in cells
  static const int _baseExtra5  = 3;  // base extension beyond arm, in cells

  /// Total span of the 5p board in cells (diameter / 2 + margin).
  static double _totalCells5() =>
      (_innerCells5 + _armLen5 + _baseExtra5).toDouble();

  /// Returns the fraction of board side where the dice should be positioned
  /// (i.e. inscribed circle radius of the central black pentagon, divided by
  /// the board's smaller side). Used by [BoardView] to size the central dice.
  static double diceSizeFraction(int n) {
    if (n == 5) {
      return 0.07;
    }
    return 0.06; // 6p placeholder
  }

  /// Cell size for the 5p layout given a square viewport of [shortSide].
  static double cellSize5(double shortSide) =>
      shortSide / (2 * (_totalCells5() + 1));

  /// The 65 ring cell centers for the 5-player board, going CW visually
  /// starting at the outer end of arm 0 (player 1, bottom) LEFT column.
  /// Section k (cells 13k..13k+12) covers arm k's left column going inward
  /// (6 cells), one transition cell at the central pentagon vertex between
  /// arm k and arm k+1, and arm (k+1)'s right column going outward (6 cells).
  static List<Offset> ringPositions5(double cx, double cy, double c) {
    final cells = <Offset>[];
    final rInner = _innerCells5 * c;
    for (int k = 0; k < 5; k++) {
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final rHat = Offset(math.cos(theta), math.sin(theta));
      final tHat = Offset(-math.sin(theta), math.cos(theta));

      // 6 cells along arm k's LEFT col (+tHat), going INWARD (row 5 → 0).
      for (int row = 5; row >= 0; row--) {
        final r = rInner + (row + 0.5) * c;
        cells.add(Offset(
          cx + r * rHat.dx + c * tHat.dx,
          cy + r * rHat.dy + c * tHat.dy,
        ));
      }

      // 1 transition cell at the central pentagon vertex between arm k and
      // arm k+1 (at angle theta + 36°).
      final transAngle = theta + math.pi / 5;
      cells.add(Offset(
        cx + rInner * math.cos(transAngle),
        cy + rInner * math.sin(transAngle),
      ));

      // 6 cells along arm (k+1)'s RIGHT col (-tHat), going OUTWARD (row 0 → 5).
      final kNext = (k + 1) % 5;
      final thetaN = math.pi / 2 + (2 * math.pi / 5) * kNext;
      final rHatN = Offset(math.cos(thetaN), math.sin(thetaN));
      final tHatN = Offset(-math.sin(thetaN), math.cos(thetaN));
      for (int row = 0; row < 6; row++) {
        final r = rInner + (row + 0.5) * c;
        cells.add(Offset(
          cx + r * rHatN.dx - c * tHatN.dx,
          cy + r * rHatN.dy - c * tHatN.dy,
        ));
      }
    }
    return cells;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Backdrop.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1A2541),
    );
    if (n == 5) {
      _paint5(canvas, size);
    } else {
      _paint6Rough(canvas, size);
    }
  }

  /// Detailed 5-player board: 5 radial arms (3×6 cells), 5 triangular bases,
  /// central colored pentagon with 5 sections + small dark inner pentagon.
  void _paint5(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final c = cellSize5(math.min(size.width, size.height));
    final rInner    = _innerCells5 * c;
    final rArmOuter = rInner + _armLen5 * c;
    final rBaseOuter = rArmOuter + _baseExtra5 * c;
    final halfArm = (_armWidth5 / 2) * c;
    final halfBase = halfArm + c; // base widens by 1 cell on each side
    final colors = _wedgeColors[5]!;

    final gridPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, c * 0.04);

    for (int k = 0; k < 5; k++) {
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final rHat = Offset(math.cos(theta), math.sin(theta));
      final tHat = Offset(-math.sin(theta), math.cos(theta));
      final color = colors[k];

      Offset p(double r, double t) =>
          Offset(cx + r * rHat.dx + t * tHat.dx,
                 cy + r * rHat.dy + t * tHat.dy);

      // 1) ARM background (white rectangle from rInner to rArmOuter).
      final armPath = Path()
        ..moveTo(p(rInner, -halfArm).dx, p(rInner, -halfArm).dy)
        ..lineTo(p(rArmOuter, -halfArm).dx, p(rArmOuter, -halfArm).dy)
        ..lineTo(p(rArmOuter, halfArm).dx, p(rArmOuter, halfArm).dy)
        ..lineTo(p(rInner, halfArm).dx, p(rInner, halfArm).dy)
        ..close();
      canvas.drawPath(armPath, Paint()..color = Colors.white);

      // 2) HOME STRETCH: 5 colored cells in the middle column.
      // Inner cell (closest to center) = row 0, outer cell = row 4.
      // The 6th cell (row 5) at the outer end of middle column is the ring
      // entry cell into the home stretch (white, but reserved for the entry).
      for (int row = 0; row < 5; row++) {
        final r0 = rInner + row * c;
        final r1 = r0 + c;
        final cellPath = Path()
          ..moveTo(p(r0, -0.5 * c).dx, p(r0, -0.5 * c).dy)
          ..lineTo(p(r1, -0.5 * c).dx, p(r1, -0.5 * c).dy)
          ..lineTo(p(r1, 0.5 * c).dx, p(r1, 0.5 * c).dy)
          ..lineTo(p(r0, 0.5 * c).dx, p(r0, 0.5 * c).dy)
          ..close();
        canvas.drawPath(cellPath, Paint()..color = color);
      }

      // 3) GRID lines on the arm (3 cols × 6 rows).
      for (int i = 0; i <= _armWidth5; i++) {
        final t = (i - _armWidth5 / 2) * c;
        canvas.drawLine(p(rInner, t), p(rArmOuter, t), gridPaint);
      }
      for (int i = 0; i <= _armLen5; i++) {
        final r = rInner + i * c;
        canvas.drawLine(p(r, -halfArm), p(r, halfArm), gridPaint);
      }

      // 4) BASE trapezoid (colored, widening outward) at the outer end of
      // the arm.
      final basePath = Path()
        ..moveTo(p(rArmOuter, -halfArm).dx,  p(rArmOuter, -halfArm).dy)
        ..lineTo(p(rBaseOuter, -halfBase).dx, p(rBaseOuter, -halfBase).dy)
        ..lineTo(p(rBaseOuter,  halfBase).dx, p(rBaseOuter,  halfBase).dy)
        ..lineTo(p(rArmOuter,   halfArm).dx,  p(rArmOuter,   halfArm).dy)
        ..close();
      canvas.drawPath(basePath, Paint()..color = color);

      // 5) Inner WHITE token triangle inside the base: an isoceles triangle
      // pointing toward the center (apex inward).
      final innerInset = 0.30; // fraction of base width/height to inset
      final apexInner = p(rArmOuter + (rBaseOuter - rArmOuter) * 0.25, 0);
      final outerLeft  = p(rBaseOuter - (rBaseOuter - rArmOuter) * 0.15,
                           -halfBase + (halfBase * 2) * innerInset);
      final outerRight = p(rBaseOuter - (rBaseOuter - rArmOuter) * 0.15,
                            halfBase - (halfBase * 2) * innerInset);
      final tokenTri = Path()
        ..moveTo(apexInner.dx, apexInner.dy)
        ..lineTo(outerLeft.dx, outerLeft.dy)
        ..lineTo(outerRight.dx, outerRight.dy)
        ..close();
      canvas.drawPath(tokenTri, Paint()..color = Colors.white);
    }

    // 6) Central HOME pentagon: 5 colored triangles converging at center.
    for (int k = 0; k < 5; k++) {
      final color = colors[k];
      final theta = math.pi / 2 + (2 * math.pi / 5) * k;
      final aLeft  = theta - math.pi / 5;
      final aRight = theta + math.pi / 5;
      final left = Offset(
          cx + rInner * math.cos(aLeft), cy + rInner * math.sin(aLeft));
      final right = Offset(
          cx + rInner * math.cos(aRight), cy + rInner * math.sin(aRight));
      final tri = Path()
        ..moveTo(cx, cy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = color);
    }

    // 7) Inner small DARK pentagon (the dice slot).
    final rBlack = rInner * 0.55;
    final blackPath = Path();
    for (int i = 0; i < 5; i++) {
      final a = math.pi / 2 + (2 * math.pi / 5) * i;
      final px = cx + rBlack * math.cos(a);
      final py = cy + rBlack * math.sin(a);
      if (i == 0) {
        blackPath.moveTo(px, py);
      } else {
        blackPath.lineTo(px, py);
      }
    }
    blackPath.close();
    canvas.drawPath(blackPath, Paint()..color = const Color(0xFF1A2541));
  }

  /// 6-player placeholder: same rough wedge sketch as before (to be detailed
  /// after the 5p layout is locked in).
  void _paint6Rough(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = math.min(cx, cy) * 0.92;
    Offset vert(int i) {
      final a = math.pi / 2 - math.pi / 6 + (math.pi / 3) * i;
      return Offset(cx + R * math.cos(a), cy + R * math.sin(a));
    }
    final outer = Path()..moveTo(vert(0).dx, vert(0).dy);
    for (int i = 1; i < 6; i++) {
      outer.lineTo(vert(i).dx, vert(i).dy);
    }
    outer.close();
    canvas.drawPath(outer, Paint()..color = Colors.white);
    final colors = _wedgeColors[6]!;
    const insetFactor = 0.82;
    for (int i = 0; i < 6; i++) {
      final v0 = vert(i);
      final v1 = vert((i + 1) % 6);
      final p0 = Offset(cx + (v0.dx - cx) * insetFactor,
                        cy + (v0.dy - cy) * insetFactor);
      final p1 = Offset(cx + (v1.dx - cx) * insetFactor,
                        cy + (v1.dy - cy) * insetFactor);
      final wedge = Path()
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(cx, cy)
        ..close();
      canvas.drawPath(wedge, Paint()..color = colors[i]);
    }
    final innerR = R * 0.14;
    final inner = Path();
    for (int i = 0; i < 6; i++) {
      final a = math.pi / 2 - math.pi / 6 + (math.pi / 3) * i;
      final x = cx + innerR * math.cos(a);
      final y = cy + innerR * math.sin(a);
      if (i == 0) {
        inner.moveTo(x, y);
      } else {
        inner.lineTo(x, y);
      }
    }
    inner.close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFF1A2541));
  }

  @override
  bool shouldRepaint(covariant _PolygonBoardPainter old) => old.n != n;
}

/// Decoded frames of a GIF, shared across all pawns of the same color so we
/// pay the decode cost only once per asset.
/// Purge le cache de décodage des animations de pions. RÉSERVÉ aux tests —
/// voir [_GifFrames.evictAll] pour le pourquoi.
@visibleForTesting
void resetPawnAnimationCache() => _GifFrames.evictAll();

class _GifFrames {
  final List<ui.Image> images;
  final List<Duration> durations;
  /// Bounding box of non-transparent pixels in frame 0 (the "rest" pose).
  /// In native pixel coords of the GIF canvas. Used by `_PawnAnimatedGif`
  /// to size and position the token consistently across anims with
  /// different canvas paddings (e.g. idle_#1 64×93 vs idle_#5 82×123 —
  /// both have a 58×86 content bbox).
  final Rect contentBbox;
  _GifFrames(this.images, this.durations, this.contentBbox);

  static final Map<String, Future<_GifFrames>> _cache = {};

  /// Vide le cache. RÉSERVÉ aux tests : chaque `testWidgets` tourne dans
  /// sa propre zone asynchrone, et une future mise en cache par un test
  /// précédent ne se résout jamais dans la suivante — le sondage des
  /// assets du second test restait suspendu dessus indéfiniment.
  @visibleForTesting
  static void evictAll() => _cache.clear();

  static Future<_GifFrames> load(String asset) {
    return _cache.putIfAbsent(asset, () async {
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final images = <ui.Image>[];
      final durations = <Duration>[];
      for (int i = 0; i < codec.frameCount; i++) {
        final f = await codec.getNextFrame();
        images.add(f.image);
        durations.add(f.duration);
      }
      codec.dispose();
      final bbox = await _findContentBbox(images.first);
      return _GifFrames(images, durations, bbox);
    });
  }

  /// Scan the image's RGBA bytes to find the bounding box of pixels with
  /// alpha > 0. Returns the full image rect if everything is opaque or
  /// the data can't be read.
  static Future<Rect> _findContentBbox(ui.Image img) async {
    final byteData =
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final W = img.width;
    final H = img.height;
    final fullRect = Rect.fromLTWH(0, 0, W.toDouble(), H.toDouble());
    if (byteData == null) return fullRect;
    final data = byteData.buffer.asUint8List();
    int minX = W, minY = H, maxX = -1, maxY = -1;
    for (int y = 0; y < H; y++) {
      final row = y * W * 4;
      for (int x = 0; x < W; x++) {
        final alpha = data[row + x * 4 + 3];
        if (alpha > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return fullRect;
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }
}

/// Renders an idle pawn GIF, with the first frame appearing as soon as the
/// asset is decoded. After [sequentialStartDelayMs] elapses, the widget
/// starts cycling through frames at the pace described by the GIF metadata.
/// Each instance keeps its OWN `_frameIdx` so the 16 pawns visibly desync.
class _PawnAnimatedGif extends StatefulWidget {
  final String asset;
  final int sequentialStartDelayMs;
  /// Debug: when true, overlay a red rectangle of the GIF's NATIVE canvas
  /// size (after BoxFit.contain scaling) so we see the actual rendered
  /// footprint, not the parent's layout bbox.
  final bool showCanvas;
  /// When true, freeze the animation on frame 0 (rest pose). Only the
  /// current player's pawns animate — the other 12 stand still so the
  /// board isn't visually overloaded.
  final bool paused;
  const _PawnAnimatedGif({
    super.key,
    required this.asset,
    required this.sequentialStartDelayMs,
    this.showCanvas = false,
    this.paused = false,
  });

  @override
  State<_PawnAnimatedGif> createState() => _PawnAnimatedGifState();
}

class _PawnAnimatedGifState extends State<_PawnAnimatedGif>
    with SingleTickerProviderStateMixin {
  _GifFrames? _frames;
  /// True when we can't display the pawn (empty asset path, asset not in
  /// the bundle, or decode failed). The widget then renders a clearly
  /// visible red "X" placeholder instead of staying blank.
  bool _failed = false;
  int _frameIdx = 0;
  Ticker? _ticker;
  Duration _accum = Duration.zero;
  Duration? _lastTickTime;
  /// Per-pawn playback rate in [0.8, 1.2]. Drawn once at first build (the
  /// widget's state is preserved across rebuilds via the parent's
  /// ValueKey, so this value stays stable for the lifetime of the pawn).
  /// Variations de-synchronize the 16 pawns naturally on top of the
  /// startup `sequentialStartDelayMs` jitter.
  late final double _speed =
      0.8 + math.Random().nextDouble() * 0.4;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _PawnAnimatedGif oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the asset prop changed under a preserved State (same ValueKey but
    // new GIF picked by _bootstrap on hot reload, etc.), reload frames from
    // scratch so the displayed animation matches the current asset.
    if (widget.asset != oldWidget.asset) {
      _ticker?.dispose();
      _ticker = null;
      _frames = null;
      _frameIdx = 0;
      _accum = Duration.zero;
      _lastTickTime = null;
      _init();
      return;
    }
    // Pause/resume on `paused` toggle. Only the current player's pawns
    // run their idle anim; everyone else is frozen on frame 0.
    if (widget.paused != oldWidget.paused) {
      if (widget.paused) {
        _ticker?.stop();
        setState(() {
          _frameIdx = 0;
          _accum = Duration.zero;
          _lastTickTime = null;
        });
      } else if (_frames != null && _ticker == null) {
        _ticker = createTicker(_onTick)..start();
      } else {
        _ticker?.start();
      }
    }
  }

  Future<void> _init() async {
    if (widget.asset.isEmpty) {
      // No asset assigned for this pawn (e.g. no idle variant available
      // for its color). Show the missing-asset placeholder.
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final frames = await _GifFrames.load(widget.asset);
      if (!mounted) return;
      setState(() => _frames = frames);

      await Future<void>.delayed(
        Duration(milliseconds: widget.sequentialStartDelayMs),
      );
      if (!mounted) return;
      // Skip the ticker entirely if this pawn shouldn't animate.
      if (!widget.paused) {
        _ticker = createTicker(_onTick)..start();
      }
    } catch (e, st) {
      debugPrint('Animated GIF load failed for ${widget.asset}: $e\n$st');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick(Duration elapsed) {
    final frames = _frames;
    if (frames == null || frames.images.isEmpty) return;

    _lastTickTime ??= elapsed;
    final dt = elapsed - _lastTickTime!;
    _lastTickTime = elapsed;
    // Scale dt by the per-pawn speed so each pion advances frames at its
    // own pace (0.8..1.2 of the WebP's native cadence).
    _accum += dt * _speed;

    bool changed = false;
    // Loop over frames until the accumulated time fits in the current one.
    while (_accum >= frames.durations[_frameIdx] &&
        frames.durations[_frameIdx] > Duration.zero) {
      _accum -= frames.durations[_frameIdx];
      _frameIdx = (_frameIdx + 1) % frames.images.length;
      changed = true;
    }
    if (changed) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox.expand(
        child: CustomPaint(painter: _MissingTokenPainter()),
      );
    }
    final frames = _frames;
    if (frames == null) return const SizedBox.expand();
    final imgW = frames.images[_frameIdx].width.toDouble();
    final imgH = frames.images[_frameIdx].height.toDouble();
    final bbox = frames.contentBbox; // non-transparent extent

    // Scaling rule: every pawn's CONTENT (the non-transparent token area)
    // renders at the same on-screen height = container height. The canvas
    // pixels around the content are extra padding from the artist (room
    // for animations) and must NOT influence the displayed size — that's
    // why we scale by `bbox.height`, not `imgH`.
    //
    // Position the image so the content bbox center lands on the
    // container center. Tokens with smaller / larger canvases or off-
    // center content (e.g. idle_#5 with extra top padding) still render
    // identically because we anchor by the content bbox, not the canvas.
    return LayoutBuilder(
      builder: (ctx, c) {
        final scale = c.maxHeight / bbox.height;
        final imgRenderW = imgW * scale;
        final imgRenderH = imgH * scale;
        final left = c.maxWidth / 2 - bbox.center.dx * scale;
        final top  = c.maxHeight / 2 - bbox.center.dy * scale;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              width: imgRenderW,
              height: imgRenderH,
              child: RawImage(image: frames.images[_frameIdx]),
            ),
            if (widget.showCanvas)
              // Red rectangle around the GIF's NATIVE canvas as rendered.
              Positioned(
                left: left,
                top: top,
                width: imgRenderW,
                height: imgRenderH,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xFFD32F2F), width: 1.5),
                      color: const Color(0x14D32F2F),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Visible placeholder drawn when a pawn's idle GIF asset is missing
/// (e.g. Studio hasn't produced the file yet for this color/variant).
/// Renders a red rectangle with a white "X" inside the visible-token
/// area of the bbox so the missing slot is obvious in-game.
class _MissingTokenPainter extends CustomPainter {
  const _MissingTokenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The full bbox is much bigger than the visible token (visible content
    // sits at ~48.6 %..68.0 % vertical, ~50 % horizontal). Draw the marker
    // roughly where the token would be so it doesn't look like a giant
    // banner.
    final w = size.width * 0.55;
    final h = size.height * 0.22;
    final cx = size.width / 2;
    final cy = size.height * 0.583;
    final rect = Rect.fromCenter(
        center: Offset(cx, cy), width: w, height: h);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFD32F2F));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final pad = math.min(w, h) * 0.18;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = math.max(3.0, math.min(w, h) * 0.10)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(rect.left + pad, rect.top + pad),
        Offset(rect.right - pad, rect.bottom - pad), p);
    canvas.drawLine(
        Offset(rect.right - pad, rect.top + pad),
        Offset(rect.left + pad, rect.bottom - pad), p);
  }

  @override
  bool shouldRepaint(covariant _MissingTokenPainter old) => false;
}

/// Small clickable dice button used in the debug panel to force a specific
/// dice value (1..6) for deterministic testing.
class _MiniDiceButton extends StatelessWidget {
  final int value;
  final VoidCallback onTap;
  final bool selected;
  const _MiniDiceButton({
    required this.value,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                color: selected ? cs.onPrimary : cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dice at rest, rendered from a colored face PNG keyed by [playerColor] and
/// [value]. When [playerColor] is null we use the generic white dice (used by
/// the 5/6-player center slot).
/// Halo CLIGNOTANT posé sur le Yard (la base) du siège dont c'est le tour.
///
/// Il double la couleur du dé central : les deux indiquent à qui de jouer,
/// que le siège soit tenu par un humain ou par l'ordinateur. Il pulse en
/// continu dans la couleur du joueur, et se FIGE pendant la pause : un
/// plateau gelé ne doit plus respirer du tout.
class YardBlink extends StatefulWidget {
  /// Couleur logique du siège — exposée pour que les tests puissent
  /// vérifier QUEL Yard clignote sans lire des pixels.
  final PlayerColor playerColor;

  /// Couleur peinte (celle du plateau pour ce siège).
  final Color color;

  /// Plateau en pause : la pulsation s'arrête net et reprend où elle en
  /// était, comme tout le reste du jeu.
  final bool paused;

  /// Épaisseur du liseré, déjà mise à l'échelle de la case par l'appelant.
  final double strokeWidth;

  const YardBlink({
    super.key,
    required this.playerColor,
    required this.color,
    required this.paused,
    required this.strokeWidth,
  });

  @override
  State<YardBlink> createState() => YardBlinkState();
}

class YardBlinkState extends State<YardBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  /// Visible dans les tests : la pulsation bat-elle en ce moment ?
  bool get animating => _pulse.isAnimating;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      // Un battement par seconde environ : assez vif pour attirer l'œil,
      // assez lent pour ne pas fatiguer sur toute une partie.
      duration: const Duration(milliseconds: 550),
    );
    if (!widget.paused) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(YardBlink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && _pulse.isAnimating) {
      _pulse.stop(); // gelé sur sa luminosité du moment
    } else if (!widget.paused && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Jamais dans le chemin des clics : le Yard reste entièrement cliquable
    // (pions en base, étiquette du joueur…).
    return IgnorePointer(
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _pulse,
          curve: Curves.easeInOut,
        ).drive(Tween(begin: 0.15, end: 0.95)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.strokeWidth * 2),
            border: Border.all(
              color: widget.color,
              width: widget.strokeWidth,
            ),
            // Teinte CONTENUE dans le Yard. Un boxShadow débordait en voile
            // blanchâtre sur les cases de l'anneau voisines — les pions y
            // devenaient laiteux. Le halo reste chez lui.
            color: widget.color.withValues(alpha: 0.20),
          ),
        ),
      ),
    );
  }
}

/// L'anneau posé aux pieds d'un pion, dans SA couleur. Un disque très
/// pâle au centre, un anneau franc autour : le pion s'y pose au lieu de
/// flotter sur la case.
/// LE HALO du pion : le cerceau posé à ses pieds.
///
///   * AU REPOS c'est un anneau plein, qui rattache le pion à sa case.
///   * QUAND C'EST À SA COULEUR DE JOUER il s'ouvre en TIRETS et se met à
///     tourner — vite, et sans s'arrêter. Rien d'autre ne tourne sur le
///     plateau : c'est le seul mouvement, et il désigne le camp qui a la
///     main sans qu'on ait à lire quoi que ce soit.
///
/// Il ne bouge PAS pendant le saut. Il est dessiné dans le même widget
/// que le pion — donc à la même position, à la même image près — mais
/// hors de la transformation du saut : le pion s'élève, le halo reste au
/// sol, et aucun décalage n'est possible puisqu'il n'y a qu'une position.
/// UN SON DU JEU, joué à VOIX MULTIPLES.
///
/// Le pas dure 400 ms, à plein niveau du début à la fin — ce n'est pas un
/// déclic qui s'éteint, c'est une note tenue. Or un pion change de case
/// toutes les 190 ms. Avec un seul lecteur, chaque pas couperait le
/// précédent en plein milieu et l'on n'entendrait qu'un hachis.
///
/// Plusieurs voix tournantes règlent la question : la première est
/// réutilisée au bout de `voices × 190 ms`, bien après la fin du son
/// qu'elle jouait. Aucun déclenchement n'est jamais interrompu — ils se
/// superposent, ce qui est le comportement normal d'un son de jeu
/// déclenché en rafale.
///
/// Les sons rares — la capture, la sortie de base — se contentent de deux
/// voix : ils ne partent jamais en rafale, mais deux pions peuvent se
/// faire manger d'un coup.
class _Sfx {
  _Sfx(this._asset, {int voices = 2}) : _voices = voices;

  /// `audioplayers` préfixe tout seul par `assets/` : le chemin part donc
  /// de l'intérieur du dossier.
  final String _asset;
  final int _voices;

  final List<AudioPlayer> _pool = [];
  int _next = 0;
  Future<void>? _warmup;

  /// Une panne du greffon ne doit pas se rejouer à chaque case. On la
  /// constate une fois, et l'on se tait pour de bon.
  bool _dead = false;

  /// Les lecteurs se préparent à la PREMIÈRE demande, pas au démarrage :
  /// tant qu'aucun pion ne bouge, il n'y a aucune raison de réveiller un
  /// greffon natif ni de décoder quoi que ce soit.
  Future<void> _warm() async {
    for (var i = 0; i < _voices; i++) {
      final p = AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      // Basse latence : le greffon garde le son décodé en mémoire. Le web
      // ne connaît pas ce mode ; son refus est sans conséquence, il joue
      // déjà depuis un cache.
      try {
        await p.setPlayerMode(PlayerMode.lowLatency);
      } catch (_) {
        // tant pis, la latence par défaut suffit
      }
      await p.setSource(AssetSource(_asset));
      _pool.add(p);
    }
  }

  /// Prépare les voix SANS jouer. À appeler au démarrage : c'est ce
  /// travail-là qui retardait le premier son de chaque sorte.
  Future<void> warmUp() async {
    if (_dead) return;
    try {
      await (_warmup ??= _warm());
    } catch (e) {
      _dead = true;
      debugPrint('[son] $_asset muet : $e');
    }
  }

  void play() {
    if (_dead) return;
    unawaited(_playOne());
  }

  Future<void> _playOne() async {
    final AudioPlayer p;
    try {
      await (_warmup ??= _warm());
      if (_pool.isEmpty) return;
      p = _pool[_next];
      _next = (_next + 1) % _pool.length;
    } catch (e) {
      // Là, c'est la BANQUE qui ne s'ouvre pas — greffon absent, fichier
      // introuvable. Rien ne sortira jamais : on cesse d'essayer.
      _dead = true;
      debugPrint('[son] $_asset muet : $e');
      return;
    }
    try {
      // On rembobine avant de relancer : la voix qui revient dans la ronde
      // a fini sa lecture et est restée sur sa dernière image. Le zéro est
      // le SEUL déplacement que le mode basse latence accepte sur Android
      // — il y est traité comme un arrêt suivi d'un redépart.
      await p.seek(Duration.zero);
      await p.resume();
    } catch (e) {
      // Un déclenchement raté ne condamne PAS les suivants. Le navigateur
      // refuse par exemple de jouer avant le premier geste de
      // l'utilisateur : ce serait une raison absurde de rendre le jeu
      // muet pour toute la partie.
      if (!_grumbled) {
        _grumbled = true;
        debugPrint('[son] $_asset : déclenchement raté ($e)');
      }
    }
  }

  /// On ne se plaint qu'UNE fois par son : sinon un refus du navigateur
  /// remplirait la console à chaque case.
  bool _grumbled = false;

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
    _pool.clear();
    _warmup = null;
  }
}

class _PawnHaloView extends StatefulWidget {
  const _PawnHaloView({required this.color, required this.spinning});

  final Color color;

  /// C'est au tour de cette couleur : l'anneau passe en tirets tournants.
  final bool spinning;

  @override
  State<_PawnHaloView> createState() => _PawnHaloViewState();
}

class _PawnHaloViewState extends State<_PawnHaloView>
    with TickerProviderStateMixin {
  /// La rotation. 620 ms le tour : assez vite pour qu'on la voie du coin
  /// de l'œil, assez lent pour que les tirets restent des tirets et non
  /// une bague floue.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  /// L'ouverture des tirets : l'anneau plein s'AJOURE quand le tour
  /// arrive, se referme quand il repart.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.spinning ? 1.0 : 0.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _PawnHaloView old) {
    super.didUpdateWidget(old);
    if (widget.spinning == old.spinning) return;
    if (widget.spinning) {
      _spin.repeat();
      _open.forward();
    } else {
      _open.reverse().whenComplete(() {
        if (mounted && !widget.spinning) _spin.stop();
      });
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _open]),
      builder: (context, _) => CustomPaint(
        painter: _PawnHalo(
          rgb: widget.color,
          turn: _spin.value,
          dashed: Curves.easeOut.transform(_open.value),
        ),
      ),
    );
  }
}

class _PawnHalo extends CustomPainter {
  const _PawnHalo({required this.rgb, this.turn = 0.0, this.dashed = 0.0});

  /// La couleur du pion, telle que le plateau la peint.
  final Color rgb;

  /// Rotation des tirets, de 0 à 1 pour un tour complet.
  final double turn;

  /// 0 = anneau plein, 1 = cercle de tirets.
  final double dashed;

  /// HUIT tirets, pas douze.
  ///
  /// Douze faisaient un pointillé fin qui, en tournant, se lisait comme
  /// un anneau continu : le mouvement disparaissait. Huit tirets épais
  /// séparés par de vrais vides laissent voir CHAQUE tiret passer — c'est
  /// ce qui fait qu'on sent la rotation, et non qu'on la déduit.
  static const int _dashes = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    // UN OVALE, PAS UN CERCLE : l'anneau est posé à plat sur la case et
    // vu de biais, comme dans Ludo King. Un cercle se dresse devant le
    // pion, monte jusqu'aux têtes voisines et les traverse.
    //
    // Les rayons se prennent donc séparément sur la boîte, que
    // l'appelant fait large et basse.
    final rx = size.width / 2 * 0.86;
    final ry = size.height / 2 * 0.86;
    // Épais : un tiret fin sur une case blanche ne se voit pas, et sur
    // une case de sa propre couleur pas du tout. La mesure se prend sur
    // la LARGEUR — sur la hauteur écrasée, elle donnerait un cheveu.
    final stroke = math.max(2.2, rx * 0.32);

    // L'ombre au sol. Elle reste dans les deux états — c'est elle qui
    // pose le pion sur sa case.
    canvas.drawOval(
        Rect.fromCenter(center: c, width: rx * 2.10, height: ry * 2.10),
        Paint()..color = rgb.withValues(alpha: 0.16));

    final rect = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);

    if (dashed < 0.02) {
      canvas.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..color = rgb.withValues(alpha: 0.85));
      return;
    }
    final step = 2 * math.pi / _dashes;
    // Le vide occupe presque la moitié du pas : c'est CE vide qu'on voit
    // défiler. Un écart étroit et le cercle redevient continu.
    final gap = step * 0.46 * dashed;
    final sweep = step - gap;
    final start = turn * 2 * math.pi;

    // Trois passes, du dessous vers le dessus : un cerne sombre pour
    // détacher le tiret de n'importe quel fond, la couleur du pion, puis
    // une arête claire. C'est ce contraste qui rend le tiret DENSE.
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 1.34
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF0A1018).withValues(alpha: 0.34 * dashed);
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = rgb;
    final gleam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.30
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.85 * dashed);

    for (var i = 0; i < _dashes; i++) {
      final a = start + i * step;
      canvas.drawArc(rect, a, sweep, false, shade);
    }
    for (var i = 0; i < _dashes; i++) {
      final a = start + i * step;
      canvas.drawArc(rect, a, sweep, false, body);
    }
    for (var i = 0; i < _dashes; i++) {
      final a = start + i * step;
      canvas.drawArc(rect, a, sweep, false, gleam);
    }
  }

  @override
  bool shouldRepaint(covariant _PawnHalo old) =>
      old.rgb != rgb || old.turn != turn || old.dashed != dashed;
}

/// Un `AssetImage` que l'on peut redemander À VOLONTÉ.
///
/// `AssetImage` s'estime égal à un autre dès que le chemin est le même.
/// `Image` en conclut qu'il n'y a rien à refaire et garde son flux — or
/// c'est justement le flux, terminé, qu'il faut renouveler pour rejouer
/// une animation qui ne boucle pas.
///
/// [seq] n'entre PAS dans la clé de cache : c'est bien le même fichier
/// qu'on veut. Il n'entre que dans l'égalité, ce qui suffit à faire
/// redemander le flux. L'entrée de cache, elle, est évincée à part.
class _ReplayableAsset extends AssetImage {
  const _ReplayableAsset(super.assetName, this.seq);

  /// Le numéro du lancer. Change → le fournisseur n'est plus le même.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is _ReplayableAsset &&
      other.assetName == assetName &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(assetName, seq);
}

class _DiceFace extends StatelessWidget {
  final int value;

  /// Couleur du joueur dont c'est le tour : le dé la reprend à chaque
  /// passage de main. `null` = dé blanc neutre (plateaux 5/6 joueurs, où
  /// l'interaction n'est pas encore câblée).
  final PlayerColor? playerColor;

  /// Pendant le lancer, on affiche le WebP animé du Studio plutôt que la
  /// face fixe. Il joue UNE fois — `repetitionCount` vaut 0 — et s'arrête
  /// sur la valeur sortie.
  final bool rolling;

  /// Numéro du lancer : il entre dans la clé de l'image pour que
  /// l'animation REPARTE même si la couleur et la valeur n'ont pas changé.
  final int throwSeq;

  const _DiceFace({
    required this.value,
    this.playerColor,
    this.rolling = false,
    this.throwSeq = 0,
  });

  String get _assetPath {
    final colorName = playerColor?.name ?? 'white';
    final v = value.clamp(1, 6);
    return rolling
        ? 'AnimStock/Dices/WEBP/Dice_${colorName}_throw_$v.webp'
        : 'AnimStock/Dices/PNG/Dice_${v}_$colorName.png';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Image(
        // ── POURQUOI PAS `Image.asset` NI UNE CLÉ QUI CHANGE ──────────
        //
        // Rejouer un WebP qui ne boucle pas demande DEUX choses, et elles
        // se contrarient :
        //
        //   1. que le flux d'images reparte de zéro — sinon on récupère
        //      celui d'avant, déjà terminé, et le dé s'affiche direct sur
        //      sa dernière face ;
        //   2. que l'État du widget SURVIVE — c'est lui qui garde la
        //      dernière image affichée, et donc qui évite le trou.
        //
        // Une clé qui change satisfait (1) et casse (2) : Flutter jette
        // l'État, la case est vide le temps du décodage, et l'on voyait
        // le halo du plateau à travers le dé — le « flash » à chaque
        // lancer.
        //
        // D'où ce fournisseur : même fichier, mais INÉGAL au précédent
        // dès que le numéro de lancer change. `Image` le voit changer et
        // redemande le flux (1) sans que l'État soit recréé (2) ; le
        // `gaplessPlayback` garde alors la face précédente à l'écran
        // pendant le décodage. L'éviction du cache, elle, se fait dans
        // `_roll` — sans elle le flux rendu serait celui d'avant.
        image: _ReplayableAsset(_assetPath, rolling ? throwSeq : 0),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}

class _PlayerLabel extends StatelessWidget {
  final String name;
  final Color color;
  final double fontSize;
  const _PlayerLabel({
    required this.name,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    // Padding scales with fontSize so the pill stays proportional on small
    // boards (Smartphone preset). FittedBox prevents long names from
    // overflowing — they shrink instead of clipping.
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize * 0.55,
        vertical: fontSize * 0.25,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(fontSize * 0.45),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2)),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

/// Thumbnail of a static asset that pops up a centered, enlarged view via
/// an [OverlayEntry] while the mouse hovers it. Used in the right panel for
/// the board nomenclature reference image.
class _HoverZoomImage extends StatefulWidget {
  final String asset;
  const _HoverZoomImage({required this.asset});

  @override
  State<_HoverZoomImage> createState() => _HoverZoomImageState();
}

class _HoverZoomImageState extends State<_HoverZoomImage> {
  OverlayEntry? _entry;

  void _show() {
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (ctx) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                  maxHeight: 800,
                ),
                child: Image.asset(widget.asset, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      onEnter: (_) => _show(),
      onExit: (_) => _hide(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(widget.asset, fit: BoxFit.contain),
      ),
    );
  }
}

/// One capture explosion. Drives its own AnimationController (vsync from
/// the parent State) and exposes the current `progress` (0..1). The
/// painter reads progress to render particles + shockwave + flash.
///
/// Position is resolved at paint time from [targetPawn]'s NEW cell so
/// the explosion stays anchored even if the board resizes mid-anim.
class ExplosionFx {
  static const Duration totalDuration = Duration(milliseconds: 700);
  final Color colorRgb;
  final Pawn targetPawn;
  final AnimationController controller;
  ExplosionFx({
    required this.colorRgb,
    required this.targetPawn,
    required TickerProvider vsync,
  }) : controller =
            AnimationController(vsync: vsync, duration: totalDuration);
  void start() => controller.forward();
}

/// Paints one explosion: a central white flash (expanding + fading), an
/// outer shockwave ring (colored, expanding), and 12 particles flying
/// outward from the center.
class _ExplosionPainter extends CustomPainter {
  final double progress;       // 0..1
  final Color color;
  final Offset center;
  final double scale;          // cell-relative radius unit (so the FX is
                               // sized consistently across resolutions)
  _ExplosionPainter({
    required this.progress,
    required this.color,
    required this.center,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    // Flash: large white opaque at start, shrinks (visually) by fading.
    final flashAlpha = (1.0 - t) * 0.85;
    if (flashAlpha > 0) {
      final fr = scale * (0.35 + 0.45 * t);
      canvas.drawCircle(
        center, fr,
        Paint()..color = Colors.white.withValues(alpha: flashAlpha),
      );
    }
    // Shockwave: ring outline expanding outward, alpha fading.
    final ringR = scale * (0.4 + 1.4 * t);
    final ringAlpha = (1.0 - t);
    if (ringAlpha > 0) {
      canvas.drawCircle(
        center, ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, scale * 0.06 * (1 - t * 0.5))
          ..color = color.withValues(alpha: ringAlpha * 0.9),
      );
    }
    // 12 particles flying outward.
    const n = 12;
    final particleAlpha = (1.0 - t);
    final particleR = math.max(2.0, scale * 0.09 * (1.0 - t * 0.6));
    final distance = scale * (0.1 + 1.5 * t);
    for (int i = 0; i < n; i++) {
      final a = (i / n) * math.pi * 2 + t * 0.6; // slight rotation
      final dx = center.dx + math.cos(a) * distance;
      final dy = center.dy + math.sin(a) * distance;
      canvas.drawCircle(
        Offset(dx, dy), particleR,
        Paint()..color = color.withValues(alpha: particleAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExplosionPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.center != center ||
      old.scale != scale;
}
