import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

enum TactileButtonVariant { primary, secondary, destructive }

/// Determines whether equally sized action buttons need a vertical layout to
/// preserve complete localised labels at the current text scale.
bool tactileButtonsNeedStacking(
  BuildContext context,
  double availableWidth,
  List<String> labels, {
  double spacing = 8,
}) {
  final textStyle = Theme.of(context).textTheme.labelLarge;
  final scaler = MediaQuery.textScalerOf(context);
  final buttonWidth = (availableWidth - spacing) / labels.length;

  return labels.any((label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    const iconAndSpacing = 32.0;
    const horizontalPadding = 36.0;
    return painter.width + iconAndSpacing + horizontalPadding > buttonWidth;
  });
}

/// A Material button with a restrained raised surface and a short physical
/// press response. The underlying [FilledButton] retains Material focus,
/// keyboard, ripple, disabled, and accessibility behaviour.
class TactileButton extends StatefulWidget {
  const TactileButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.variant = TactileButtonVariant.secondary,
    this.loading = false,
    this.minimumSize,
    this.padding,
  });

  const TactileButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.variant = TactileButtonVariant.secondary,
    this.loading = false,
    this.minimumSize,
    this.padding,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final TactileButtonVariant variant;
  final bool loading;
  final Size? minimumSize;
  final EdgeInsetsGeometry? padding;

  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  late final WidgetStatesController _statesController;
  bool _pressed = false;
  bool _focused = false;
  bool _stateUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _statesController = WidgetStatesController();
    _statesController.update(
      WidgetState.disabled,
      widget.onPressed == null || widget.loading,
    );
    _statesController.addListener(_handleStatesChanged);
  }

  @override
  void didUpdateWidget(covariant TactileButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _statesController.update(
      WidgetState.disabled,
      widget.onPressed == null || widget.loading,
    );
  }

  void _handleStatesChanged() {
    if (!mounted) return;
    final nextPressed = _statesController.value.contains(WidgetState.pressed);
    final nextFocused = _statesController.value.contains(WidgetState.focused);
    if (_pressed == nextPressed && _focused == nextFocused) return;

    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() {
        _pressed = nextPressed;
        _focused = nextFocused;
      });
      return;
    }

    if (_stateUpdateScheduled) return;
    _stateUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stateUpdateScheduled = false;
      if (!mounted) return;
      setState(() {
        _pressed = _statesController.value.contains(WidgetState.pressed);
        _focused = _statesController.value.contains(WidgetState.focused);
      });
    });
  }

  @override
  void dispose() {
    _statesController.removeListener(_handleStatesChanged);
    _statesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brand = context.brandColors;
    final enabled = widget.onPressed != null && !widget.loading;

    final surface = _surfaceColor(colorScheme, brand, _pressed, enabled);
    final foreground = _foregroundColor(colorScheme, brand, enabled);

    final style = ButtonStyle(
      animationDuration: const Duration(milliseconds: 100),
      backgroundColor: WidgetStatePropertyAll(surface),
      foregroundColor: WidgetStatePropertyAll(foreground),
      overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: 0.08)),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: WidgetStatePropertyAll(
        widget.minimumSize ?? const Size(64, 50),
      ),
      padding: WidgetStatePropertyAll(
        widget.padding ??
            const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
      tapTargetSize: MaterialTapTargetSize.padded,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      side: WidgetStatePropertyAll(
        BorderSide(
          color: _borderColor(colorScheme, brand, _focused, enabled),
          width: _focused ? 2 : _restingBorderWidth,
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );

    final content = widget.loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: foreground,
            ),
          )
        : widget.child;

    final button = widget.icon == null
        ? FilledButton(
            statesController: _statesController,
            onPressed: enabled ? widget.onPressed : null,
            style: style,
            child: content,
          )
        : FilledButton.icon(
            statesController: _statesController,
            onPressed: enabled ? widget.onPressed : null,
            style: style,
            icon: widget.loading ? const SizedBox.shrink() : widget.icon!,
            label: content,
          );

    return AnimatedContainer(
      duration: Duration(milliseconds: _pressed ? 90 : 145),
      curve: _pressed ? Curves.easeOut : Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: _shadowColor(colorScheme, brand, _focused),
                  blurRadius: _pressed ? 1 : (_focused ? 7 : 5),
                  offset: Offset(0, _pressed ? 1 : 3),
                ),
              ]
            : const [],
      ),
      child: button,
    );
  }

  double get _restingBorderWidth => switch (widget.variant) {
    TactileButtonVariant.primary => 1.5,
    TactileButtonVariant.secondary => 1,
    TactileButtonVariant.destructive => 1.25,
  };

  Color _surfaceColor(
    ColorScheme colors,
    AppBrandColors brand,
    bool pressed,
    bool enabled,
  ) {
    if (!enabled) return colors.onSurface.withValues(alpha: 0.06);
    return switch (widget.variant) {
      TactileButtonVariant.primary =>
        pressed ? brand.accentSoft : brand.accentLight,
      TactileButtonVariant.secondary =>
        pressed ? brand.accentLight : brand.controlSurface,
      TactileButtonVariant.destructive =>
        pressed
            ? colors.errorContainer.withValues(alpha: 0.8)
            : colors.errorContainer.withValues(alpha: 0.48),
    };
  }

  Color _foregroundColor(
    ColorScheme colors,
    AppBrandColors brand,
    bool enabled,
  ) {
    if (!enabled) return colors.onSurface.withValues(alpha: 0.38);
    return switch (widget.variant) {
      TactileButtonVariant.primary ||
      TactileButtonVariant.secondary => brand.accentDark,
      TactileButtonVariant.destructive => colors.error,
    };
  }

  Color _borderColor(
    ColorScheme colors,
    AppBrandColors brand,
    bool focused,
    bool enabled,
  ) {
    if (!enabled) return colors.onSurface.withValues(alpha: 0.12);
    if (focused) {
      return widget.variant == TactileButtonVariant.destructive
          ? colors.error
          : brand.accentDark;
    }
    return switch (widget.variant) {
      TactileButtonVariant.primary => brand.accent,
      TactileButtonVariant.secondary => brand.controlEdge,
      TactileButtonVariant.destructive => colors.error.withValues(alpha: 0.72),
    };
  }

  Color _shadowColor(ColorScheme colors, AppBrandColors brand, bool focused) {
    if (widget.variant == TactileButtonVariant.destructive) {
      return colors.error.withValues(alpha: focused ? 0.22 : 0.14);
    }
    return brand.onAccentLight.withValues(alpha: focused ? 0.2 : 0.14);
  }
}
