import 'package:cpd_tracker/cpd_creation/profession_creation_store.dart';
import 'package:cpd_tracker/cpd_creation/template_evaluation.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:flutter/material.dart';

class EvaluationSummary extends StatelessWidget {
  const EvaluationSummary(this.status, {super.key, this.explain = false});
  final TemplateEvaluationStatus status;
  final bool explain;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final used = status.used;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (used) {
          _ when status.owned => s.evaluationUnlimited,
          null => s.evaluationUnavailable,
          0 => s.evaluationAvailable(templateRecordAllowance),
          _ => s.evaluationUsed(used, templateRecordAllowance),
        }),
        if (!status.owned && explain)
          Text(s.evaluationTerms(templateRecordAllowance)),
      ],
    );
  }
}

class TemplateEvaluationPanel extends StatefulWidget {
  const TemplateEvaluationPanel({
    super.key,
    required this.store,
    required this.templateId,
    required this.purchase,
    this.onUse,
    this.onStandard,
    this.onStatus,
    this.ownedOnly = false,
  });

  final ProfessionCreationStore store;
  final String templateId;
  final Future<void> Function() purchase;
  final VoidCallback? onUse, onStandard;
  final ValueChanged<TemplateEvaluationStatus>? onStatus;
  final bool ownedOnly;

  @override
  State<TemplateEvaluationPanel> createState() =>
      _TemplateEvaluationPanelState();
}

class _TemplateEvaluationPanelState extends State<TemplateEvaluationPanel> {
  TemplateEvaluationStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool purchase = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    TemplateEvaluationStatus status;
    try {
      if (purchase) await widget.purchase();
      if (!mounted) return;
      status = await widget.store.evaluationStatus(widget.templateId);
    } on Object {
      status = const TemplateEvaluationStatus();
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _busy = false;
    });
    widget.onStatus?.call(status);
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final status = _status;
    if (status == null) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.ownedOnly || status.owned)
          EvaluationSummary(
            status,
            explain: widget.onUse != null || !status.canCreate,
          ),
        if (widget.onUse != null &&
            (widget.ownedOnly ? status.owned : status.canCreate))
          FilledButton(
            onPressed: _busy ? null : widget.onUse,
            child: Text(s.p6ChooseTemplate),
          ),
        if (!status.owned)
          OutlinedButton(
            onPressed: _busy ? null : () => _refresh(purchase: true),
            child: Text(
              status.exhausted && !widget.ownedOnly
                  ? s.evaluationExhausted
                  : s.evaluationBuy,
            ),
          ),
        if (!status.canCreate && widget.onStandard != null)
          TextButton(
            onPressed: widget.onStandard,
            child: Text(s.evaluationStandard),
          ),
      ],
    );
  }
}
