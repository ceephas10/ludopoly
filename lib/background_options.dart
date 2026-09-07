// Options › Arrière-plan : le panneau qui personnalise le décor.
//
// Reprend la section du kit « Ludo King Background » — cinq styles, cinq
// palettes, les effets d'ambiance et leurs curseurs — habillée aux
// couleurs de l'application.

import 'package:flutter/material.dart';

import 'game/app_background.dart';
import 'game/background_config.dart';

class BackgroundOptions extends StatelessWidget {
  const BackgroundOptions({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final BackgroundConfig config;
  final ValueChanged<BackgroundConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          icon: Icons.layers_outlined,
          title: 'Style d\'arrière-plan',
          trailing: '${BgStyle.values.length} styles disponibles',
        ),
        const SizedBox(height: 8),
        // Deux par rangée, comme dans le kit.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.5,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          children: [
            for (final s in BgStyle.values)
              _StyleTile(
                key: Key('bg-style-${s.name}'),
                style: s,
                selected: config.style == s,
                onTap: () => onChanged(config.copyWith(style: s)),
              ),
          ],
        ),

        const SizedBox(height: 18),
        _Header(icon: Icons.palette_outlined, title: 'Palette de couleurs'),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final t in BgTheme.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ThemeSwatch(
                    key: Key('bg-theme-${t.name}'),
                    theme: t,
                    selected: config.theme == t,
                    onTap: () => onChanged(config.copyWith(theme: t)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(config.theme.label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),

        const SizedBox(height: 18),
        _Header(
            icon: Icons.tune, title: 'Éclairage & effets d\'ambiance'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _EffectToggle(
                key: const Key('bg-droplets'),
                label: '💧 Gouttes d\'eau',
                value: config.waterDroplets,
                tint: BgPalette.cyan,
                onTap: () => onChanged(
                    config.copyWith(waterDroplets: !config.waterDroplets)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EffectToggle(
                key: const Key('bg-accents'),
                label: '✨ Halos colorés',
                value: config.floatingAccents,
                tint: const Color(0xFFB45CFF),
                onTap: () => onChanged(config.copyWith(
                    floatingAccents: !config.floatingAccents)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        _Slider(
          key: const Key('bg-pattern-opacity'),
          label: 'Opacité du motif en losange / dés',
          value: config.patternOpacity,
          onChanged: (v) => onChanged(config.copyWith(patternOpacity: v)),
        ),
        _Slider(
          key: const Key('bg-rays'),
          label: '☀ Rayons lumineux en diagonale',
          value: config.raysIntensity,
          onChanged: (v) => onChanged(config.copyWith(raysIntensity: v)),
        ),

        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _StateButton(
                key: const Key('bg-center-glow'),
                label: 'Halo central',
                value: config.centerGlow,
                onTap: () =>
                    onChanged(config.copyWith(centerGlow: !config.centerGlow)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StateButton(
                key: const Key('bg-vignette'),
                label: 'Vignettage',
                value: config.vignette,
                onTap: () =>
                    onChanged(config.copyWith(vignette: !config.vignette)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),
        // L'aperçu : on voit le décor tel qu'il sera, sans quitter la page.
        Text('Aperçu',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 150,
            child: AppBackground.board
                .wrap(const SizedBox.expand(), config: config),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: BgPalette.cyan),
        const SizedBox(width: 6),
        Expanded(
          child: Text(title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              )),
        ),
        if (trailing != null)
          Text(trailing!,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: BgPalette.amber)),
      ],
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final BgStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? BgPalette.tile : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? BgPalette.cyan : cs.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(style.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : cs.onSurface,
                  )),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? BgPalette.cyan.withValues(alpha: 0.25)
                      : cs.surface,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(style.badge,
                    style: TextStyle(
                      fontSize: 9,
                      color: selected ? Colors.white : cs.onSurfaceVariant,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    super.key,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final BgTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: theme.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.light, theme.dark],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

class _EffectToggle extends StatelessWidget {
  const _EffectToggle({
    super.key,
    required this.label,
    required this.value,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final bool value;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: value ? tint.withValues(alpha: 0.16) : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: value ? tint : cs.outlineVariant, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: value ? cs.onSurface : cs.onSurfaceVariant)),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? tint : cs.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            Text('$value %',
                style: TextStyle(
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: cs.onSurface)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.toDouble(),
            max: 100,
            divisions: 20,
            activeColor: BgPalette.cyan,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _StateButton extends StatelessWidget {
  const _StateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        side: BorderSide(color: value ? BgPalette.cyan : cs.outlineVariant),
        foregroundColor: value ? cs.onSurface : cs.onSurfaceVariant,
        backgroundColor:
            value ? BgPalette.cyan.withValues(alpha: 0.12) : null,
      ),
      onPressed: onTap,
      child: Text('$label : ${value ? "activé" : "désactivé"}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11)),
    );
  }
}
