import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../recording_engine/storage_authority.dart';
import '../migration_report.dart';

typedef PrepareRecordingStore =
    Future<StartupAuthority> Function(
      Future<void> Function(MigrationReport) reportProgress,
    );

/// Internal recovery route. The host must defer opening either store until
/// the coordinator returns a guarded recording authority.
class MigrationRecoveryPage extends StatefulWidget {
  const MigrationRecoveryPage({
    super.key,
    required this.prepare,
    required this.onReady,
  });

  final PrepareRecordingStore prepare;
  final VoidCallback onReady;

  @override
  State<MigrationRecoveryPage> createState() => _MigrationRecoveryPageState();
}

class _MigrationRecoveryPageState extends State<MigrationRecoveryPage> {
  MigrationPhase? _phase;
  StartupAuthority? _result;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      StartupAuthority? result;
      try {
        result = await widget.prepare((report) async {
          if (mounted) setState(() => _phase = report.phase);
        });
      } catch (_) {
        // The host has not opened a writer. Offer only the support route.
      }
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    });
  }

  Future<void> _copyDetails() async {
    final result = _result;
    final text = AppLocalizations.of(context)!;
    // Keep identifiers, filesystem paths and personal data out of diagnostics.
    await Clipboard.setData(
      ClipboardData(
        text:
            'CPD migration recovery\n'
            'Startup: ${result?.reason.name ?? 'unavailable'}\n'
            'Recovery copy: ${result?.recoveryCopy.name ?? 'unchecked'}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.migrationDetailsCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppLocalizations.of(context)!;
    final ready = _result?.store == StoreAuthority.recording;
    final theme = Theme.of(context);
    final step = switch (_phase) {
      MigrationPhase.copyingRecovery => text.migrationCopy,
      MigrationPhase.staging => text.migrationMove,
      MigrationPhase.verifying ||
      MigrationPhase.handoffReserved => text.migrationVerify,
      MigrationPhase.checkingStorage => text.migrationCheckSpace,
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(text.appTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _busy
                        ? text.migrationPreparingRecords
                        : ready
                        ? text.migrationRecordsReady
                        : text.migrationNeedsRecovery,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                if (_busy) ...[
                  Text(text.migrationKeepOpen),
                  const SizedBox(height: 24),
                  LinearProgressIndicator(
                    semanticsLabel: step ?? text.migrationPreparingRecords,
                  ),
                  if (step != null) ...[const SizedBox(height: 8), Text(step)],
                ] else if (ready)
                  FilledButton(
                    onPressed: widget.onReady,
                    child: Text(
                      MaterialLocalizations.of(context).continueButtonLabel,
                    ),
                  )
                else ...[
                  Text(text.migrationContactSupport),
                  const SizedBox(height: 8),
                  const SelectableText('bmbapps@icloud.com'),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: _copyDetails,
                    child: Text(text.migrationCopyDetails),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
