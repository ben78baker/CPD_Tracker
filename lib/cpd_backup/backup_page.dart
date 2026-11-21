import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../recording_engine_storage/portable_archive.dart';
import '../widgets/branded_headers.dart';
import '../widgets/form_section_tile.dart';
import '../widgets/tactile_button.dart';

typedef BackupFile = ({File file, BackupInspection inspection});

/// The host supplies file picking/sharing and a protected restore operation.
/// Production navigation does not include this internal rehearsal page.
class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.create,
    required this.chooseAndVerify,
    required this.share,
    required this.prepareReplacement,
  });

  final Future<BackupFile> Function() create;
  final Future<BackupFile?> Function() chooseAndVerify;
  final Future<void> Function(File file, Rect anchor) share;
  final Future<void> Function(BackupFile backup) prepareReplacement;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  BackupFile? _created;
  BackupFile? _selected;
  bool _busy = false;
  bool _prepared = false;
  BackupProblem? _failure;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _prepared = false;
      _failure = null;
    });
    try {
      await action();
    } on BackupException catch (error) {
      if (mounted) _failure = error.problem;
    } catch (_) {
      if (mounted) _failure = BackupProblem.integrity;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(BackupFile backup) async {
    final loc = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.p8Restore),
        content: SingleChildScrollView(child: Text(loc.p8Confirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          TactileButton(
            variant: TactileButtonVariant.destructive,
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.p8Restore),
          ),
        ],
      ),
    );
    if (mounted && yes == true) {
      await _run(() async {
        await widget.prepareReplacement(backup);
        if (mounted) {
          _prepared = true;
          _selected = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: ListView(
            children: [
              BrandedPageHeader(
                title: loc.p8Title,
                icon: Icons.archive_outlined,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.p8Private),
                    const SizedBox(height: 16),
                    FormSectionTile(
                      label: loc.p8Portable,
                      icon: Icons.save_outlined,
                      supportingText: loc.p8Includes,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TactileButton(
                            variant: TactileButtonVariant.primary,
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    final output = await widget.create();
                                    if (mounted) _created = output;
                                  }),
                            child: Text(loc.p8Create),
                          ),
                          if (_created case final output?) ...[
                            _details(context, output.inspection),
                            Builder(
                              builder: (buttonContext) => TactileButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(() {
                                        final box =
                                            buttonContext.findRenderObject()
                                                as RenderBox;
                                        return widget.share(
                                          output.file,
                                          box.localToGlobal(Offset.zero) &
                                              box.size,
                                        );
                                      }),
                                child: Text(loc.p8Share),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.restore,
                      icon: Icons.settings_backup_restore,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TactileButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() async {
                                    _selected = null;
                                    final result = await widget
                                        .chooseAndVerify();
                                    if (mounted) _selected = result;
                                  }),
                            child: Text(loc.p8Choose),
                          ),
                          if (_selected case final input?) ...[
                            _details(context, input.inspection),
                            Text(loc.p8Confirm),
                            const SizedBox(height: 8),
                            TactileButton(
                              variant: TactileButtonVariant.destructive,
                              onPressed: _busy ? null : () => _confirm(input),
                              child: Text(loc.p8Restore),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (_prepared || _failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(switch (_failure) {
                            BackupProblem.capacity => loc.p8LowSpace,
                            BackupProblem.version => loc.p8Unsupported,
                            null => loc.p8Restored,
                            _ => loc.p8Failed,
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, BackupInspection check) {
    final loc = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(
      language,
    ).add_jm().format(check.created.toLocal());
    final files = NumberFormat.decimalPattern(language).format(check.originals);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.p8Verified, style: Theme.of(context).textTheme.titleSmall),
            Text(date),
            Text('${loc.p8Originals} · $files'),
          ],
        ),
      ),
    );
  }
}
