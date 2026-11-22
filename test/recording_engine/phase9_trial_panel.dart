import 'dart:async';

import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_trials.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:flutter/material.dart';

/// The CPD host supplies purchase and activation outside the sample renderer.
class TemplateTrialPanel extends StatefulWidget {
  const TemplateTrialPanel({
    super.key,
    required this.store,
    required this.templateId,
    required this.purchase,
    this.onUse,
    this.onStandard,
    this.onStatus,
  });

  final ProfessionCreationStore store;
  final String templateId;
  final Future<void> Function() purchase;
  final VoidCallback? onUse, onStandard;
  final ValueChanged<TemplateTrialStatus>? onStatus;

  @override
  State<TemplateTrialPanel> createState() => _TemplateTrialPanelState();
}

class _TemplateTrialPanelState extends State<TemplateTrialPanel>
    with WidgetsBindingObserver {
  TemplateTrialStatus? _status;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _refresh({bool start = false, bool purchase = false}) async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    late TemplateTrialStatus next;
    try {
      if (purchase) await widget.purchase();
      if (!mounted) return;
      next = start
          ? await widget.store.startTrial(widget.templateId)
          : await widget.store.trialStatus(widget.templateId);
    } on Object {
      next = const TemplateTrialStatus(TemplateTrialState.unavailable);
    }
    if (!mounted) return;
    final previous = _status?.state;
    setState(() {
      _status = next;
      _busy = false;
    });
    if (previous != next.state) widget.onStatus?.call(next);
    if (start && next.active) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(editorStrings(context).trialStarted)),
      );
    }
    if (next.remaining case final remaining?) {
      var delay = const Duration(seconds: 30);
      for (final threshold in [0, 1, 3]) {
        final until = remaining - Duration(days: threshold);
        if (until > Duration.zero && until < delay) delay = until;
      }
      _timer = Timer(delay, _refresh);
    }
  }

  String _remaining(BuildContext context, Duration time) {
    final s = editorStrings(context);
    final hours = time.inHours;
    final minutes = hours == 0
        ? time.inMinutes.clamp(1, 59)
        : time.inMinutes.remainder(60);
    return [
      if (hours > 0) s.hoursPlural(hours),
      s.minutesPlural(minutes),
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final current = _status;
    if (current == null) return const LinearProgressIndicator();
    final state = current.state;
    final owned = state == TemplateTrialState.owned;
    final remaining = current.remaining;
    final ended = state == TemplateTrialState.ended;
    final use = widget.onUse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!owned) Text(s.trialTerms),
        if (remaining != null) ...[
          Text(s.trialRemaining(_remaining(context, remaining))),
          if (remaining <= const Duration(days: 3))
            Semantics(
              liveRegion: true,
              child: Text(
                remaining <= const Duration(days: 1)
                    ? s.trialOneDay
                    : s.trialThreeDays,
              ),
            ),
        ],
        if (state == TemplateTrialState.unavailable) Text(s.trialUnavailable),
        if (use != null && state == TemplateTrialState.eligible)
          FilledButton(
            onPressed: _busy ? null : () => _refresh(start: true),
            child: Text(s.trialStart),
          ),
        if (use != null && (owned || current.active))
          FilledButton(
            onPressed: _busy ? null : use,
            child: Text(s.p6ChooseTemplate),
          ),
        if (!owned)
          OutlinedButton(
            onPressed: _busy ? null : () => _refresh(purchase: true),
            child: Semantics(
              liveRegion: ended,
              child: Text(ended ? s.trialEnded : s.trialBuy),
            ),
          ),
        if (!owned && !current.active && widget.onStandard != null)
          TextButton(
            onPressed: widget.onStandard,
            child: Text(s.trialStandard),
          ),
      ],
    );
  }
}
