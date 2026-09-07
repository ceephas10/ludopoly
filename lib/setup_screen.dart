// L'écran d'accueil : on règle la partie, puis on joue.
//
// Il n'applique rien lui-même — il rassemble un [GameSetup] et le rend au
// moment où l'on appuie sur « Jouer ». C'est le plateau qui l'applique.

import 'package:flutter/material.dart';

import 'background_options.dart';
import 'game/ai_difficulty.dart';
import 'game/game_setup.dart';
import 'game/player_color.dart';

const Map<PlayerColor, Color> _swatch = {
  PlayerColor.blue: Color(0xFF2E7DF7),
  PlayerColor.red: Color(0xFFE04A4A),
  PlayerColor.green: Color(0xFF3FA34D),
  PlayerColor.yellow: Color(0xFFE8B93B),
};

const Map<PlayerColor, String> _frenchColor = {
  PlayerColor.blue: 'Bleu',
  PlayerColor.red: 'Rouge',
  PlayerColor.green: 'Vert',
  PlayerColor.yellow: 'Jaune',
};

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onStart});

  /// Appelé quand le joueur appuie sur « Jouer ».
  final ValueChanged<GameSetup> onStart;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  GameSetup _s = const GameSetup();

  void _set(GameSetup next) => setState(() => _s = next);

  /// Un siège bascule entre humain et ordinateur.
  void _toggleSeat(PlayerColor c) {
    final seats = Set<PlayerColor>.from(_s.aiSeats);
    if (!seats.remove(c)) seats.add(c);
    _set(_s.copyWith(aiSeats: seats));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                Text('LudoPoly',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    )),
                const SizedBox(height: 4),
                Text('Réglez la partie, puis jouez.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),

                // ─── Combien de joueurs ───
                _Section(
                  title: 'Nombre de joueurs',
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: {_s.playerCount.clamp(2, 4)},
                    onSelectionChanged: (v) {
                      final n = v.first;
                      // Un siège devenu inactif ne doit pas rester marqué
                      // « ordinateur » : il ressortirait au prochain
                      // agrandissement de la partie.
                      final kept = _s.aiSeats
                          .where(_s.copyWith(playerCount: n).colors.contains)
                          .toSet();
                      _set(_s.copyWith(
                        playerCount: n,
                        aiSeats: kept,
                        teamMode: n == 4 && _s.teamMode,
                      ));
                    },
                  ),
                ),

                // ─── Qui tient quelle couleur ───
                _Section(
                  title: 'Qui joue ?',
                  subtitle: 'Touchez une couleur pour la confier à '
                      'l\'ordinateur.',
                  child: Column(
                    children: [
                      for (final c in _s.colors)
                        _SeatTile(
                          color: _swatch[c]!,
                          name: _frenchColor[c]!,
                          isAi: _s.aiSeats.contains(c),
                          onTap: () => _toggleSeat(c),
                        ),
                    ],
                  ),
                ),

                // ─── Niveau de l'ordinateur ───
                if (_s.aiSeats.isNotEmpty)
                  _Section(
                    title: 'Niveau de l\'ordinateur',
                    subtitle: _s.difficulty.summary,
                    child: DropdownButtonFormField<AiDifficulty>(
                      key: const Key('setup-difficulty'),
                      initialValue: _s.difficulty,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final d in AiDifficulty.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (d) =>
                          d == null ? null : _set(_s.copyWith(difficulty: d)),
                    ),
                  ),

                // ─── Options de jeu ───
                _Section(
                  title: 'Options',
                  child: Column(
                    children: [
                      _OptionTile(
                        title: 'Cases spéciales',
                        subtitle: 'Vortex et trous noirs : un pion peut être '
                            'projeté à l\'autre bout du plateau.',
                        value: _s.vortex,
                        onChanged: (v) => _set(_s.copyWith(vortex: v)),
                      ),
                      _OptionTile(
                        title: 'Cartes chance',
                        subtitle: 'Les cases Chance font tirer une carte, '
                            'immédiate ou gardée pour plus tard.',
                        value: _s.chance,
                        onChanged: (v) => _set(_s.copyWith(chance: v)),
                      ),
                      if (_s.playerCount == 4)
                        _OptionTile(
                          title: 'Équipes 2 contre 2',
                          subtitle: 'Bleu avec vert, rouge avec jaune. '
                              'La partie s\'arrête dès qu\'une équipe a '
                              'rentré ses huit pions.',
                          value: _s.teamMode,
                          onChanged: (v) => _set(_s.copyWith(teamMode: v)),
                        ),
                      if (_s.aiSeats.isNotEmpty)
                        _OptionTile(
                          title: 'Accélérateur',
                          subtitle: 'Raccourcit les temps d\'attente de '
                              'l\'ordinateur.',
                          value: _s.aiTurbo,
                          onChanged: (v) => _set(_s.copyWith(aiTurbo: v)),
                        ),
                    ],
                  ),
                ),

                // ─── Arrière-plan ───
                _Section(
                  title: 'Arrière-plan',
                  subtitle: 'Le décor du menu et du plateau.',
                  child: BackgroundOptions(
                    config: _s.background,
                    onChanged: (b) => _set(_s.copyWith(background: b)),
                  ),
                ),

                const SizedBox(height: 8),
                if (!_s.hasHuman)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tous les sièges sont tenus par l\'ordinateur : '
                            'la partie se jouera toute seule.',
                            style: TextStyle(color: cs.primary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('setup-play'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Jouer',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                    onPressed: () => widget.onStart(_s),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un bloc de réglages : un titre, une explication facultative, le contenu.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Une couleur de la partie : humain ou ordinateur, d'un seul toucher.
class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.color,
    required this.name,
    required this.isAi,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool isAi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('setup-seat-$name'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(name)),
                Icon(isAi ? Icons.smart_toy : Icons.person,
                    size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(isAi ? 'Ordinateur' : 'Humain',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une option à interrupteur, avec la phrase qui dit ce qu'elle change.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: Key('setup-option-$title'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }
}
