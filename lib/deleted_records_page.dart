import 'package:flutter/material.dart';

import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';
import 'widgets/branded_headers.dart';
import 'widgets/tactile_button.dart';

class DeletedRecordsPage extends StatefulWidget {
  const DeletedRecordsPage({super.key});

  @override
  State<DeletedRecordsPage> createState() => _DeletedRecordsPageState();
}

class _DeletedRecordsPageState extends State<DeletedRecordsPage> {
  List<CpdEntry> _records = [];
  String _dateFormat = 'dd/MM/yyyy';
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await EntryRepository().loadDeleted();
      final format = await SettingsStore.instance.getDateFormat();
      if (!mounted) return;
      setState(() {
        _records = records;
        _dateFormat = format;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _restore(CpdEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final active = await SettingsStore.instance.loadActiveProfessions();
      final needsProfession = !active.any(
        (name) =>
            name.trim().toLowerCase() == entry.profession.trim().toLowerCase(),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.restoreRecordTitle),
          content: Text(
            needsProfession
                ? AppLocalizations.of(
                    context,
                  )!.restoreRecordProfessionConfirm(entry.profession)
                : AppLocalizations.of(context)!.restoreRecordConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context)!.restore),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await SettingsStore.instance.restoreRecord(
        entry.id,
        recoverProfession: needsProfession,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.recordRestoreFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Column(
      children: [
        BrandedPageHeader(
          title: AppLocalizations.of(context)!.deletedRecordsTitle,
          icon: Icons.restore,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadFailed
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: Text(
                      AppLocalizations.of(context)!.deletedRecordsLoadFailed,
                    ),
                  ),
                )
              : _records.isEmpty
              ? Center(
                  child: Text(AppLocalizations.of(context)!.noDeletedRecords),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final entry = _records[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${entry.profession} · ${formatDate(entry.date, _dateFormat)}',
                            ),
                            const SizedBox(height: 8),
                            TactileButton.icon(
                              key: ValueKey('restore-record-${entry.id}'),
                              onPressed: _busy ? null : () => _restore(entry),
                              icon: const Icon(Icons.restore),
                              label: Text(
                                AppLocalizations.of(context)!.restore,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
