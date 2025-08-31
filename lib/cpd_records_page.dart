import 'package:flutter/material.dart';
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'add_entry_page.dart';

class CpdRecordsPage extends StatefulWidget {
  const CpdRecordsPage({super.key, required this.profession});
  final String profession;

  @override
  State<CpdRecordsPage> createState() => _CpdRecordsPageState();
}

class _CpdRecordsPageState extends State<CpdRecordsPage> {
  final _repo = EntryRepository();
  final _settings = SettingsStore();
  List<CpdEntry> _entries = [];
  String _fmt = 'dd/MM/yyyy';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _repo.loadForProfession(widget.profession);
    list.sort((a, b) => b.date.compareTo(a.date)); // newest first
    final fmt = await _settings.getDateFormat();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _fmt = fmt;
    });
  }

  Future<void> _edit(CpdEntry e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryPage(profession: e.profession, existingEntry: e),
      ),
    );
    _load();
  }

  Future<void> _toggleDelete(CpdEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.deleted ? 'Restore record?' : 'Delete record?'),
        content: Text(e.deleted
            ? 'Do you want to restore this record?'
            : 'Do you want to delete this record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(e.deleted ? 'Restore' : 'Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.setDeleted(e.id, !e.deleted);
      _load();
    }
  }

  void _showAttachments(CpdEntry e) {
    if (e.attachments.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => const AlertDialog(
          title: Text('Attachments'),
          content: Text('No items have been added.'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attachments'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: e.attachments.length,
            itemBuilder: (ctx, i) => ListTile(
              title: Text(e.attachments[i]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.profession)),
      body: _entries.isEmpty
          ? const Center(child: Text('No CPD records yet.'))
          : ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, i) {
                final e = _entries[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row + per-record menu
                        Row(
                          children: [
                            Expanded(
                              child: Text(e.title, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _edit(e);
                                if (value == 'delete') _toggleDelete(e);
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'edit', child: Text('Edit record')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(e.deleted ? 'Restore record' : 'Delete record'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatDate(e.date, _fmt)}   ${e.hours}h ${e.minutes}m',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(e.details),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(
                            onPressed: () => _showAttachments(e),
                            child: const Text('Attachments'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}