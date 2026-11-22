import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../cpd_compatibility/cpd_data_store.dart';
import '../cpd_creation/profession_creation_store.dart';
import '../l10n/app_localizations.dart';
import '../recording_engine_storage/managed_attachment_files.dart';
import '../recording_engine_storage/portable_archive.dart';
import '../recording_engine_storage/sqlite_recording_repository.dart';
import '../widgets/branded_headers.dart';
import '../widgets/tactile_button.dart';

/// Explicitly supplied by the rehearsal composition root.
class ProfessionBackupActions {
  const ProfessionBackupActions({
    required this.backups,
    required this.temporary,
    required this.originals,
    required this.pick,
    required this.share,
  });

  final SqliteCollectionBackup backups;
  final Directory temporary;
  final ManagedAttachmentFiles originals;
  final Future<File?> Function() pick;
  final Future<void> Function(File, Rect) share;

  Future<CollectionImportResult?> open(
    BuildContext context,
    ProfessionCreationStore store, {
    String? collectionId,
  }) => Navigator.of(context).push<CollectionImportResult>(
    MaterialPageRoute(
      builder: (_) => _ProfessionBackupPage(
        actions: this,
        store: store,
        collectionId: collectionId,
      ),
    ),
  );
}

class _ProfessionBackupPage extends StatefulWidget {
  const _ProfessionBackupPage({
    required this.actions,
    required this.store,
    this.collectionId,
  });
  final ProfessionBackupActions actions;
  final ProfessionCreationStore store;
  final String? collectionId;
  @override
  State<_ProfessionBackupPage> createState() => _ProfessionBackupPageState();
}

class _ProfessionBackupPageState extends State<_ProfessionBackupPage> {
  CollectionBackupExport? _export;
  CollectionBackupReview? _review;
  CollectionImportResult? _conflict;
  String? _message;
  bool _busy = false;
  bool _confirmedGaps = false;
  bool _encrypt = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    // Routes cannot pop during an operation. If the host is torn down, its
    // private cache is reconciled on the next rehearsal launch.
    _export?.dispose().ignore();
    _review?.dispose().ignore();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final s = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on BackupException catch (error) {
      _message = switch (error.problem) {
        BackupProblem.authentication => s.pbAuthentication,
        BackupProblem.capacity => s.p8LowSpace,
        BackupProblem.version => s.p8Unsupported,
        _ => s.pbFailed,
      };
    } catch (_) {
      _message = s.pbFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _password({required bool create}) => showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(create: create),
  );

  Future<void> _prepare() => _run(() async {
    _export = await widget.actions.backups.create(
      repository: widget.store.repository,
      collectionId: widget.collectionId!,
      originals: widget.actions.originals.root,
      temporary: widget.actions.temporary,
    );
  });

  Future<void> _share(Rect anchor) => _run(() async {
    final output = _export!;
    final password = _encrypt ? await _password(create: true) : null;
    if (_encrypt && password == null) return;
    final file = await output.fileForSharing(
      password: password,
      acceptUnavailable: _confirmedGaps,
    );
    try {
      await widget.actions.share(file, anchor);
    } finally {
      if (_encrypt) await file.delete();
    }
  });

  Future<void> _choose() => _run(() async {
    final source = await widget.actions.pick();
    if (source == null || !mounted) return;
    final encrypted = await SqliteCollectionBackup.encryption.isEncrypted(
      source,
    );
    if (!mounted) return;
    final password = encrypted ? await _password(create: false) : null;
    if (encrypted && password == null) return;
    await _review?.dispose();
    _review = null;
    _conflict = null;
    _review = await widget.actions.backups.inspect(
      source: source,
      temporary: widget.actions.temporary,
      password: password,
    );
    if (mounted) _name.text = _review!.summary.label;
  });

  Future<void> _restore() => _run(() async {
    final result = await widget.actions.backups.restore(
      review: _review!,
      repository: widget.store.repository,
      originals: widget.actions.originals,
      label: cpdProfessionLabel(_name.text),
      canUseName: widget.store.canUseNameInTransaction,
    );
    if (!mounted) return;
    if (result.status == CollectionImportStatus.added) {
      // Allow the route to pop after its busy guard is removed.
      setState(() => _busy = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
    } else {
      _conflict = result;
    }
  });

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    final export = _export;
    final restore = _review;
    final title = widget.collectionId == null ? s.pbRestore : s.p8Create;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: ListView(
            children: [
              BrandedPageHeader(title: title, icon: Icons.archive_outlined),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.collectionId != null) ...[
                      if (export == null)
                        TactileButton(
                          onPressed: _busy ? null : _prepare,
                          child: Text(s.p8Create),
                        ),
                      if (export != null) ...[
                        _summary(context, export.summary),
                        Text(s.pbBackupSaved),
                        if (export.summary.unavailable.isNotEmpty)
                          CheckboxListTile(
                            title: Text(s.pbIncludeGaps),
                            value: _confirmedGaps,
                            onChanged: _busy
                                ? null
                                : (value) =>
                                      setState(() => _confirmedGaps = value!),
                          ),
                        SwitchListTile(
                          title: Text(s.pbEncrypt),
                          value: _encrypt,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _encrypt = value),
                        ),
                        Text(_encrypt ? s.pbPasswordHelp : s.pbPrivate),
                        const SizedBox(height: 12),
                        Builder(
                          builder: (buttonContext) => TactileButton(
                            variant: TactileButtonVariant.primary,
                            onPressed:
                                _busy ||
                                    (export.summary.unavailable.isNotEmpty &&
                                        !_confirmedGaps)
                                ? null
                                : () {
                                    final box =
                                        buttonContext.findRenderObject()
                                            as RenderBox;
                                    _share(
                                      box.localToGlobal(Offset.zero) & box.size,
                                    );
                                  },
                            child: Text(s.p8Share),
                          ),
                        ),
                      ],
                    ] else ...[
                      TactileButton(
                        onPressed: _busy ? null : _choose,
                        child: Text(s.p8Choose),
                      ),
                      if (restore != null) ...[
                        _summary(context, restore.summary),
                        TextField(
                          controller: _name,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: s.professionLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TactileButton(
                          variant: TactileButtonVariant.primary,
                          onPressed: _busy ? null : _restore,
                          child: Text(s.pbAddRestored),
                        ),
                      ],
                    ],
                    if (_conflict case final state?) ...[
                      if (state.collection case final collection?)
                        Text(collection.label),
                      Semantics(
                        liveRegion: true,
                        child: Text(switch (state.status) {
                          CollectionImportStatus.recoverable =>
                            s.pbDeletedExisting,
                          CollectionImportStatus.existing => s.pbExisting,
                          _ => s.pbNameInUse,
                        }),
                      ),
                      if (state.status == CollectionImportStatus.existing ||
                          state.status == CollectionImportStatus.recoverable)
                        TextButton(
                          onPressed: () => Navigator.pop(context, state),
                          child: Text(
                            state.status == CollectionImportStatus.existing
                                ? s.pbOpenExisting
                                : s.viewDeletedProfessions,
                          ),
                        ),
                    ],
                    if (_busy) const LinearProgressIndicator(),
                    if (_message case final message?)
                      Semantics(liveRegion: true, child: Text(message)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, CollectionBackupSummary summary) {
    final s = AppLocalizations.of(context)!;
    final date = DateFormat.yMMMd(
      s.localeName,
    ).add_jm().format(summary.created.toLocal());
    final number = NumberFormat.decimalPattern(s.localeName);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary.label, style: Theme.of(context).textTheme.titleLarge),
          Semantics(liveRegion: true, child: Text(s.p8Verified)),
          Text(date),
          Text('${s.pbRecords} · ${number.format(summary.recordCount)}'),
          if (summary.deletedRecords > 0)
            Text('${s.pbDeleted} · ${number.format(summary.deletedRecords)}'),
          Text(
            '${s.pbAttachments} · ${number.format(summary.attachmentCount)}',
          ),
          Text('${s.p8Originals} · ${number.format(summary.originals)}'),
          if (summary.links > 0)
            Text('${s.pbLinks} · ${number.format(summary.links)}'),
          if (summary.unavailable.isNotEmpty) ...[
            Text(
              '${s.pbUnavailable} · ${number.format(summary.unavailable.length)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final issue in summary.unavailable)
              Text(
                '${issue.name} · ${issue.reason == UnavailableOriginal.damaged ? s.pbDamaged : s.pbMissing}',
              ),
          ],
        ],
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.create});
  final bool create;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(s.pbPassword),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: s.pbPassword),
              ),
              if (widget.create)
                TextFormField(
                  controller: _repeat,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(labelText: s.pbRepeat),
                  validator: (input) =>
                      input == _password.text && _password.text.length >= 8
                      ? null
                      : s.pbAuthMismatch,
                ),
              const SizedBox(height: 12),
              Text(s.pbPasswordHelp),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate() && _password.text.isNotEmpty) {
              Navigator.pop(context, _password.text);
            }
          },
          child: Text(s.continueLabel),
        ),
      ],
    );
  }
}
