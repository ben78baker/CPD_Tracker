import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'add_entry_page.dart';
import 'edit_details_page.dart';
import 'qr_scan_page.dart';
import 'cpd_records_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _professions = <String>[];
  List<String> _deleted = <String>[];

  String _suggestTitleFromScan(String s) {
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.hasScheme || s.startsWith('www.'))) {
    final host = uri.host.isNotEmpty ? uri.host : s;
    return 'Evidence: $host';
  }
  return s.length <= 40 ? s : s.substring(0, 40);
}

void _openRecords(String profession) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CpdRecordsPage(profession: profession)),
  );
}

Future<void> _scanQrAndPrefill(String profession) async {
  final result = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => QrScanPage(profession: profession)),
  );
  if (!mounted) return;
  if (result != null && result.isNotEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryPage(
          profession: profession,
          prefillDate: DateTime.now(),
          prefillAttachments: [result],
          prefillTitle: _suggestTitleFromScan(result),
        ),
      ),
    );
  }
}

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _load());
}

  Future<void> _load() async {
    final active = await SettingsStore.instance.loadActiveProfessions();
    final deleted = await SettingsStore.instance.loadDeletedProfessions();
    if (!mounted) return;
    setState(() {
      _professions = List.of(active);
      _deleted = List.of(deleted);
    });
  }


  Future<void> _addProfessionDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add profession'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Enter profession'),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Please enter a profession';
              if (_professions.map((e) => e.toLowerCase()).contains(val.toLowerCase())) {
                return 'That profession already exists';
              }
              if (_deleted.map((e) => e.toLowerCase()).contains(val.toLowerCase())) {
                return 'That name is in Deleted. Restore it instead.';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      // Persist using centralized normalize+dedupe+sort
      await SettingsStore.instance.addProfession(result);
      // Reload from store to reflect canonical formatting
      final refreshed = await SettingsStore.instance.loadActiveProfessions();
      final deleted = await SettingsStore.instance.loadDeletedProfessions();
      if (!mounted) return;
      setState(() {
        _professions = List.of(refreshed);
        _deleted = List.of(deleted);
      });
    }
  }

  Future<void> _renameProfession(int index) async {
    final controller = TextEditingController(text: _professions[index]);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename profession'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Please enter a name';
              if (_professions.asMap().entries.any(
                    (e) => e.key != index && e.value.toLowerCase() == val.toLowerCase(),
                  )) {
                return 'That profession already exists';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      // Update local list, then save via centralized save (which normalizes/dedupes/sorts)
      final next = List<String>.of(_professions);
      next[index] = result;
      await SettingsStore.instance.saveProfessions(next);
      final refreshed = await SettingsStore.instance.loadActiveProfessions();
      final deleted = await SettingsStore.instance.loadDeletedProfessions();
      if (!mounted) return;
      setState(() {
        _professions = List.of(refreshed);
        _deleted = List.of(deleted);
      });
    }
  }

  Future<void> _deleteProfession(int index) async {
    final name = _professions[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profession?'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      final name = _professions[index];
      await SettingsStore.instance.softDeleteProfession(name);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved "$name" to Deleted')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CPD Tracker'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) async {
              if (value == 'add_profession') {
                await _addProfessionDialog();
              } else if (value == 'edit_details') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditDetailsPage()),
                );
                if (mounted) setState(() {});
              } else if (value == 'view_deleted') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeletedProfessionsPage()),
                );
                await _load();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'add_profession', child: Text('Add Profession')),
              PopupMenuItem(value: 'edit_details', child: Text('Edit Personal Details')),
              PopupMenuItem(value: 'view_deleted', child: Text('View Deleted Professions')),
            ],
          ),
        ],
      ),
      body: _professions.isEmpty
          ? const Center(child: Text('No professions yet. Use menu → Add Profession.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _professions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final name = _professions[index];
                return _ProfessionCard(
                  name: name,
                  onAdd: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AddEntryPage(profession: name)),
                  ),
                  onScan: () => _scanQrAndPrefill(name),
                  onView: () => _openRecords(name),
                  onRename: () => _renameProfession(index),
                  onDelete: () => _deleteProfession(index),
                );
              },
            ),
    );
  }
}

class _ProfessionCard extends StatelessWidget {
  const _ProfessionCard({
    required this.name,
    required this.onAdd,
    required this.onScan,
    required this.onView,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onView;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.all(16.0);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onView, // tap card → view records
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // important for ListView items
            children: [
              // Header: name + kebab menu
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename Profession')),
                      PopupMenuItem(value: 'delete', child: Text('Delete Profession')),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action row
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Entry'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // View records full-width
              SizedBox(
                width: double.infinity,
                    child: FilledButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.list),
                  label: const Text('View Records'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeletedProfessionsPage extends StatefulWidget {
  const DeletedProfessionsPage({super.key});
  @override
  State<DeletedProfessionsPage> createState() => _DeletedProfessionsPageState();
}

class _DeletedProfessionsPageState extends State<DeletedProfessionsPage> {
  List<String> _deleted = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await SettingsStore.instance.loadDeletedProfessions();
    if (!mounted) return;
    setState(() { _deleted = items; _loading = false; });
  }

  Future<void> _restore(String name) async {
    await SettingsStore.instance.restoreProfession(name);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored "$name"')),
    );
  }

  Future<void> _deleteForever(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: Text('Delete "$name" and all its records? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    // TODO: also delete DB records tied to this profession once DatabaseHelper support exists
    await SettingsStore.instance.removeProfession(name);
    await SettingsStore.instance.restoreProfession(name); // ensure it’s no longer marked deleted
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "$name" permanently (records not yet removed)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted Professions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deleted.isEmpty
              ? const Center(child: Text('No deleted professions'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deleted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final name = _deleted[index];
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _restore(name),
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Restore'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _deleteForever(name),
                                    icon: const Icon(Icons.delete_forever),
                                    label: const Text('Delete Permanently'),
                                  ),
                                ),
                              ],
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