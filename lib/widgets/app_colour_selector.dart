import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_accent.dart';
import '../theme/app_theme.dart';

String appAccentLabel(AppLocalizations loc, AppAccent accent) {
  return switch (accent) {
    AppAccent.purple => loc.colourPurple,
    AppAccent.blue => loc.colourBlue,
    AppAccent.teal => loc.colourTeal,
    AppAccent.green => loc.colourGreen,
    AppAccent.orange => loc.colourOrange,
    AppAccent.red => loc.colourRed,
    AppAccent.pink => loc.colourPink,
    AppAccent.indigo => loc.colourIndigo,
  };
}

class AppColourSelector extends StatelessWidget {
  const AppColourSelector({
    super.key,
    required this.selectedAccent,
    required this.onChanged,
  });

  final AppAccent selectedAccent;
  final ValueChanged<AppAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 430
            ? 4
            : constraints.maxWidth >= 285
            ? 3
            : 2;
        const gap = 8.0;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: AppAccent.values.map((accent) {
            return SizedBox(
              width: itemWidth,
              child: _ColourChoice(
                accent: accent,
                label: appAccentLabel(loc, accent),
                selected: accent == selectedAccent,
                textScale: textScale,
                onTap: () => onChanged(accent),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ColourChoice extends StatefulWidget {
  const _ColourChoice({
    required this.accent,
    required this.label,
    required this.selected,
    required this.textScale,
    required this.onTap,
  });

  final AppAccent accent;
  final String label;
  final bool selected;
  final double textScale;
  final VoidCallback onTap;

  @override
  State<_ColourChoice> createState() => _ColourChoiceState();
}

class _ColourChoiceState extends State<_ColourChoice> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppBrandColors.fromAccent(widget.accent);
    final minHeight = 88.0 + ((widget.textScale - 1).clamp(0, 1) * 22);

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        child: Material(
          color: widget.selected
              ? palette.accentWash
              : Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _focused || widget.selected
                  ? palette.accentDark
                  : palette.outlineVariant,
              width: _focused ? 3 : (widget.selected ? 2 : 1),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('app-colour-${widget.accent.storageValue}'),
            onTap: widget.onTap,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            overlayColor: WidgetStatePropertyAll(
              palette.accent.withValues(alpha: 0.10),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.selected
                                ? palette.accentDark
                                : palette.outline,
                            width: widget.selected ? 3 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: widget.selected
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 26,
                              )
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: palette.onAccentLight,
                              fontWeight: widget.selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              height: 1.15,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
