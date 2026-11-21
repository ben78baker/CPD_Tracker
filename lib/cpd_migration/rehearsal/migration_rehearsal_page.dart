import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../migration_coordinator.dart';
import '../migration_report.dart';

enum RehearsalSample { standard, review, lowStorage }

typedef OpenRehearsal =
    Future<CpdMigrationCoordinator> Function(
      RehearsalSample sample,
      Future<void> Function(MigrationReport) onCheckpoint,
    );

/// Used only from the separate synthetic debug entry point.
class MigrationRehearsalPage extends StatefulWidget {
  const MigrationRehearsalPage({
    super.key,
    required this.openAttempt,
    this.initialSample = RehearsalSample.standard,
    this.autoRun = false,
  });

  final OpenRehearsal openAttempt;
  final RehearsalSample initialSample;
  final bool autoRun;

  @override
  State<MigrationRehearsalPage> createState() => _MigrationRehearsalPageState();
}

class _MigrationRehearsalPageState extends State<MigrationRehearsalPage> {
  late RehearsalSample _sample = widget.initialSample;
  CpdMigrationCoordinator? _attempt;
  MigrationReport? _report;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  Future<void> _update(MigrationReport report) async {
    if (mounted) setState(() => _report = report);
  }

  Future<void> _run({bool abandon = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final attempt = _attempt ??= await widget.openAttempt(_sample, _update);
      await _update(
        await (abandon ? attempt.abandonStaging() : attempt.rehearse()),
      );
    } catch (_) {
      await _update(const MigrationReport(MigrationPhase.failed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOriginal(int row) async {
    final text = AppLocalizations.of(context)!;
    String content;
    try {
      content = (await _attempt!.readOriginalRow(row)).toString();
    } catch (_) {
      content = text.migrationOriginalUnavailable;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.migrationOriginal),
        content: SingleChildScrollView(child: SelectableText(content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final report = _report;
    final phase = report?.phase;
    final review = phase == MigrationPhase.reviewRequired;
    final ready = phase == MigrationPhase.ready;
    final failed = phase == MigrationPhase.failed;
    final abandoned = phase == MigrationPhase.abandoned;
    final canLeaveAttempt =
        !_busy && (review || ready || failed) && _attempt != null;
    final low = report?.failure == 'insufficient_storage';

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(text.migrationTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (phase == null) ...[
                    Text(text.migrationIntro, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 22),
                    DropdownButtonFormField<RehearsalSample>(
                      initialValue: _sample,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: text.migrationScenario,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: RehearsalSample.standard,
                          child: Text(text.migrationStandardSample),
                        ),
                        DropdownMenuItem(
                          value: RehearsalSample.review,
                          child: Text(text.migrationReviewSample),
                        ),
                        DropdownMenuItem(
                          value: RehearsalSample.lowStorage,
                          child: Text(text.migrationLowSpaceSample),
                        ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _sample = value!),
                    ),
                  ],
                  if (_busy || phase != null)
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                low
                                    ? text.migrationLowSpaceSample
                                    : _heading(text, phase),
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              if (_busy) ...[
                                LinearProgressIndicator(
                                  semanticsLabel: _heading(text, phase),
                                ),
                                const SizedBox(height: 10),
                                Text(text.migrationStay),
                              ] else if (low)
                                Text(text.migrationSpaceDetail)
                              else if (failed)
                                Text(text.migrationProblemDetail)
                              else if (review)
                                Text(text.migrationReviewDetail)
                              else if (ready)
                                Text(text.migrationReadyDetail),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (!_busy && report != null)
                    for (final issue in report.review)
                      ListTile(
                        leading: Icon(
                          issue.disposition ==
                                  RecoveryDisposition.requiresResolution
                              ? Icons.info_outline
                              : Icons.bookmark_outline,
                        ),
                        title: Text(_issueLabel(text, issue.code)),
                        subtitle: issue.row == null
                            ? null
                            : Text(text.migrationOriginal),
                        onTap: issue.row == null
                            ? null
                            : () => _showOriginal(issue.row!),
                      ),
                  const SizedBox(height: 16),
                  if (!_busy && (phase == null || failed))
                    FilledButton(
                      onPressed: _run,
                      child: Text(
                        failed ? text.migrationRetry : text.migrationStart,
                      ),
                    ),
                  if (canLeaveAttempt && failed) const SizedBox(height: 10),
                  if (canLeaveAttempt)
                    OutlinedButton(
                      onPressed: () => _run(abandon: true),
                      child: Text(text.migrationKeepAttempt),
                    ),
                  if (!_busy && abandoned)
                    FilledButton(
                      onPressed: () => setState(() {
                        _attempt = null;
                        _report = null;
                      }),
                      child: Text(text.migrationNew),
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

String _heading(AppLocalizations text, MigrationPhase? phase) =>
    switch (phase) {
      MigrationPhase.copyingRecovery ||
      MigrationPhase.snapshotReady => text.migrationCopy,
      MigrationPhase.staging => text.migrationMove,
      MigrationPhase.verifying => text.migrationVerify,
      MigrationPhase.ready ||
      MigrationPhase.handoffReserved ||
      MigrationPhase.rehearsalActivated ||
      MigrationPhase.productionActivated => text.migrationReady,
      MigrationPhase.reviewRequired => text.migrationReview,
      MigrationPhase.failed => text.migrationProblem,
      MigrationPhase.abandoned => text.migrationStopped,
      _ => text.migrationCheckSpace,
    };

String _issueLabel(AppLocalizations text, String code) => switch (code) {
  'duplicate_legacy_id' => text.migrationDuplicate,
  'invalid_or_ambiguous_activity_date' => text.migrationDate,
  'fractional_duration' => text.migrationDuration,
  'unsupported_evidence_reference' ||
  'unreadable_attachment' => text.migrationUnsupportedEvidence,
  'unresolved_attachment' => text.migrationMissingEvidence,
  _ => text.migrationOtherIssue,
};
