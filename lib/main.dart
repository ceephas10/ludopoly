// LudoPoly — Step 1: static board with 4 players at starting positions
// rendered from the GameState model, with a debug overlay for the 52-cell ring.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'game/board_painter.dart';
import 'game/board_painter_5p.dart';
import 'game/board_path.dart';
import 'game/game_controller.dart';
import 'game/game_state.dart';
import 'game/pawn.dart';
import 'game/player_color.dart';
export 'game/player_color.dart';

void main() => runApp(const LudoPolyApp());

class LudoPolyApp extends StatelessWidget {
  const LudoPolyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LudoPoly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const BoardScreen(),
    );
  }
}

class Player {
  final String name;
  final PlayerColor color;
  const Player(this.name, this.color);
}

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

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

  /// Règle « adversaires ordinateur ». Exposée aux tests pour éviter de
  /// dépendre du libellé de l'interrupteur dans le panneau.
  @visibleForTesting
  bool get aiOpponents => _ruleAiOpponents;

  @visibleForTesting
  set aiOpponents(bool v) {
    _aiTimer?.cancel();
    setState(() => _ruleAiOpponents = v);
    _scheduleAiTurn();
  }
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

  /// Manual-mode selection: which color to play next and which dice value
  /// to force. Independent of the controller's natural turn rotation.
  PlayerColor _manualPlayer = PlayerColor.blue;
  int _manualValue = 1;

  /// Right-panel tab. `'commandes'` = Centre de commandes (default),
  /// `'rules'` = Règles du jeu.
  String _panelTab = 'commandes';

  /// Game rules state. **In-memory for now** — persistence across app
  /// reloads is TODO (was attempted with shared_preferences but hits a
  /// Flutter web path-resolution bug that maps `..\..\AppData\...` to a
  /// non-existent location). Default values match "classic" Ludo.
  bool _ruleStartWith1TokenOut = false;
  bool _ruleTeamMode = false;

  /// Mode "contre ordinateur" : toutes les couleurs sauf la première de
  /// l'ordre des tours sont pilotées par l'IA locale.
  bool _ruleAiOpponents = false;

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
  static const Duration _baseExitDuration = Duration(milliseconds: 220);

  /// Temps d'affichage du dé AVANT qu'un coup automatique (un seul pion
  /// jouable) ne parte. Sans cette pause on ne voit jamais le chiffre.
  static const Duration _dicePause = Duration(milliseconds: 550);

  /// Pause pendant laquelle l'attaquant ET le pion qu'il vient de capturer
  /// restent affichés ENSEMBLE sur la même case. Elle ne commence qu'une
  /// fois l'attaquant VISUELLEMENT arrivé ; le pion capturé n'a pas bougé
  /// d'un pixel avant cet instant, et ne quitte la case qu'à la fin.
  static const Duration _captureHold = Duration(milliseconds: 340);

  /// Temps que prend une IA avant de saisir le dé. C'est aussi le blanc
  /// que l'on voit entre deux ordinateurs qui s'enchaînent : sans lui, les
  /// couleurs défilent d'un bloc et on ne suit plus qui joue.
  static const Duration _aiRollDelay = Duration(milliseconds: 900);

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

  /// Position VISUELLE d'un pion pendant son trajet. Tant qu'une entrée est
  /// présente, le plateau dessine le pion sur cette case-là et non sur sa
  /// position réelle (le moteur, lui, a déjà appliqué tout le coup).
  final Map<Pawn, PawnStep> _travelStep = {};

  /// Pions capturés mais visiblement encore à leur ancienne position. Le moteur
  /// a déjà rendu le pion capturé, mais on le MONTRE en train de se faire
  /// capturer — à sa place d'avant la capture — pendant que le pion attaquant
  /// fait son trajet. Une fois que l'attaquant arrive sur cette case, le pion
  /// disparaît (on l'enlève de cette map).
  final Map<Pawn, PawnStep> _captureOverride = {};

  /// Timer du trajet en cours et du coup automatique en attente.
  Timer? _travelTimer;
  Timer? _autoMoveTimer;

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

  /// Couleur RETENUE par le dé pendant qu'un pion parcourt ses cases.
  /// Le moteur passe la main dès que le coup est appliqué, c'est-à-dire au
  /// DÉBUT de l'animation ; sans cette retenue le dé changerait de couleur
  /// alors que le pion est encore en train de compter. `null` = pas de
  /// trajet en cours, le dé suit le joueur courant.
  PlayerColor? _diceColorHold;

  /// Couleur affichée par le dé : celle du pion qui compte tant qu'il
  /// n'est pas arrivé, sinon celle du joueur dont c'est le tour.
  PlayerColor get _shownDiceColor =>
      _diceColorHold ?? _controller.currentColor;

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
    _bootstrap();
    // Le dé change de couleur à chaque passage de main. Sans préchargement,
    // la 1re fois qu'une face (valeur × couleur) apparaît, Flutter doit
    // d'abord la charger : le dé garde visiblement l'ancienne couleur
    // pendant ce temps. 24 images à précharger, une fois pour toutes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheDice());
    _startAiWatchdog();
  }

  @override
  void dispose() {
    _aiWatchdog?.cancel();
    _cancelAnimations();
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
    // Point de retour : l'instantané est pris AVANT le lancer, donc le
    // bouton Retour annule le lancer ET le déplacement joué avec.
    _controller.pushHistory(
        '${(forPlayer ?? _controller.currentColor).name} · dé $value');
    Pawn? autoMove;
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
      _controller.roll(value);
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
    if (pending != null) _scheduleAutoMove(pending);
  }

  /// Laisse le dé affiché [_dicePause] avant de jouer le coup forcé. Le
  /// verrou est levé pendant l'attente : on voit le chiffre et le pion
  /// surligné, et aucune autre commande ne peut s'intercaler.
  void _scheduleAutoMove(Pawn p) {
    _autoMoveTimer?.cancel();
    setState(() => _animating = true);
    _autoMoveTimer = Timer(_dicePause, () {
      if (!mounted) return;
      _animating = false; // pour que _movePawn accepte le coup
      _movePawn(p);
    });
  }

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
    if (_animating) return; // verrou : une commande à la fois
    if (_isAiTurn) return;  // c'est à l'ordinateur de lancer, pas à nous
    if (_controller.phase != TurnPhase.rolling) return;
    _roll(_controller.pickDiceValue(_secureRng));
    _scheduleAiTurn();
  }

  // --- Mode contre ordinateur ------------------------------------------------

  /// Couleurs pilotées par l'IA : tout le monde sauf le premier joueur de
  /// l'ordre des tours (l'humain), et seulement quand la règle est ON.
  bool _isAiColor(PlayerColor c) =>
      _ruleAiOpponents &&
      _controller.turnOrder.isNotEmpty &&
      c != _controller.turnOrder.first;

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
    if (!_ruleAiOpponents) return;
    if (_controller.phase == TurnPhase.gameOver) return;
    if (!_isAiColor(_controller.currentColor)) return;
    _aiTimer = Timer(delay ?? _aiRollDelay, _playAiTurn);
  }

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
    _aiWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _animating || !_aiMayAct) return;
      if ((_aiTimer?.isActive ?? false) ||
          (_autoMoveTimer?.isActive ?? false)) {
        return;
      }
      debugPrint('[ai] relance de secours : il manque un appel à '
          '_scheduleAiTurn sur le chemin qui vient de passer la main');
      _scheduleAiTurn();
    });
  }

  /// Vrai tant que l'IA courante peut continuer à agir. Les trois causes
  /// d'arrêt : le widget est parti, la règle a été coupée, ou la main n'est
  /// plus à une IA.
  bool get _aiMayAct =>
      mounted &&
      _ruleAiOpponents &&
      _controller.phase != TurnPhase.gameOver &&
      _isAiColor(_controller.currentColor);

  /// Premier temps du tour d'une IA : le lancer, et RIEN d'autre.
  ///
  /// Le coup est volontairement repoussé à [_playAiMove] : jouer dans la
  /// foulée du lancer ne laissait pas le temps de lire le dé — on voyait le
  /// pion partir avant le chiffre. Le seul cas où l'on ne programme rien
  /// est celui où [_roll] a déjà posé un coup automatique (un unique pion
  /// jouable) : il a sa propre pause et rendra la main tout seul.
  void _playAiTurn() {
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
    _roll(_controller.pickDiceValue(_secureRng));
    if (_animating) return; // coup automatique déjà programmé par _roll
    if (_controller.phase == TurnPhase.moving) {
      _aiTimer = Timer(_aiMoveDelay, _playAiMove);
    } else {
      // Le lancer n'a rien donné et a passé la main : au suivant.
      _scheduleAiTurn();
    }
  }

  /// Second temps : l'IA choisit son pion et le joue. Le coup passe par
  /// [_movePawn] — donc par le moteur, jamais par l'animation.
  void _playAiMove() {
    if (!mounted) return;
    if (_animating) {
      _scheduleAiTurn();
      return;
    }
    if (!_aiMayAct) return;
    if (_controller.phase == TurnPhase.moving) {
      final choice = _controller.pickAiPawn();
      if (choice != null) {
        _movePawn(choice);
        return; // _movePawn replanifie le tour suivant
      }
    }
    _scheduleAiTurn();
  }

  void _rollDiceManual(PlayerColor player, int value) {
    _roll(value, forPlayer: player);
    // Ce lancer peut passer la main à un ordinateur : sans cet appel il ne
    // repartirait jamais, et le plateau étant en lecture seule pendant son
    // tour, la partie serait définitivement figée.
    _scheduleAiTurn();
  }

  void _movePawn(Pawn p) {
    // Verrou anti-bug : double clic sur un pion, clic pendant l'animation,
    // deux commandes simultanées → une seule est acceptée.
    if (_animating) return;
    if (_controller.phase != TurnPhase.moving) return;
    final distance = _controller.diceValue;
    final oldLoc = p.location;
    // Snapshot capture state to spawn explosions for any pawn that got
    // sent back to base by this move. Sauvegarde aussi la position exacte.
    final beforeLoc = {
      for (final pp in _game.allPawns)
        pp: PawnStep(pp.location, pp.position),
    };
    // Trajet case par case, calculé AVANT que le moteur n'applique le coup.
    // Une sortie de base est un saut unique, pas un parcours.
    final path = _controller.pathFor(p, distance);
    final stepDur = (oldLoc == PawnLocation.base)
        ? _baseExitDuration
        : _stepDuration;
    // Instant où l'attaquant est VISUELLEMENT sur sa case d'arrivée. Le
    // `Timer.periodic` ci-dessous retire `_travelStep` à son tick
    // `path.length - 1` ; un trajet d'une seule étape (sortie de base)
    // s'affiche tout de suite mais glisse encore pendant `stepDur`.
    final arrivalDur = stepDur * math.max(path.length - 1, 1);
    // Pions capturés par ce coup, détectés en comparant l'avant / l'après.
    final capturedNow = <Pawn>[];

    _travelTimer?.cancel();
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
      _controller.movePawn(p);
      // Pions capturés : on garde leur ancienne position visible pendant le trajet.
      capturedNow.addAll(_game.allPawns.where((pp) =>
          pp != p &&
          beforeLoc[pp]!.location != PawnLocation.base &&
          pp.location == PawnLocation.base));
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
      _animating = true;
      // Le dé garde la couleur du pion tant qu'il n'a pas fini de compter.
      _diceColorHold = p.color;
      // On force l'affichage sur la 1re case du trajet ; le pion glissera
      // ensuite de case en case jusqu'à sa position réelle.
      if (path.length > 1) _travelStep[p] = path.first;
    });

    // Une étape par tick : le pion s'arrête visiblement sur chaque case.
    if (path.length > 1) {
      int idx = 0;
      _travelTimer = Timer.periodic(stepDur, (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        idx++;
        setState(() {
          if (idx >= path.length - 1) {
            // Dernière case = position réelle du pion : on retire l'override.
            _travelStep.remove(p);
            t.cancel();
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
    final holdDur = capturedNow.isEmpty ? Duration.zero : _captureHold;
    final totalDur = arrivalDur + holdDur;

    // Libère le verrou une fois le trajet parcouru ET la pause écoulée,
    // puis rend la main à l'IA si c'est à son tour.
    Timer(totalDur, () {
      if (!mounted) return;
      setState(() {
        _animating = false;
        _travelStep.remove(p);
        // Le pion est arrivé : c'est MAINTENANT que le dé prend la couleur
        // du joueur suivant.
        _diceColorHold = null;
      });
      // L'attaquant est arrivé et la pause est écoulée : les pions capturés
      // quittent MAINTENANT la case, en rembobinant leur parcours à
      // contre-sens jusqu'à leur flèche d'entrée puis dans leur base.
      for (final cap in capturedNow) {
        _startReturnTravel(cap);
      }
      _scheduleAiTurn();
    });
    // Explosion de capture : au moment EXACT où le pion capturé s'efface.
    final captures = capturedNow;
    if (captures.isNotEmpty) {
      Future.delayed(totalDur, () {
        if (!mounted) return;
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
    setState(() {
      // Le pion glisse d'une case à l'autre au rythme du rembobinage.
      _moveDuration[cap] = _returnStep;
      _captureOverride[cap] = path.first;
    });
    int i = 0;
    _returnTimers[cap] = Timer.periodic(_returnStep, (timer) {
      // Le pion est ressorti de sa base entre-temps : son trajet normal
      // reprend la main, on s'efface immédiatement.
      if (!mounted || cap.location != PawnLocation.base) {
        timer.cancel();
        _returnTimers.remove(cap);
        if (mounted) setState(() => _captureOverride.remove(cap));
        return;
      }
      i++;
      setState(() {
        if (i >= path.length - 1) {
          // Dernière étape = la base, sa position réelle : on retire
          // l'override plutôt que de l'y poser, c'est le même point.
          _captureOverride.remove(cap);
          timer.cancel();
          _returnTimers.remove(cap);
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
    if (_animating) return;
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
    _travelTimer?.cancel();
    _autoMoveTimer?.cancel();
    for (final t in _returnTimers.values) {
      t.cancel();
    }
    _returnTimers.clear();
    _travelStep.clear();
    _diceColorHold = null;
    _captureOverride.clear();
    _animating = false;
  }

  /// Bouton « Rejouer » : rétablit l'action qu'on vient d'annuler. Chaque
  /// pression redescend d'un coup. Jouer un nouveau coup vide la pile de
  /// rétablissement — on ne rejoue pas une branche abandonnée.
  void _stepForward() {
    if (_animating) return;
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
    if (_animating) return;
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
    final color = _shownDiceColor;
    setState(() {
      _hoverInfo = 'Dé ${color.name} · valeur $_shownDice';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_assetsReady) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A2541),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'Loading tokens…',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  _loadingStatus,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1A2541),
      body: SafeArea(
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
            final panelWidth = (w * 0.39).clamp(panelMin, panelMax);
            final boardArea = isNarrow ? w : (w - panelWidth).clamp(120.0, w);
            // 15 px top + 15 px bottom breathing room around the board.
            const boardMarginV = 15.0;
            final maxBoardSquare = isNarrow
                ? math.min(w, h * 0.6) // narrow: board takes ~60 % of height
                : (h - 2 * boardMarginV).clamp(0.0, boardArea);
            final boardSide =
                _boardWidthOverride?.clamp(120.0, maxBoardSquare) ??
                    maxBoardSquare;

            final boardWidget = SizedBox(
              width: boardArea,
              height: isNarrow ? boardSide + 2 * boardMarginV : h,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: boardMarginV),
                child: Center(
                  child: SizedBox(
                    width: boardSide,
                    height: boardSide,
                    child: BoardView(
                      players: _activePlayers,
                      game: _game,
                      showRing: _showRing,
                      showGrid: _showGrid,
                      showCanvas: _showCanvas,
                      playerCount: _playerCount,
                      diceValue: _shownDice,
                      diceColor: _shownDiceColor,
                      currentPlayerColor: _controller.currentColor,
                      canRollDice: _controller.phase == TurnPhase.rolling &&
                          !_animating &&
                          !_isAiTurn,
                      // Aucun sélecteur, aucun pion cliquable tant que
                      // c'est un ordinateur qui joue : il n'attend rien.
                      movablePawns: _isAiTurn
                          ? const <Pawn>{}
                          : _controller.movablePawns().toSet(),
                      onRollDice: _rollDiceRandom,
                      onPawnTap: _movePawn,
                      pawnAsset: _pawnAsset,
                      pawnInfo: _pawnInfo,
                      onPawnHover: _onPawnHover,
                      onDiceHover: _onDiceHover,
                      showDetails: _showDetails,
                      moveDuration: _moveDuration,
                      travelStep: _travelStep,
                      captureOverride: _captureOverride,
                      explosions: _explosions,
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
                        // so the central dice picks up the new color.
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
                        _rollDiceManual(_manualPlayer, v),
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
                    ruleAiOpponents: _ruleAiOpponents,
                    onToggleRuleAiOpponents: (v) {
                      _aiTimer?.cancel();
                      setState(() => _ruleAiOpponents = v);
                      _scheduleAiTurn();
                    },
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

            // ── Responsive root: stack on narrow screens, side-by-side
            //    on wide ones. ───────────────────────────────────────
            if (isNarrow) {
              return Column(
                children: [
                  boardWidget,
                  Expanded(child: panel),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                boardWidget,
                SizedBox(
                  width: panelWidth,
                  height: h,
                  child: panel,
                ),
              ],
            );
          },
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
  final ValueChanged<String> onChangePanelTab;
  final bool ruleStartWith1TokenOut;
  final ValueChanged<bool> onToggleRuleStartWith1TokenOut;
  final bool ruleTeamMode;
  final ValueChanged<bool> onToggleRuleTeamMode;
  final bool ruleAiOpponents;
  final ValueChanged<bool> onToggleRuleAiOpponents;

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
    required this.onStepBack,
    required this.canStepBack,
    required this.stepBackLabel,
    required this.onStepForward,
    required this.canStepForward,
    required this.stepForwardLabel,
    required this.panelTab,
    required this.onChangePanelTab,
    required this.ruleStartWith1TokenOut,
    required this.onToggleRuleStartWith1TokenOut,
    required this.ruleTeamMode,
    required this.onToggleRuleTeamMode,
    required this.ruleAiOpponents,
    required this.onToggleRuleAiOpponents,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Tab selector ----
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'commandes',
                        label: Text('Centre de commandes'),
                        icon: Icon(Icons.tune, size: 18),
                      ),
                      ButtonSegment(
                        value: 'rules',
                        label: Text('Règles du jeu'),
                        icon: Icon(Icons.rule, size: 18),
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
                        SwitchListTile(
                          title: const Text('Adversaires ordinateur'),
                          subtitle: const Text(
                              'Le 1er joueur est humain, les autres couleurs '
                              'sont jouées par l\'IA locale (capture > '
                              'maison > couloir > sortie > case sûre).'),
                          value: ruleAiOpponents,
                          onChanged: onToggleRuleAiOpponents,
                        ),
                      ],
                    ),
                  ),
                ] else ...[

                // ---- Setup card (left, half width) + nomenclature
                //      thumbnail (right, half width, hover-zoom) ----
                Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 1, child: _normalCard(theme, cs)),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: _manualCard(theme, cs)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ---- Overlays card (2 toggles per row) ----
                _SectionCard(
                  title: 'Overlays',
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
          FilledButton.icon(
            icon: const Icon(Icons.casino),
            label: const Text('Lancer le dé'),
            onPressed: (phase == TurnPhase.rolling && !busy)
                ? onRollDice
                : null,
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
          Text('Couleur',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in activePlayers)
                _ColorDot(
                  color: _playerColor(p.color),
                  selected: p.color == manualPlayer,
                  onTap: () => onChangeManualPlayer(p.color),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Valeur dé (left) ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Valeur dé',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(
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
              ),
              const SizedBox(width: 12),
              // ─── Pions à la base (right) ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pions dans la Maison',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
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

  /// Couleur du dé central. Ce n'est PAS toujours [currentPlayerColor] :
  /// pendant qu'un pion compte ses cases, le dé garde la couleur de ce
  /// pion et ne passe au joueur suivant qu'à son ARRIVÉE.
  final PlayerColor diceColor;
  final PlayerColor currentPlayerColor;
  final bool canRollDice;
  final Set<Pawn> movablePawns;
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

  /// Pions en train de se faire capturer : affichés à leur ancienne position
  /// le temps du trajet du pion attaquant.
  final Map<Pawn, PawnStep> captureOverride;
  /// Active explosion FX painted on top of the board (capture markers).
  final List<ExplosionFx> explosions;
  const BoardView({
    super.key,
    required this.players,
    required this.game,
    required this.diceValue,
    required this.diceColor,
    required this.currentPlayerColor,
    required this.canRollDice,
    required this.movablePawns,
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
    this.captureOverride = const {},
    this.explosions = const [],
    this.showGrid = false,
    this.showCanvas = false,
    this.playerCount = 4,
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
  static const List<double> _spotsX = [1.5, 2.5, 3.5, 4.5];

  // ---- Pawn-image visible bounds inside its bbox -------------------------
  // The content-bbox-based scaling in `_PawnAnimatedGif` already aligns the
  // visible token's CENTER with the parent container's center, so we only
  // need to remember where the container is anchored on screen — which is
  // the cell center for every position (base / ring / home column).
  static const double _pawnVisibleCenterFrac = 0.5;

  // Center of each player's dice, in global cell coordinates. Each dice
  // occupies the 2x2 cell square diagonally inward from the base's outer
  // corner: red 32/33/47/48, green 41/42/56/57, blue 167/168/182/183,
  // yellow 176/177/191/192.
  static const Map<PlayerColor, Offset> _diceCenter = {
    PlayerColor.red:    Offset(3.0,  3.0),
    PlayerColor.green:  Offset(12.0, 3.0),
    PlayerColor.blue:   Offset(3.0,  12.0),
    PlayerColor.yellow: Offset(12.0, 12.0),
  };

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
    final cy = (corner.dy + 1.1) * cell;
    return Offset(cx, cy);
  }

  /// Geometric center of ring cell [index] in pixels.
  Offset _ringCellCenter(int index, double cell) => ring[index].pos * cell;

  /// Resolve a pawn's visual ANCHOR in board coordinates — the point where
  /// `_pawnVisibleCenterFrac × pawnHeight` lands. Universal rule: the
  /// token's **pointe** (the bottom tip = feet, contact with the cell)
  /// sits at `(cell_center.x, cell_center.y + 0.1 cell)`. The body
  /// extends UPWARD from there, overflowing into the cell above.
  ///
  /// With `visibleCenterFrac = 0.5` and content filling the full bbox,
  /// visible_bottom = anchor + 0.5 pawnHeight, so
  ///   anchor = cell_center + (0, 0.1 cell − 0.5 pawnHeight).
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
      PawnLocation.home       => _homeCenter(p.color, cell),
    };
    return Offset(
      cellCenter.dx,
      cellCenter.dy + 0.1 * cell - 0.5 * pawnHeight,
    );
  }

  /// Geometric center of the colored home triangle for [color]. Each
  /// triangle sits one cell away from the board center in its cardinal
  /// direction:
  ///   blue  → bottom (south)
  ///   red   → left   (west)
  ///   green → top    (north)
  ///   yellow→ right  (east)
  Offset _homeCenter(PlayerColor color, double cell) {
    switch (color) {
      case PlayerColor.blue:   return Offset(7.5 * cell, 8.5 * cell);
      case PlayerColor.red:    return Offset(6.5 * cell, 7.5 * cell);
      case PlayerColor.green:  return Offset(7.5 * cell, 6.5 * cell);
      case PlayerColor.yellow: return Offset(8.5 * cell, 7.5 * cell);
    }
  }

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
                child: const _DiceFace(value: 1, playerColor: null),
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

        // Visible token target ≈ 0.84 cells tall (≈30 % smaller than the
        // previous 1.2 so the pion doesn't overflow neighbouring cells
        // and no longer masks the gold-arrow selector behind it).
        final pawnHeight = cell * 0.84;
        // Aspect ≈ 0.7 — close to a typical idle WebP (64/93 = 0.69).
        final pawnWidth = pawnHeight * 0.7;

        return Stack(
          children: [
            // Vector-drawn board: stays crisp at any size (no raster scaling).
            const Positioned.fill(
              child: CustomPaint(painter: BoardPainter()),
            ),

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

            // Single central dice in the current player's color. Clickable
            // during the rolling phase.
            () {
              final size = cell * 1.6;
              final clickable = canRollDice;
              return Positioned(
                left: 7.5 * cell - size / 2,
                top:  7.5 * cell - size / 2,
                width: size,
                height: size,
                child: MouseRegion(
                  cursor: showDetails
                      ? SystemMouseCursors.help
                      : (clickable
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic),
                  onEnter: (_) => onDiceHover?.call(true),
                  onExit: (_) => onDiceHover?.call(false),
                  child: GestureDetector(
                    onTap: clickable ? onRollDice : null,
                    child: _DiceFace(
                      value: diceValue,
                      playerColor: diceColor,
                    ),
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
                    return 'home_${p.color.name}';
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

              // Studio spec for Selector_D_Arrow.gif (400×400, transparent,
              // pawn logical center at (200,200), ring at (200,299) — under
              // feet, arrow at y 95..131 — above head):
              //   - SQUARE width == height (here +4 vertical viewbox extension)
              //   - centered on the visible pawn anchor (NOT bbox center)
              //   - pointer-events: none (IgnorePointer)
              final selSize = cell * 1.8 + 4;

              // ---- Pass 1: selectors (all behind all pawns) ----
              for (final pawn in list) {
                if (!movablePawns.contains(pawn)) continue;
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final visCx = center.dx;
                final visCy = center.dy;
                yield Positioned(
                  key: ValueKey('sel_${pawn.color.name}_${pawn.id}'),
                  left: visCx - selSize / 2,
                  top:  visCy - (selSize + 4) / 2 - 7,
                  width: selSize,
                  height: selSize + 4,
                  child: IgnorePointer(
                    child: Image.asset(
                      'AnimStock/Selectors/WEBP/Selector_D_Arrow.webp',
                      fit: BoxFit.fill,
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
                  curve: Curves.easeInOut,
                  left: bboxLeft,
                  top:  bboxTop,
                  width: pawnWidth,
                  height: pawnHeight,
                  child: IgnorePointer(
                    child: _PawnAnimatedGif(
                      key: ValueKey('${pawn.color.name}_${pawn.id}'),
                      asset: pawnAsset(pawn),
                      sequentialStartDelayMs: delayOf(pawn),
                      showCanvas: showCanvas,
                      // Only the current player's pawns animate. The
                      // others stay on their rest frame so the board
                      // doesn't get visually overloaded.
                      paused: pawn.color != currentPlayerColor,
                    ),
                  ),
                );
                // (Canvas debug overlay is drawn inside `_PawnAnimatedGif`
                // when `showCanvas` is true, using the GIF's native pixel
                // dimensions so the rectangle matches the actual rendered
                // image — not the layout bbox.)
              }

              // ---- Pass 3: HIT zones (tight square around the visible
              //              token only — no more giant bbox swallowing
              //              the empty halo around the sprite). ----
              // Hit zone is cell × 1.0 centered on the visible token anchor.
              // Visible token spans cell×0.776 vertically inside its bbox, so
              // cell×1.0 wraps it tightly with a tiny margin.
              final hitSize = cell * 1.0;
              for (final pawn in list) {
                final center =
                    _pawnCenter(pawn, cell, pawnHeight) + stackOffsets[pawn]!;
                final isMovable = movablePawns.contains(pawn);
                yield Positioned(
                  key: ValueKey('hit_${pawn.color.name}_${pawn.id}'),
                  left: center.dx - hitSize / 2,
                  top:  center.dy - hitSize / 2,
                  width: hitSize,
                  height: hitSize,
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
                      child: GestureDetector(
                        // Without `opaque`, an invisible SizedBox doesn't
                        // absorb taps → clicks on the pawn would fall
                        // through to the parent, breaking `onPawnTap`.
                        behavior: HitTestBehavior.opaque,
                        onTap: isMovable ? () => onPawnTap(pawn) : null,
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
class _DiceFace extends StatelessWidget {
  final int value;
  final PlayerColor? playerColor;
  const _DiceFace({required this.value, required this.playerColor});

  String get _assetPath {
    final colorName = playerColor?.name ?? 'white';
    final v = value.clamp(1, 6);
    return 'AnimStock/Dices/PNG/Dice_${v}_$colorName.png';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        // Le chemin change à chaque changement de couleur ou de valeur.
        // Sans ça, Flutter vide la case le temps de décoder la nouvelle
        // image : le dé disparaît pendant une frame.
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
