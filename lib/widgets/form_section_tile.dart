import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A focus-aware surface used to give related form content a clear visual
/// boundary without turning the whole screen into a field grid.
class FormSectionTile extends StatefulWidget {
  const FormSectionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    this.supportingText,
  });

  final String label;
  final IconData icon;
  final Widget child;
  final String? supportingText;

  @override
  State<FormSectionTile> createState() => _FormSectionTileState();
}

class _FormSectionTileState extends State<FormSectionTile> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final brand = context.brandColors;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [brand.accentWash, AppColors.surface],
            stops: const [0, 0.7],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hasFocus ? brand.accent : brand.outlineVariant,
            width: _hasFocus ? 2 : 1,
          ),
          boxShadow: _hasFocus
              ? [
                  BoxShadow(
                    color: brand.accent.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: brand.accentLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: brand.outlineVariant),
                  ),
                  child: Icon(widget.icon, size: 20, color: brand.accentDark),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: textTheme.titleMedium?.copyWith(
                      color: brand.onAccentLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.supportingText case final supportingText?) ...[
              const SizedBox(height: 6),
              Text(supportingText, style: textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            widget.child,
          ],
        ),
      ),
    );
  }
}
