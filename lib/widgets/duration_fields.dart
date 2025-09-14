import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Compact Hours/Minutes inputs with validation and select‑all on focus.
///
/// Usage:
/// ```dart
/// DurationFields(
///   hours: entry.hours,
///   minutes: entry.minutes,
///   onChanged: (h, m) => setState(() { entry.hours = h; entry.minutes = m; }),
/// )
/// ```
class DurationFields extends StatefulWidget {
  const DurationFields({
    super.key,
    required this.hours,
    required this.minutes,
    required this.onChanged,
    this.enabled = true,
    this.minWidth = 90,
    this.gap = 12,
    this.labelStyle,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final int hours;
  final int minutes;
  final bool enabled;
  final double minWidth;
  final double gap;
  final TextStyle? labelStyle;
  final AutovalidateMode autovalidateMode;
  final void Function(int hours, int minutes) onChanged;

  @override
  State<DurationFields> createState() => _DurationFieldsState();
}

class _DurationFieldsState extends State<DurationFields> {
  late final TextEditingController _hCtrl;
  late final TextEditingController _mCtrl;
  final _hFocus = FocusNode();
  final _mFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hCtrl = TextEditingController(text: (widget.hours).toString());
    _mCtrl = TextEditingController(text: (widget.minutes).toString());
    // Select-all on first focus
    _hFocus.addListener(() {
      if (_hFocus.hasFocus) {
        _hCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _hCtrl.text.length);
      }
    });
    _mFocus.addListener(() {
      if (_mFocus.hasFocus) {
        _mCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _mCtrl.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DurationFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hours != widget.hours && !_hFocus.hasFocus) {
      _hCtrl.text = widget.hours.toString();
    }
    if (oldWidget.minutes != widget.minutes && !_mFocus.hasFocus) {
      _mCtrl.text = widget.minutes.toString();
    }
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    _hFocus.dispose();
    _mFocus.dispose();
    super.dispose();
  }

  String? _validateHours(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    final n = int.tryParse(v);
    if (n == null) return 'Numbers only';
    if (n < 0) return 'Must be ≥ 0';
    if (n > 999) return 'Too large';
    return null;
  }

  String? _validateMinutes(String? v) {
    if (v == null || v.isEmpty) return 'Required';
    final n = int.tryParse(v);
    if (n == null) return 'Numbers only';
    if (n < 0) return 'Must be ≥ 0';
    if (n > 59) return '0–59';
    return null;
  }

  void _notify() {
    var h = int.tryParse(_hCtrl.text) ?? 0;
    var m = int.tryParse(_mCtrl.text) ?? 0;
    if (h < 0) h = 0; if (h > 999) h = 999;
    if (m < 0) m = 0; if (m > 59) m = 59;
    widget.onChanged(h, m);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            enabled: widget.enabled,
            controller: _hCtrl,
            focusNode: _hFocus,
            keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _mFocus.requestFocus(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            autovalidateMode: widget.autovalidateMode,
            validator: _validateHours,
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: 'Hours',
              labelStyle: widget.labelStyle,
              isDense: true,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(width: widget.gap),
        Expanded(
          child: TextFormField(
            enabled: widget.enabled,
            controller: _mCtrl,
            focusNode: _mFocus,
            keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            autovalidateMode: widget.autovalidateMode,
            validator: _validateMinutes,
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: 'Minutes',
              labelStyle: widget.labelStyle,
              isDense: true,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}